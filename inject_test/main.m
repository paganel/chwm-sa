#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <ScriptingBridge/ScriptingBridge.h>

#include <stdio.h>
#include <string.h>

@interface Controller : NSObject <SBApplicationDelegate> { }

- (void) eventDidFail:(const AppleEvent *)Event withError:(NSError *)Error;
- (void) Inject;

@end

@implementation Controller

- (void) eventDidFail:(const AppleEvent *)Event withError:(NSError *)Error
{
    return;
}

- (void) Inject
{
    for(NSRunningApplication *Application in [[NSWorkspace sharedWorkspace] runningApplications])
    {
        pid_t PID = Application.processIdentifier;
        const char *Name = [[Application localizedName] UTF8String];
        if(Name)
        {
            if(strcmp(Name, "iTerm2") == 0)
            {
                printf("process found\n");

                SBApplication *SBApp = [SBApplication applicationWithProcessIdentifier:PID];

                [SBApp setTimeout:10*60];
                [SBApp setSendMode:kAEWaitReply];
                [SBApp sendEvent:'ascr' id:'gdut' parameters:0];
                [SBApp setSendMode:kAENoReply];
                [SBApp sendEvent:'CHWM' id:'injc' parameters:0];

                printf("event sent\n");
            }
        }
    }
}

@end

int main(int Count, char **Args)
{
    Controller *_Controller = [[Controller alloc] init];
    [_Controller Inject];
}
