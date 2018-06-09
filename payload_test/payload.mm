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
static bool did_init_instances;
static id ds_instance;

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

static void objc_storeStrong(id *object, id value)
{
    id oldValue = *object;
    value = [value retain];
    *object = value;
    [oldValue release];
}

const char *ds_c_pattern = "?? ?? ?? 00 48 8B 38 48 8B B5 E0 FD FF FF 4C 8B BD B8 FE FF FF 4C 89 FA 41 FF D5 48 89 C7 E8 ?? ?? ?? 00 49 89 C5 4C 89 EF 48 8B B5 80 FE FF FF FF 15 ?? ?? ?? 00 48 89 C7 E8 ?? ?? ?? 00 48 89 C3 48 89 9D C8 FE FF FF 4C 89 EF 48 8B 05 ?? ?? ?? 00";
static void init_instances()
{
    uint64_t baseaddr = static_base_address() + image_slide();
    uint64_t ds_instance_addr = baseaddr + 0xe10;

    ds_instance_addr = hex_find_seq(ds_instance_addr, ds_c_pattern);
    if (ds_instance_addr == 0) {
        NSLog(@"[chunkwm-sa] failed to get pointer to dock.spaces! space-switching will not work..");
        ds_instance = nil;
    } else {
        uint32_t offset = *(int32_t *)ds_instance_addr;
        NSLog(@"[chunkwm-sa] dock.spaces found at address 0x%llX", ds_instance_addr + offset + 0x4);
        objc_storeStrong(&ds_instance, *(id *)(ds_instance_addr + offset + 0x4));
    }
}

/*
static uint64_t get_method_imp(const char *name, SEL sel)
{
    Class c = objc_getClass(name);
    return (uint64_t) method_getImplementation(class_getInstanceMethod(c, sel));
}

static uint64_t get_method_pointer_from_call_at_offset(uint64_t arg0, uint64_t arg1)
{
    uint64_t rax = ((*(int8_t *)(arg0 + arg1 + 0x4) & 0xff) << 0x18 | (*(int8_t *)(arg0 + arg1 + 0x3) & 0xff) << 0x10 | (*(int8_t *)(arg0 + arg1 + 0x2) & 0xff) << 0x8 | *(int8_t *)(arg0 + arg1 + 0x1) & 0xff) + 0x5 + arg0 + arg1;
    return rax;
}

static uint64_t fix_animation_duration(uint64_t addr)
{
    const char *pattern = "F2 0F 10 05 ?? ?? ?? 00 BA 00 00 00 00 4C 89 F7 48 8B B5 ?? FF FF FF 48 89 D9 44 8B";
    uint64_t rbx = hex_find_seq(addr, pattern);
    uint64_t r13 = rbx + 0x8;
    uint64_t transition_time = 0;
    // vm_protect(*(int32_t *)*_mach_task_self_, rbx + 0x4, 0x8, 0x0, 0x17);
    uint64_t rax = transition_time - r13;
    *(int8_t *)(rbx + 0x4) = rax;
    *(int8_t *)(rbx + 0x5) = (rax >> 8) & 0xff;
    *(int8_t *)(rbx + 0x6) = transition_time - r13 >> 0x10;
    *(int8_t *)(rbx + 0x7) = transition_time - r13 >> 0x18;
    return rax;
}

static void disable_native_transitions()
{
    uint64_t impl = get_method_imp("Dock.DisplaySpaces", @selector(switchToSpace:fromServer:updatePSN:));
    uint64_t method_at_offset = get_method_pointer_from_call_at_offset(impl, 0x47);
    fix_animation_duration(method_at_offset);
}

static void *get_ivar_pointer(id instance, const char *name)
{
    Ivar ivar = class_getInstanceVariable(object_getClass(instance), name);
    return ivar == NULL ? NULL : (__bridge uint8_t *)instance + ivar_getOffset(ivar);
}

    uint64_t ip = (uint64_t) get_ivar_pointer(display_space, "_currentSpace");
    size_t size = class_getInstanceSize([(*(id *)ip) class]);
    vm_protect(mach_task_self(), ip, size, 0x0, 0x17);
*/

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

static void do_space_change(const char *message)
{
    if (!did_init_instances) {
        did_init_instances = true;
        init_instances();
    }

    if (ds_instance == nil) {
        return;
    }

    Token token = get_token(&message);
    uint64_t dest_space_id = token_to_uint64t(token);
    if (!dest_space_id) {
        return;
    }

    CFStringRef dest_display = CGSCopyManagedDisplayForSpace(_connection, dest_space_id);
    id source_space = objc_msgSend(ds_instance, @selector(currentSpaceforDisplayUUID:), dest_display);
    uint64_t source_space_id = get_space_id(source_space);
    if (source_space_id == dest_space_id) {
        CFRelease(dest_display);
        return;
    }

    id dest_space = nil;
    NSArray *spaces_for_display = (NSArray *) objc_msgSend(ds_instance, @selector(spacesForDisplay:), dest_display);
    for (id space in spaces_for_display) {
        if (dest_space_id == get_space_id(space)) {
            dest_space = space;
            break;
        }
    }

    if (dest_space == nil) {
        CFRelease(dest_display);
        return;
    }

    NSArray *display_spaces = get_ivar_value(ds_instance, "_displaySpaces");
    if (display_spaces == nil) {
        CFRelease(dest_display);
        return;
    }

    for (id display_space in display_spaces) {
        id display_source_space = get_ivar_value(display_space, "_currentSpace");
        if ((display_source_space == nil) ||
            (get_space_id(display_source_space) != source_space_id)) {
            continue;
        }

        NSArray *ns_source_space = @[ @(source_space_id) ];
        NSArray *ns_dest_space = @[ @(dest_space_id) ];
        CGSShowSpaces(_connection, (__bridge CFArrayRef) ns_dest_space);
        CGSHideSpaces(_connection, (__bridge CFArrayRef) ns_source_space);
        CGSManagedDisplaySetCurrentSpace(_connection, dest_display, dest_space_id);
        set_ivar_value(display_space, "_currentSpace", dest_space);
        [ns_dest_space release];
        [ns_source_space release];
        break;
    }

    CFRelease(dest_display);
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

static void handle_message(const char *message)
{
    /*
     * NOTE(koekeishiya): interaction is supposed to happen through an
     * external program (chunkwm), and so we do not bother doing input
     * validation, as the program in question should do this.
     */

    Token token = get_token(&message);
    if (token_equals(token, "space")) {
        do_space_change(message);
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
        NSLog(@"[chunkwm-sa] now listening on port 5050..");
    } else {
        NSLog(@"[chunkwm-sa] failed to spawn thread..");
    }
}
@end
