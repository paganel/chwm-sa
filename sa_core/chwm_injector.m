#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

@interface Payload: NSObject
+ (void) load;
@end

static Class _instance;

@interface CHWMInjector : NSObject
@end

@implementation CHWMInjector
@end

OSErr CHWMhandleInject(const AppleEvent *event, AppleEvent *reply, long context) {
    NSLog(@"[chunkwm-sa] injection begin");

    NSBundle* chwm_bundle = [NSBundle bundleForClass:[CHWMInjector class]];
    NSString *payload_path = [chwm_bundle pathForResource:@"chunkwm-sa" ofType:@"bundle"];
    NSBundle *payload_bundle = [NSBundle bundleWithPath:payload_path];

    if (!payload_bundle) {
        NSLog(@"[chunkwm-sa] Couldn't find Payload Bundle!");
        return 2;
    }

    NSError *Error;
    if (![payload_bundle loadAndReturnError:&Error]) {
        NSLog(@"[chunkwm-sa] Couldn't load Payload!");
        return 2;
    }

    _instance = [payload_bundle principalClass];
    NSLog(@"[chunkwm-sa] injection end");

    return noErr;
}
