#include <Foundation/Foundation.h>
#include <Cocoa/Cocoa.h>

#include <mach-o/getsect.h>
#include <mach-o/dyld.h>

#include <objc/message.h>
#include <objc/runtime.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <netdb.h>
#include <dlfcn.h>

#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

typedef int CGSConnectionID;
extern "C" CGSConnectionID CGSMainConnectionID(void);
extern "C" CGError CGSSetWindowAlpha(CGSConnectionID cid, uint32_t wid, float alpha);
extern "C" CGError CGSGetWindowAlpha(CGSConnectionID cid, uint32_t wid, float *out_alpha);
extern "C" CGError CGSSetWindowListAlpha(CGSConnectionID cid, const uint32_t *window_list, int window_count, float alpha, float duration);
extern "C" CGError CGSSetWindowLevel(CGSConnectionID cid, uint32_t wid, int level);
extern "C" OSStatus CGSMoveWindow(const int cid, const uint32_t wid, CGPoint *point);
extern "C" void CGSManagedDisplaySetCurrentSpace(CGSConnectionID cid, CFStringRef display_ref, uint64_t spid);
extern "C" uint64_t CGSManagedDisplayGetCurrentSpace(CGSConnectionID cid, CFStringRef display_ref);
extern "C" CFArrayRef CGSCopyManagedDisplaySpaces(const CGSConnectionID cid);
extern "C" CFStringRef CGSCopyManagedDisplayForSpace(const CGSConnectionID cid, uint64_t spid);
extern "C" void CGSShowSpaces(CGSConnectionID cid, CFArrayRef spaces);
extern "C" void CGSHideSpaces(CGSConnectionID cid, CFArrayRef spaces);

#define BUF_SIZE 256
#define kCGSOnAllWorkspacesTagBit (1 << 11)
#define kCGSNoShadowTagBit (1 << 3)
extern "C" CGError CGSSetWindowTags(int cid, uint32_t wid, const int tags[2], size_t maxTagSize);
extern "C" CGError CGSClearWindowTags(int cid, uint32_t wid, const int tags[2], size_t maxTagSize);

static CGSConnectionID _connection;
static id ds_instance;
static uint64_t add_space_fp;
static uint64_t remove_space_fp;
static Class managed_space;

static socklen_t sin_size = sizeof(struct sockaddr);
static pthread_t daemon_thread;
static int daemon_sockfd;

static void dump_class_info(Class c)
{
    const char *name = class_getName(c);
    unsigned int count = 0;

    Ivar *ivar_list = class_copyIvarList(c, &count);
    for (int i = 0; i < count; i++) {
        Ivar ivar = ivar_list[i];
        const char *ivar_name = ivar_getName(ivar);
        NSLog(@"%s ivar: %s", name, ivar_name);
    }
    if (ivar_list) free(ivar_list);

    objc_property_t *property_list = class_copyPropertyList(c, &count);
    for (int i = 0; i < count; i++) {
        objc_property_t property = property_list[i];
        const char *prop_name = property_getName(property);
        NSLog(@"%s property: %s", name, prop_name);
    }
    if (property_list) free(property_list);

    Method *method_list = class_copyMethodList(c, &count);
    for (int i = 0; i < count; i++) {
        Method method = method_list[i];
        const char *method_name = sel_getName(method_getName(method));
        NSLog(@"%s method: %s", name, method_name);
    }
    if (method_list) free(method_list);
}

static Class dump_class_info(const char *name)
{
    Class c = objc_getClass(name);
    if (c != nil) {
        dump_class_info(c);
    }
    return c;
}

static uint64_t static_base_address(void)
{
    const struct segment_command_64 *command = getsegbyname("__TEXT");
    uint64_t addr = command->vmaddr;
    return addr;
}

static uint64_t image_slide(void)
{
    char path[1024];
    uint32_t size = sizeof(path);

    if (_NSGetExecutablePath(path, &size) != 0) {
        return -1;
    }

    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if (strcmp(_dyld_get_image_name(i), path) == 0) {
            return _dyld_get_image_vmaddr_slide(i);
        }
    }

    return 0;
}

