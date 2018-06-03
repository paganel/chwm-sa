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

    NSBundle* chwm_bundle = [NSBundle bundleForClass:[CHWMInjector class]];
    NSString *payload_path = [chwm_bundle pathForResource:@"chunkwm-sa" ofType:@"bundle"];
    NSBundle *payload_bundle = [NSBundle bundleWithPath:payload_path];

    if (!payload_bundle) {
        NSLog(@"[chunkwm-sa] could not locate Payload Bundle!");
        return 2;
    }

    NSError *error;
    if (![payload_bundle loadAndReturnError:&error]) {
        NSLog(@"[chunkwm-sa] could not load payload!");
        return 2;
    }

    _instance = [payload_bundle principalClass];
    NSLog(@"[chunkwm-sa] injection end");

    return noErr;
}
