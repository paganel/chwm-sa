#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

#define internal static

@interface Payload: NSObject
+ (void) load;
@end

internal Class _Instance;

@interface CHWMInjector : NSObject
@end

@implementation CHWMInjector
@end

OSErr CHWMhandleInject(const AppleEvent *Event, AppleEvent *Reply, long Context) {
    NSLog(@"CHWM injection begin");

    NSBundle* CHWMBundle = [NSBundle bundleForClass:[CHWMInjector class]];
    NSLog(@"Bundle %@", CHWMBundle);

    NSString *PayloadPath = [CHWMBundle pathForResource:@"chunkwm-sa" ofType:@"bundle"];
    NSLog(@"Payload path %@", PayloadPath);

    NSBundle *PayloadBundle = [NSBundle bundleWithPath:PayloadPath];
    NSLog(@"Payload bundle %@", PayloadBundle);

    if(!PayloadBundle)
    {
        NSLog(@"Couldn't find Payload Bundle!");
        return 2;
    }

    NSError *Error;
    if(![PayloadBundle loadAndReturnError:&Error]) {
        NSLog(@"Couldn't load Payload!");
        return 2;
    }

    _Instance = [PayloadBundle principalClass];
    NSLog(@"CHWM injection end");

    return noErr;
}