static uint64_t hex_find_seq(uint64_t baddr, const char *c_pattern)
{
    int counter = 0;
    uint64_t addr = baddr;
    uint64_t pattern_length = (strlen(c_pattern) + 1) / 3;

    char buffer_a[pattern_length];
    char buffer_b[pattern_length];
    memset(buffer_a, '\0', sizeof(buffer_a));
    memset(buffer_b, '\0', sizeof(buffer_b));

    char *pattern = (char *) c_pattern + 1;
    for (int i = 0; i < pattern_length; ++i) {
        char c = pattern[-1];
        if (c == '?') {
            buffer_b[i] = 1;
        } else {
            int temp = 9;
            if (c <= '9') {
                temp = 0;
            }
            temp = (temp + c) << 0x4;
            c = pattern[0];
            int temp2 = 0xc9;
            if (c <= '9') {
                temp2 = 0xd0;
            }
            buffer_a[i] = temp2 + c + temp;
        }
        pattern += 3;
    }
    goto loc_59f2;

loc_59f2:
    if (pattern_length < 3) goto loc_5a14;

loc_59f8:
    counter = 0;
    goto loc_59fa;

loc_59fa:
    if (buffer_b[counter] != 0 || ((char *)addr)[counter] == buffer_a[counter]) goto loc_5a0c;

loc_5a19:
    addr = (uint64_t)((char *)addr + 1);
    if (addr - baddr < 0x186a0) goto loc_59f2;

loc_5a2a:
    addr = 0;
    goto loc_5a2d;

loc_5a2d:
    return addr;

loc_5a0c:
    counter = counter + 1;
    if (counter < pattern_length) goto loc_59fa;

loc_5a14:
    if (addr != 0x0) goto loc_5a2d;

    return 0;
}

enum MacOS_Version {
    MACOS_UNSUPPORTED = 0,
    MACOS_HIGH_SIERRA = 1,
    MACOS_MOJAVE      = 2,

    MACOS_VERSION_COUNT
};

MacOS_Version get_macos_version()
{
    NSOperatingSystemVersion os_version = [[NSProcessInfo processInfo] operatingSystemVersion];
    switch (os_version.minorVersion) {
    case 14: return MACOS_MOJAVE;
    case 13: return MACOS_HIGH_SIERRA;
    default: return MACOS_UNSUPPORTED;
    }
}

uint64_t dock_spaces_offset[MACOS_VERSION_COUNT] = {
    [MACOS_HIGH_SIERRA] = 0xe10,
    [MACOS_MOJAVE]      = 0x9a00
};

uint64_t add_space_offset[] = {
    [MACOS_HIGH_SIERRA] = 0x335000,
    [MACOS_MOJAVE]      = 0x27e500
};

uint64_t remove_space_offset[] = {
    [MACOS_HIGH_SIERRA] = 0x495000,
    [MACOS_MOJAVE]      = 0x37fb00
};

const char *dock_spaces_pattern[MACOS_VERSION_COUNT] =  {
    [MACOS_HIGH_SIERRA] = "?? ?? ?? 00 48 8B 38 48 8B B5 E0 FD FF FF 4C 8B BD B8 FE FF FF 4C 89 FA 41 FF D5 48 89 C7 E8 ?? ?? ?? 00 49 89 C5 4C 89 EF 48 8B B5 80 FE FF FF FF 15 ?? ?? ?? 00 48 89 C7 E8 ?? ?? ?? 00 48 89 C3 48 89 9D C8 FE FF FF 4C 89 EF 48 8B 05 ?? ?? ?? 00",
    [MACOS_MOJAVE]      = "?? ?? ?? 00 49 8B 3C 24 48 8B 35 ?? E9 4C 00 44 89 BD 94 FE FF FF 44 89 FA 41 FF D5 48 89 C7 E8 45 0C 3D 00 48 ?? 85 40 FE FF FF 48 8B 3D ?? 40 4D 00 48 89 DE 41 FF D5 48 8B 35 ?? ?? 4C 00 31 D2 48 89 C7 41 FF D5 48 89 85 70 FE FF FF 49 8B 3C 24"
};

