#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

#include </usr/include/mach-o/getsect.h>
#include </usr/include/mach-o/dyld.h>

#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "daemon.h"
#import "daemon.cpp"

#include <stdio.h>
#include <string.h>
#include <vector>
#include <string>
#include <sstream>

@interface Payload : NSObject
+ (void) load;
@end

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

#define kCGSOnAllWorkspacesTagBit (1 << 11)
#define kCGSNoShadowTagBit (1 << 3)
extern "C" CGError CGSSetWindowTags(int cid, uint32_t wid, const int tags[2], size_t maxTagSize);
extern "C" CGError CGSClearWindowTags(int cid, uint32_t wid, const int tags[2], size_t maxTagSize);

static CGSConnectionID _connection;
static bool did_init_instances;
static id ds_instance;

static void init_instances();

static inline std::vector<std::string>
split_string(char *line, char delim)
{
    std::vector<std::string> elements;
    std::stringstream stream(line);
    std::string temp;

    while (std::getline(stream, temp, delim)) {
        elements.push_back(temp);
    }

    return elements;
}

uint64_t static_base_address(void)
{
    const struct segment_command_64* command = getsegbyname("__TEXT");
    uint64_t addr = command->vmaddr;
    return addr;
}

intptr_t image_slide(void)
{
    char path[1024];
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) != 0) return -1;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if (strcmp(_dyld_get_image_name(i), path) == 0) {
            return _dyld_get_image_vmaddr_slide(i);
        }
    }
    return 0;
}

uint64_t base_address(void)
{
    return static_base_address() + image_slide();
}

const char *ds_c_pattern = "?? ?? ?? 00 48 8B 38 48 8B B5 E0 FD FF FF 4C 8B BD B8 FE FF FF 4C 89 FA 41 FF D5 48 89 C7 E8 ?? ?? ?? 00 49 89 C5 4C 89 EF 48 8B B5 80 FE FF FF FF 15 ?? ?? ?? 00 48 89 C7 E8 ?? ?? ?? 00 48 89 C3 48 89 9D C8 FE FF FF 4C 89 EF 48 8B 05 ?? ?? ?? 00";
uint64_t hex_find_seq(uint64_t baddr, const char *c_pattern)
{
    uint64_t addr = baddr;
    uint64_t pattern_length = (strlen(c_pattern) + 1) / 3;
    char *buffer_a = (char *) calloc(pattern_length, 1);
    char *buffer_b = (char *) calloc(pattern_length, 1);
    int counter = 0;

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
    free(buffer_a);
    free(buffer_b);
    return addr;

loc_5a0c:
    counter = counter + 1;
    if (counter < pattern_length) goto loc_59fa;

loc_5a14:
    if (addr != 0x0) goto loc_5a2d;

    return 0;
}

void dump_class_info(Class c)
{
    const char *name = class_getName(c);
    unsigned int count = 0;
    Ivar *ivar_list = class_copyIvarList(c, &count);
    for (int i = 0; i < count; i++) {
        Ivar ivar = ivar_list[i];
        const char *ivar_name = ivar_getName(ivar);
        NSLog(@"%s ivar: %s", name, ivar_name);
    }
    objc_property_t *property_list = class_copyPropertyList(c, &count);
    for (int i = 0; i < count; i++) {
        objc_property_t property = property_list[i];
        const char *prop_name = property_getName(property);
        NSLog(@"%s property: %s", name, prop_name);
    }
    Method *method_list = class_copyMethodList(c, &count);
    for (int i = 0; i < count; i++) {
        Method method = method_list[i];
        const char *method_name = sel_getName(method_getName(method));
        NSLog(@"%s method: %s", name, method_name);
    }
}

Class dump_class_info(const char *name)
{
    Class c = objc_getClass(name);
    if (c != nil) {
        dump_class_info(c);
    }
    return c;
}

id my_get_ivar(id instance, const char *name)
{
    unsigned int count = 0;
    Ivar *ivar_list = class_copyIvarList([instance class], &count);
    for (int i = 0; i < count; i++) {
        Ivar ivar = ivar_list[i];
        const char *ivar_name = ivar_getName(ivar);
        if (strcmp(ivar_name, name) == 0) {
            return object_getIvar(instance, ivar);
        }
    }
    return nil;
}

