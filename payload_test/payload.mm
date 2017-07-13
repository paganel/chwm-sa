#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>

#import "daemon.h"
#import "daemon.cpp"

#include <vector>
#include <string>
#include <sstream>

@interface Payload : NSObject
+ (void) load;
@end

typedef int CGSConnectionID;
extern "C" CGSConnectionID CGSMainConnectionID(void);
extern "C" CGError CGSSetWindowAlpha(CGSConnectionID Connection, uint32_t WindowId, float Alpha);
extern "C" CGError CGSSetWindowListAlpha(CGSConnectionID Connection, const uint32_t *WindowList, int WindowCount, float Alpha, float Duration);
extern "C" CGError CGSSetWindowLevel(CGSConnectionID Connection, uint32_t WindowId, int Level);

#define kCGSOnAllWorkspacesTagBit (1 << 11)
extern "C" CGError CGSSetWindowTags(int cid, uint32_t wid, const int tags[2], size_t maxTagSize);
extern "C" CGError CGSClearWindowTags(int cid, uint32_t wid, const int tags[2], size_t maxTagSize);

static CGSConnectionID _Connection;

static inline std::vector<std::string>
SplitString(char *Line, char Delim)
{
    std::vector<std::string> Elements;
    std::stringstream Stream(Line);
    std::string Temp;

    while(std::getline(Stream, Temp, Delim))
        Elements.push_back(Temp);

    return Elements;
}

DAEMON_CALLBACK(DaemonCallback)
{
    NSLog(@"daemon: '%s'", Message);

    char *Temp = strdup(Message);
    std::vector<std::string> Tokens = SplitString(Temp, ' ');
    free(Temp);

    if(Tokens[0] == "window_alpha")
    {
        uint32_t WindowId = 0;
        if(Tokens.size() > 1)
        {
            sscanf(Tokens[1].c_str(), "%d", &WindowId);
        }

        float WindowAlpha = 1.0f;
        if(Tokens.size() > 2)
        {
            sscanf(Tokens[2].c_str(), "%f", &WindowAlpha);
        }

        NSLog(@"window_alpha id: '%d', alpha: '%f'", WindowId, WindowAlpha);
        CGSSetWindowAlpha(_Connection, WindowId, WindowAlpha);
    }
    else if(Tokens[0] == "window_alpha_fade")
    {
        uint32_t WindowId = 0;
        if(Tokens.size() > 1)
        {
            sscanf(Tokens[1].c_str(), "%d", &WindowId);
        }

        float WindowAlpha = 1.0f;
        if(Tokens.size() > 2)
        {
            sscanf(Tokens[2].c_str(), "%f", &WindowAlpha);
        }

        float Duration = 0.5f;
        if(Tokens.size() > 3)
        {
            sscanf(Tokens[3].c_str(), "%f", &Duration);
        }

        CGSSetWindowListAlpha(_Connection, &WindowId, 1, WindowAlpha, Duration);
    }
    else if(Tokens[0] == "window_level")
    {
        uint32_t WindowId = 0;
        if(Tokens.size() > 1)
        {
            sscanf(Tokens[1].c_str(), "%d", &WindowId);
        }

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
        int WindowLevel = 0;
        if(Tokens.size() > 2)
        {
            int WindowLevelKey;
            sscanf(Tokens[2].c_str(), "%d", &WindowLevelKey);
            WindowLevel = CGWindowLevelForKey(WindowLevelKey);
        }

        NSLog(@"window_level id: '%d', level: '%d'", WindowId, WindowLevel);
        CGSSetWindowLevel(_Connection, WindowId, WindowLevel);
    }
    else if(Tokens[0] == "window_sticky")
    {
        uint32_t WindowId = 0;
        if(Tokens.size() > 1)
        {
            sscanf(Tokens[1].c_str(), "%d", &WindowId);
        }

        int Value = 0;
        if(Tokens.size() > 2)
        {
            sscanf(Tokens[2].c_str(), "%d", &Value);
        }

        int Tags[2] = {0};
        Tags[0] |= kCGSOnAllWorkspacesTagBit;
        if(Value == 1)
        {
            CGSSetWindowTags(_Connection, WindowId, Tags, 32);
        }
        else
        {
            CGSClearWindowTags(_Connection, WindowId, Tags, 32);
        }
    }
}

@implementation Payload
+ (void) load
{
    NSLog(@"Loaded Payload into: %d, uid: %d, euid: %d", getpid(), getuid(), geteuid());
    _Connection = CGSMainConnectionID();

    int Port = 5050;
    StartDaemon(Port, DaemonCallback);
}
@end