const char *add_space_pattern[MACOS_VERSION_COUNT] =  {
    [MACOS_HIGH_SIERRA] = "55 48 89 E5 41 57 41 56 41 55 41 54 53 48 83 EC 38 4C 89 6D B0 49 89 FC 48 BB 01 00 00 00 00 00 00 C0 48 B9 01 00 00 00 00 00 00 80 49 BF F8 FF FF FF FF FF FF 00 49 8D 45 28 48 89 45 C0 4D 8B 75 28 41 80 7D 38 01 4C 89 65 C8",
    [MACOS_MOJAVE]      = "55 48 89 E5 41 57 41 56 41 55 41 54 53 48 83 EC 18 48 89 7D C0 41 8A 5D 30 4C 89 6D C8 4D 8B 65 20 4C 89 E7 E8 8B 17 15 00 4C 89 E7 E8 0F 7E F3 FF 49 89 C6 4D 89 F7 80 FB 01 74 6E 4D 85 F6 0F 84 24 01 00 00 49 FF CE 0F 80 7E 02 00 00 48 BB 03 00 00 00 00 00 00 C0 31 F6 49 85 DC 40 0F 94 C6 4C 89 F7 4C 89 E2 E8 F4 7E 10 00 49 85 DC 0F 85 29 02 00 00 4F 8B 6C F4 20 4C 89 EF E8 92 14 15 00 48 8B 05 6F 8E 1C 00 48 89 C3 48 8B 08 49 23 4D 00 FF 91 80 00 00 00 88 45 D0 4C 89 EF E8 6A 14 15 00 F6 45 D0 01 74 08 4C 89 E7 E9 ED 00 00 00 4D 85 F6 49 89 DF 0F 84 AB 00 00 00 49 FF CE 0F 80 9E 00 00 00 48 B8 F8 FF FF FF FF FF FF 00 4C 21 E0 48 89 45 D0 48 B8 03 00 00 00 00 00 00 C0 49 85 C4 74 27 4C 89 E7 E8 C5 16 15 00 4C 89 F7 4C 89 E6 48 8D 15 64 11 F7 FF E8 8F C4 00 00 48 89 C3 4C 89 E7 E8 9C 16 15 00 EB 25 48 8B 05 7B 83 1C 00"
};

const char *remove_space_pattern[MACOS_VERSION_COUNT] =  {
    [MACOS_HIGH_SIERRA] = "55 48 89 E5 41 57 41 56 41 55 41 54 53 48 83 EC 68 4C 89 45 80 48 89 4D C0 48 89 55 D0 48 89 F3 49 89 FC 49 BE 01 00 00 00 00 00 00 C0 49 89 DD E8 ?? ?? E9 FF 49 89 C7 4D 85 F7",
    [MACOS_MOJAVE]      = "55 48 89 E5 41 57 41 56 41 55 41 54 53 48 83 EC 48 48 89 4D A0 49 89 D4 49 89 F7 49 89 FE 4D 89 FD E8 ?? ?? EF FF 48 89 C3 48 89 DF E8 ?? ?? ?? FF 48 83 F8 02 0F 8C 94 01 00 00 4C 89 7D A8 48 89 5D B8"
};

static void init_instances()
{
    MacOS_Version os_version = get_macos_version();
    if (os_version == MACOS_UNSUPPORTED) {
        NSLog(@"[chunkwm-sa] spaces functionality is only supported on macOS High Sierra and Mojave!");
        return;
    }

    uint64_t baseaddr = static_base_address() + image_slide();
    uint64_t ds_instance_addr = hex_find_seq(baseaddr + dock_spaces_offset[os_version], dock_spaces_pattern[os_version]);
    if (ds_instance_addr == 0) {
        NSLog(@"[chunkwm-sa] could not locate pointer to dock.spaces! spaces functionality will not work!");
        return;
    }

    uint32_t offset = *(int32_t *)ds_instance_addr;
    NSLog(@"[chunkwm-sa] (0x%llx) dock.spaces found at address 0x%llX (0x%llx)", baseaddr, ds_instance_addr + offset + 0x4, ds_instance_addr - baseaddr);
    ds_instance = [(*(id *)(ds_instance_addr + offset + 0x4)) retain];

    uint64_t add_space_addr = hex_find_seq(baseaddr + add_space_offset[os_version], add_space_pattern[os_version]);
    if (add_space_addr == 0x0) {
        NSLog(@"[chunkwm-sa] failed to get pointer to addSpace function..");
        add_space_fp = 0;
    } else {
        NSLog(@"[chunkwm-sa] (0x%llx) addSpace found at address 0x%llX (0x%llx)", baseaddr, add_space_addr, add_space_addr - baseaddr);
        add_space_fp = add_space_addr;
    }

    uint64_t remove_space_addr = hex_find_seq(baseaddr + remove_space_offset[os_version], remove_space_pattern[os_version]);
    if (remove_space_addr == 0x0) {
        NSLog(@"[chunkwm-sa] failed to get pointer to removeSpace function..");
        remove_space_fp = 0;
    } else {
        NSLog(@"[chunkwm-sa] (0x%llx) removeSpace found at address 0x%llX (0x%llx)", baseaddr, remove_space_addr, remove_space_addr - baseaddr);
        remove_space_fp = remove_space_addr;
    }

    managed_space = objc_getClass("Dock.ManagedSpace");
}

