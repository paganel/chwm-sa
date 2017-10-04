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
extern "C" CGError CGSGetWindowAlpha(CGSConnectionID Connection, uint32_t WindowId, float *outAlpha);
extern "C" CGError CGSSetWindowListAlpha(CGSConnectionID Connection, const uint32_t *WindowList, int WindowCount, float Alpha, float Duration);
extern "C" CGError CGSSetWindowLevel(CGSConnectionID Connection, uint32_t WindowId, int Level);
extern "C" OSStatus CGSMoveWindow(const int cid, const uint32_t wid, CGPoint *point);

#define kCGSOnAllWorkspacesTagBit (1 << 11)
#define kCGSNoShadowTagBit (1 << 3)
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
    char *Temp = strdup(Message);
    std::vector<std::string> Tokens = SplitString(Temp, ' ');
    free(Temp);

    // NOTE(koekeishiya): interaction is supposed to happen through an
    // external program (chunkwm), and so we do not bother doing input
    // validation, as the program in question should do this.

    if(Tokens[0] == "window_move")
    {
        uint32_t WindowId = 0;
        int X = 0;
        int Y = 0;

        sscanf(Tokens[1].c_str(), "%d", &WindowId);
        sscanf(Tokens[2].c_str(), "%d", &X);
        sscanf(Tokens[3].c_str(), "%d", &Y);

        CGPoint Point = CGPointMake(X, Y);
        CGSMoveWindow(_Connection, WindowId, &Point);
    }
    else if(Tokens[0] == "window_alpha")
    {
        uint32_t WindowId = 0;
        sscanf(Tokens[1].c_str(), "%d", &WindowId);
        float WindowAlpha = 1.0f;
        sscanf(Tokens[2].c_str(), "%f", &WindowAlpha);
        CGSSetWindowAlpha(_Connection, WindowId, WindowAlpha);
    }
    else if(Tokens[0] == "window_alpha_fade")
    {
        uint32_t WindowId = 0;
        sscanf(Tokens[1].c_str(), "%d", &WindowId);
        float WindowAlpha = 1.0f;
        sscanf(Tokens[2].c_str(), "%f", &WindowAlpha);
        float Duration = 0.5f;
        sscanf(Tokens[3].c_str(), "%f", &Duration);
        CGSSetWindowListAlpha(_Connection, &WindowId, 1, WindowAlpha, Duration);
    }
    else if(Tokens[0] == "window_level")
    {
        uint32_t WindowId = 0;
        sscanf(Tokens[1].c_str(), "%d", &WindowId);

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
        int WindowLevelKey;
        sscanf(Tokens[2].c_str(), "%d", &WindowLevelKey);
        WindowLevel = CGWindowLevelForKey(WindowLevelKey);
        CGSSetWindowLevel(_Connection, WindowId, WindowLevel);
    }
    else if(Tokens[0] == "window_sticky")
    {
        uint32_t WindowId = 0;
        sscanf(Tokens[1].c_str(), "%d", &WindowId);
        int Value = 0;
        sscanf(Tokens[2].c_str(), "%d", &Value);
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
    else if(Tokens[0] == "window_shadow")
    {
        uint32_t WindowId = 0;
        sscanf(Tokens[1].c_str(), "%d", &WindowId);
        int Value = 0;
        sscanf(Tokens[2].c_str(), "%d", &Value);
        int Tags[2] = {0};

        Tags[0] |= kCGSNoShadowTagBit;
        if(Value == 1)
        {
            CGSClearWindowTags(_Connection, WindowId, Tags, 32);
        }
        else
        {
            CGSSetWindowTags(_Connection, WindowId, Tags, 32);
        }

        /* 
          The restoring of the shadow doesn't get drawn until the window
          is either moved, focused or otherwise altered. We slightly flip 
          the alpha state to trigger a redrawing after changing the flag.
        */
        float OriginalAlpha = 0.0f;
        CGSGetWindowAlpha(_Connection, WindowId, &OriginalAlpha);
        CGSSetWindowAlpha(_Connection, WindowId, OriginalAlpha - 0.1f);
        CGSSetWindowAlpha(_Connection, WindowId, OriginalAlpha);
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
