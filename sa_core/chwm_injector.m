#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

@interface CHWMInjector : NSObject
@end

@implementation CHWMInjector
@end

static Class _instance;

OSErr CHWMhandleInject(const AppleEvent *event, AppleEvent *reply, long context)
{
    NSLog(@"[chunkwm-sa] injection begin");

    OSErr result = noErr;
    NSBundle* chwm_bundle = [NSBundle bundleForClass:[CHWMInjector class]];
    NSString *payload_path = [chwm_bundle pathForResource:@"chunkwm-sa" ofType:@"bundle"];
    NSBundle *payload_bundle = [NSBundle bundleWithPath:payload_path];

    if (!payload_bundle) {
        NSLog(@"[chunkwm-sa] could not locate payload!");
        result = 2;
        goto end;
    }

    if ([payload_bundle isLoaded]) {
        NSLog(@"[chunkwm-sa] payload has already been loaded!");
        result = 2;
        goto end;
    }

    if (![payload_bundle load]) {
        NSLog(@"[chunkwm-sa] could not load payload!");
        result = 2;
        goto end;
    }

    _instance = [payload_bundle principalClass];

end:
    NSLog(@"[chunkwm-sa] injection end");
    return result;
}