static inline id get_ivar_value(id instance, const char *name)
{
    id result = nil;
    object_getInstanceVariable(instance, name, (void **) &result);
    return result;
}

static inline void set_ivar_value(id instance, const char *name, id value)
{
    object_setInstanceVariable(instance, name, value);
}

static inline uint64_t get_space_id(id space)
{
    return (uint64_t) objc_msgSend(space, @selector(spid));
}

static inline id space_for_display_with_id(CFStringRef display_uuid, uint64_t space_id)
{
    NSArray *spaces_for_display = (NSArray *) objc_msgSend(ds_instance, @selector(spacesForDisplay:), display_uuid);
    for (id space in spaces_for_display) {
        if (space_id == get_space_id(space)) {
            return space;
        }
    }
    return nil;
}

static inline id display_space_for_space_with_id(uint64_t space_id)
{
    NSArray *display_spaces = get_ivar_value(ds_instance, "_displaySpaces");
    if (display_spaces != nil) {
        for (id display_space in display_spaces) {
            id display_source_space = get_ivar_value(display_space, "_currentSpace");
            if (get_space_id(display_source_space) == space_id) {
                return display_space;
            }
        }
    }
    return nil;
}

static inline id display_space_uuid(id display_space)
{
    id display_uuid = get_ivar_value(display_space, "displayUUID");
    return display_uuid;
}

struct Token
{
    const char *text;
    unsigned int length;
};

static bool token_equals(Token token, const char *match)
{
    const char *at = match;
    for (int i = 0; i < token.length; ++i, ++at) {
        if ((*at == 0) || (token.text[i] != *at)) {
            return false;
        }
    }
    return *at == 0;
}

static uint64_t token_to_uint64t(Token token)
{
    uint64_t result = 0;
    char buffer[token.length + 1];
    memcpy(buffer, token.text, token.length);
    buffer[token.length] = '\0';
    sscanf(buffer, "%lld", &result);
    return result;
}

static uint32_t token_to_uint32t(Token token)
{
    uint32_t result = 0;
    char buffer[token.length + 1];
    memcpy(buffer, token.text, token.length);
    buffer[token.length] = '\0';
    sscanf(buffer, "%d", &result);
    return result;
}

static int token_to_int(Token token)
{
    int result = 0;
    char buffer[token.length + 1];
    memcpy(buffer, token.text, token.length);
    buffer[token.length] = '\0';
    sscanf(buffer, "%d", &result);
    return result;
}

static float token_to_float(Token token)
{
    float result = 0.0f;
    char buffer[token.length + 1];
    memcpy(buffer, token.text, token.length);
    buffer[token.length] = '\0';
    sscanf(buffer, "%f", &result);
    return result;
}

static Token get_token(const char **message)
{
    Token token;

    token.text = *message;
    while (**message && !isspace(**message)) {
        ++(*message);
    }
    token.length = *message - token.text;

    if (isspace(**message)) {
        ++(*message);
    } else {
        // NOTE(koekeishiya): don't go past the null-terminator
    }

    return token;
}

typedef void (*remove_space_call)(id space, id display_space, id ds_instance, uint64_t space_id1, uint64_t space_id2);
static void do_space_destroy(const char *message)
{
    Token space_id_token = get_token(&message);
    uint64_t space_id = token_to_uint64t(space_id_token);
    CFStringRef display_uuid = CGSCopyManagedDisplayForSpace(_connection, space_id);
    id space = objc_msgSend(ds_instance, @selector(currentSpaceforDisplayUUID:), display_uuid);
    id display_space = display_space_for_space_with_id(space_id);
    ((remove_space_call) remove_space_fp)(space, display_space, ds_instance, space_id, space_id);
    uint64_t dest_space_id = CGSManagedDisplayGetCurrentSpace(_connection, display_uuid);
    id dest_space = space_for_display_with_id(display_uuid, dest_space_id);
    set_ivar_value(display_space, "_currentSpace", [dest_space retain]);
    CFRelease(display_uuid);
}

