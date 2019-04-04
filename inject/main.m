#import <Cocoa/Cocoa.h>
#import <ScriptingBridge/ScriptingBridge.h>

int main(int Count, char **Args)
{
    SBApplication *SBApp = [[SBApplication applicationWithBundleIdentifier:@"com.apple.Dock"] retain];
    if (SBApp == nil) return -1;

    [SBApp setTimeout:10*60];
    [SBApp setSendMode:kAEWaitReply];
    [SBApp sendEvent:'ascr' id:'gdut' parameters:0];
    [SBApp setSendMode:kAENoReply];
    [SBApp sendEvent:'CHWM' id:'injc' parameters:0];
    [SBApp release];
}
