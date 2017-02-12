#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>

#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>

#import "daemon.h"
#import "daemon.cpp"

#define internal static

@interface Payload : NSObject
+ (void) load;
@end

typedef int CGSConnectionID;
extern CGSConnectionID _CGSDefaultConnection(void);
extern CGError CGSSetWindowAlpha(int Connection, uint32_t WindowID, float Alpha);

internal CGSConnectionID _Connection;
internal Payload *_Instance = nil;

DAEMON_CALLBACK(DaemonCallback)
{
    NSLog(@"daemon: '%s'", Message);
}

@implementation Payload
+ (void) load
{
    NSLog(@"Loading Payload");

    if (!_Instance) {
        _Instance = [[Payload alloc] init];
    }

    NSLog(@"Loaded Payload into: %d, uid: %d, euid: %d", getpid(), getuid(), geteuid());
    _Connection = _CGSDefaultConnection();
    // CGSSetWindowAlpha(_Connection, 58, 0.2);

    int Port = 5050;
    StartDaemon(Port, DaemonCallback);
}
@end