#define asm__call_add_space(v0,v1,func) \
        __asm__("movq %0, %%rdi;""movq %1, %%r13;""callq *%2;" : :"r"(v0), "r"(v1), "r"(func) :"%rdi", "%r13");
static void do_space_create(const char *message)
{
    Token space_id_token = get_token(&message);
    uint64_t __block space_id = token_to_uint64t(space_id_token);
    volatile bool __block is_finished = false;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0), dispatch_get_main_queue(), ^{
        id new_space = [[managed_space alloc] init];
        id display_space = display_space_for_space_with_id(space_id);
        asm__call_add_space(new_space, display_space, add_space_fp);
        is_finished = true;
    });
    while (!is_finished) { /* maybe spin lock */ }
}

static void do_space_change(const char *message)
{
    Token token = get_token(&message);
    uint64_t dest_space_id = token_to_uint64t(token);
    if (dest_space_id) {
        CFStringRef dest_display = CGSCopyManagedDisplayForSpace(_connection, dest_space_id);
        id source_space = objc_msgSend(ds_instance, @selector(currentSpaceforDisplayUUID:), dest_display);
        uint64_t source_space_id = get_space_id(source_space);

        if (source_space_id != dest_space_id) {
            id dest_space = space_for_display_with_id(dest_display, dest_space_id);
            if (dest_space != nil) {
                id display_space = display_space_for_space_with_id(source_space_id);
                if (display_space != nil) {
                    NSArray *ns_source_space = @[ @(source_space_id) ];
                    NSArray *ns_dest_space = @[ @(dest_space_id) ];
                    CGSShowSpaces(_connection, (__bridge CFArrayRef) ns_dest_space);
                    CGSHideSpaces(_connection, (__bridge CFArrayRef) ns_source_space);
                    CGSManagedDisplaySetCurrentSpace(_connection, dest_display, dest_space_id);
                    set_ivar_value(display_space, "_currentSpace", [dest_space retain]);
                    [ns_dest_space release];
                    [ns_source_space release];
                }
            }
        }
        CFRelease(dest_display);
    }
}

static void do_window_move(const char *message)
{
    Token wid_token = get_token(&message);
    uint32_t wid = token_to_uint32t(wid_token);
    Token x_token = get_token(&message);
    int x = token_to_int(x_token);
    Token y_token = get_token(&message);
    int y = token_to_int(y_token);
    CGPoint point = CGPointMake(x, y);
    CGSMoveWindow(_connection, wid, &point);
}

static void do_window_alpha(const char *message)
{
    Token wid_token = get_token(&message);
    uint32_t wid = token_to_uint32t(wid_token);
    Token alpha_token = get_token(&message);
    float alpha = token_to_float(alpha_token);
    CGSSetWindowAlpha(_connection, wid, alpha);
}

static void do_window_alpha_fade(const char *message)
{
    Token wid_token = get_token(&message);
    uint32_t wid = token_to_uint32t(wid_token);
    Token alpha_token = get_token(&message);
    float alpha = token_to_float(alpha_token);
    Token duration_token = get_token(&message);
    float duration = token_to_float(duration_token);
    CGSSetWindowListAlpha(_connection, &wid, 1, alpha, duration);
}

static void do_window_level(const char *message)
{
    Token wid_token = get_token(&message);
    uint32_t wid = token_to_uint32t(wid_token);
    Token key_token = get_token(&message);
    int key = token_to_int(key_token);
    CGSSetWindowLevel(_connection, wid, CGWindowLevelForKey(key));
}

static void do_window_sticky(const char *message)
{
    Token wid_token = get_token(&message);
    uint32_t wid = token_to_uint32t(wid_token);
    Token value_token = get_token(&message);
    int value = token_to_int(value_token);
    int tags[2] = { kCGSOnAllWorkspacesTagBit, 0 };
    if (value == 1) {
        CGSSetWindowTags(_connection, wid, tags, 32);
    } else {
        CGSClearWindowTags(_connection, wid, tags, 32);
    }
}