void my_set_ivar(id instance, const char *name, id value)
{
    unsigned int count = 0;
    Ivar *ivar_list = class_copyIvarList([instance class], &count);
    for (int i = 0; i < count; i++) {
        Ivar ivar = ivar_list[i];
        const char *ivar_name = ivar_getName(ivar);
        if (strcmp(ivar_name, name) == 0) {
            object_setIvar(instance, ivar, value);
            return;
        }
    }
}

DAEMON_CALLBACK(DaemonCallback)
{
    char *temp = strdup(Message);
    std::vector<std::string> tokens = split_string(temp, ' ');
    free(temp);

    if (!did_init_instances) {
        did_init_instances = true;
        init_instances();
    }

    // NOTE(koekeishiya): interaction is supposed to happen through an
    // external program (chunkwm), and so we do not bother doing input
    // validation, as the program in question should do this.

    if (tokens[0] == "space") {
        if (ds_instance == nil) return;

        uint64_t space_id = 0;
        if (sscanf(tokens[1].c_str(), "%lld", &space_id) == 1) {
            CFStringRef dest_display = CGSCopyManagedDisplayForSpace(_connection, space_id);
            id cspace = objc_msgSend(ds_instance, @selector(currentSpaceforDisplayUUID:), dest_display);
            uint64_t csid = (uint64_t) objc_msgSend(cspace, @selector(spid));
            if (csid == space_id) {
                CFRelease(dest_display);
                return;
            }

            id dest_space = nil;
            NSArray *allspaces = (NSArray *) objc_msgSend(ds_instance, @selector(allUserSpaces));
            for (id space in allspaces) {
                uint64_t sid = (uint64_t) objc_msgSend(space, @selector(spid));
                if (sid == space_id) {
                    dest_space = space;
                    break;
                }
                NSLog(@"dock.spaces allspaces: %lld", sid);
            }

            NSArray *displayspaces = (NSArray*) my_get_ivar(ds_instance, "_displaySpaces");
            for (id dspace in displayspaces) {
                id cspace = my_get_ivar(dspace, "_currentSpace");
                uint64_t sid = (uint64_t) objc_msgSend(cspace, @selector(spid));
                if (sid == csid) {
                    NSArray *NSSSpace = @[ @(csid) ];
                    NSArray *NSASpace = @[ @(space_id) ];
                    CGSShowSpaces(_connection, (__bridge CFArrayRef)NSASpace);
                    CGSHideSpaces(_connection, (__bridge CFArrayRef)NSSSpace);
                    CGSManagedDisplaySetCurrentSpace(_connection, dest_display, space_id);
                    my_set_ivar(dspace, "_currentSpace", dest_space);
                    NSLog(@"dock.displayspaces space: %lld", space_id);
                    break;
                }
            }

            CFRelease(dest_display);
        }
    } else if (tokens[0] == "window_move") {
        uint32_t wid = 0;
        int x = 0;
        int y = 0;

        sscanf(tokens[1].c_str(), "%d", &wid);
        sscanf(tokens[2].c_str(), "%d", &x);
        sscanf(tokens[3].c_str(), "%d", &y);

        CGPoint point = CGPointMake(x, y);
        CGSMoveWindow(_connection, wid, &point);
    } else if (tokens[0] == "window_alpha") {
        uint32_t wid = 0;
        sscanf(tokens[1].c_str(), "%d", &wid);
        float alpha = 1.0f;
        sscanf(tokens[2].c_str(), "%f", &alpha);
        CGSSetWindowAlpha(_connection, wid, alpha);
    } else if (tokens[0] == "window_alpha_fade") {
        uint32_t wid = 0;
        sscanf(tokens[1].c_str(), "%d", &wid);
        float alpha = 1.0f;
        sscanf(tokens[2].c_str(), "%f", &alpha);
        float duration = 0.5f;
        sscanf(tokens[3].c_str(), "%f", &duration);
        CGSSetWindowListAlpha(_connection, &wid, 1, alpha, duration);
    } else if (tokens[0] == "window_level") {
        uint32_t wid = 0;
        sscanf(tokens[1].c_str(), "%d", &wid);

        /*
        enum _CGCommonWindowLevelKey
        {
            kCGBaseWindowLevelKey               =  0,
            kCGMinimumWindowLevelKey            =  1,
            kCGDesktopWindowLevelKey            =  2,
            kCGBackstopMenuLevelKey             =  3,
            kCGNormalWindowLevelKey             =  4,
            kCGFloatingWindowLevelKey           =  5,
            kCGTornOffMenuWindowLevelKey        =  6,
            kCGDockWindowLevelKey               =  7,
            kCGMainMenuWindowLevelKey           =  8,
            kCGStatusWindowLevelKey             =  9,
            kCGModalPanelWindowLevelKey         = 10,
            kCGPopUpMenuWindowLevelKey          = 11,
            kCGDraggingWindowLevelKey           = 12,
            kCGScreenSaverWindowLevelKey        = 13,
            kCGMaximumWindowLevelKey            = 14,
            kCGOverlayWindowLevelKey            = 15,
            kCGHelpWindowLevelKey               = 16,
            kCGUtilityWindowLevelKey            = 17,
            kCGDesktopIconWindowLevelKey        = 18,
            kCGCursorWindowLevelKey             = 19,
            kCGAssistiveTechHighWindowLevelKey  = 20,
            kCGNumberOfWindowLevelKeys
        }; typedef int32_t CGWindowLevelKey;
        */

        int level = 0;
        int key;
        sscanf(tokens[2].c_str(), "%d", &key);
        level = CGWindowLevelForKey(key);
        CGSSetWindowLevel(_connection, wid, level);
    } else if (tokens[0] == "window_sticky") {
        uint32_t wid = 0;
        sscanf(tokens[1].c_str(), "%d", &wid);
        int value = 0;
        sscanf(tokens[2].c_str(), "%d", &value);
        int tags[2] = {0};
        tags[0] |= kCGSOnAllWorkspacesTagBit;
        if (value == 1) {
            CGSSetWindowTags(_connection, wid, tags, 32);
        } else {
            CGSClearWindowTags(_connection, wid, tags, 32);
        }
    } else if (tokens[0] == "window_shadow") {
        uint32_t wid = 0;
        sscanf(tokens[1].c_str(), "%d", &wid);
        int value = 0;
        sscanf(tokens[2].c_str(), "%d", &value);
        int tags[2] = {0};
        tags[0] |= kCGSNoShadowTagBit;
        if (value == 1) {
            CGSClearWindowTags(_connection, wid, tags, 32);
        } else {
            CGSSetWindowTags(_connection, wid, tags, 32);
        }

        /*
          The restoring of the shadow doesn't get drawn until the window
          is either moved, focused or otherwise altered. We slightly flip
          the alpha state to trigger a redrawing after changing the flag.
        */
        float alpha = 0.0f;
        CGSGetWindowAlpha(_connection, wid, &alpha);
        CGSSetWindowAlpha(_connection, wid, alpha - 0.1f);
        CGSSetWindowAlpha(_connection, wid, alpha);
    }
}

static void init_instances()
{
    uint64_t baseaddr = base_address();

    uint64_t ds_instance_addr = baseaddr + 0xe10;
    ds_instance_addr = hex_find_seq(ds_instance_addr, ds_c_pattern);
    uint32_t offset = *(int32_t *)ds_instance_addr;
    NSLog(@"ds location = 0x%llX", ds_instance_addr + offset + 0x4);

    ds_instance = *(id *)(ds_instance_addr + offset + 0x4);
    [ds_instance retain];

    /*
    Class ds_class = [ds_instance class];
    if (ds_class != nil) {
        dump_class_info(ds_class);
    }
    */
}

@implementation Payload
+ (void) load
{
    NSLog(@"[chwm-sa] Loaded");
    _connection = CGSMainConnectionID();

    int port = 5050;
    StartDaemon(port, DaemonCallback);
}
@end