static void do_window_shadow(const char *message)
{
    Token wid_token = get_token(&message);
    uint32_t wid = token_to_uint32t(wid_token);
    Token value_token = get_token(&message);
    int value = token_to_int(value_token);
    int tags[2] = { kCGSNoShadowTagBit,  0};
    if (value == 1) {
        CGSClearWindowTags(_connection, wid, tags, 32);
    } else {
        CGSSetWindowTags(_connection, wid, tags, 32);
    }

    /*
     * The restoring of the shadow doesn't get drawn until the window
     * is either moved, focused or otherwise altered. We slightly flip
     * the alpha state to trigger a redrawing after changing the flag.
     */

    float alpha = 0.0f;
    CGSGetWindowAlpha(_connection, wid, &alpha);
    CGSSetWindowAlpha(_connection, wid, alpha - 0.1f);
    CGSSetWindowAlpha(_connection, wid, alpha);
}

static inline bool can_focus_space()
{
    return ds_instance != nil;
}

static inline bool can_create_space()
{
    return ds_instance != nil && add_space_fp != 0;
}

static inline bool can_destroy_space()
{
    return ds_instance != nil && remove_space_fp != 0;
}

static void handle_message(const char *message)
{
    /*
     * NOTE(koekeishiya): interaction is supposed to happen through an
     * external program (chunkwm), and so we do not bother doing input
     * validation, as the program in question should do this.
     */

    Token token = get_token(&message);
    if (token_equals(token, "space")) {
        if (!can_focus_space()) return;
        do_space_change(message);
    } else if (token_equals(token, "space_create")) {
        if (!can_create_space()) return;
        do_space_create(message);
    } else if (token_equals(token, "space_destroy")) {
        if (!can_destroy_space()) return;
        do_space_destroy(message);
    } else if (token_equals(token, "window_move")) {
        do_window_move(message);
    } else if (token_equals(token, "window_alpha")) {
        do_window_alpha(message);
    } else if (token_equals(token, "window_alpha_fade")) {
        do_window_alpha_fade(message);
    } else if (token_equals(token, "window_level")) {
        do_window_level(message);
    } else if (token_equals(token, "window_sticky")) {
        do_window_sticky(message);
    } else if (token_equals(token, "window_shadow")) {
        do_window_shadow(message);
    }
}

static bool recv_socket(int sockfd, char *message, size_t message_size)
{
    int len = recv(sockfd, message, message_size, 0);
    if (len > 0) {
        message[len] = '\0';
        return true;
    }
    return false;
}

static void *handle_connection(void *unused)
{
    while (1) {
        struct sockaddr_in client_addr;
        int sockfd = accept(daemon_sockfd, (struct sockaddr*)&client_addr, &sin_size);
        if (sockfd != -1) {
            char message[BUF_SIZE];
            if (recv_socket(sockfd, message, sizeof(message))) {
                handle_message(message);
            }
            shutdown(sockfd, SHUT_RDWR);
            close(sockfd);
        }
    }
    return NULL;
}

static bool start_daemon(int port)
{
    struct sockaddr_in srv_addr;
    int _true = 1;

    if ((daemon_sockfd = socket(PF_INET, SOCK_STREAM, 0)) == -1) {
        return false;
    }

    srv_addr.sin_family = AF_INET;
    srv_addr.sin_port = htons(port);
    srv_addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    memset(&srv_addr.sin_zero, '\0', 8);
    setsockopt(daemon_sockfd, SOL_SOCKET, SO_REUSEADDR, &_true, sizeof(int));

    if (bind(daemon_sockfd, (struct sockaddr*)&srv_addr, sizeof(struct sockaddr)) == -1) {
        return false;
    }

    if (listen(daemon_sockfd, 10) == -1) {
        return false;
    }

    pthread_create(&daemon_thread, NULL, &handle_connection, NULL);
    return true;
}

@interface Payload : NSObject
+ (void) load;
@end

@implementation Payload
+ (void) load
{
    NSLog(@"[chunkwm-sa] loaded payload");
    _connection = CGSMainConnectionID();

    if (start_daemon(5050)) {
        init_instances();
        NSLog(@"[chunkwm-sa] now listening on port 5050..");
    } else {
        NSLog(@"[chunkwm-sa] failed to spawn thread..");
    }
}
@end
