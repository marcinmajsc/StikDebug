//
//  JITEnableContext.m
//  StikJIT
//
//  Created by s s on 2025/3/28.
//
#include "idevice.h"
#include <arpa/inet.h>
#include <stdlib.h>

#include "heartbeat.h"
#include "jit.h"
#include "applist.h" // declares list_installed_apps_with_icons

#include "JITEnableContext.h"
#import "StikDebug-Swift.h"

JITEnableContext* sharedJITContext = nil;

@implementation JITEnableContext {
    bool heartbeatRunning;
    IdeviceProviderHandle* provider;
}

+ (instancetype)shared {
    if (!sharedJITContext) {
        sharedJITContext = [[JITEnableContext alloc] init];
    }
    return sharedJITContext;
}

- (instancetype)init {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* docPathUrl = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL* logURL = [docPathUrl URLByAppendingPathComponent:@"idevice_log.txt"];
    idevice_init_logger(Info, Debug, (char*)logURL.path.UTF8String);
    return self;
}

- (NSError*)errorWithStr:(NSString*)str code:(int)code {
    return [NSError errorWithDomain:@"StikJIT"
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: str }];
}

- (LogFuncC)createCLogger:(LogFunc)logger {
    return ^(const char* format, ...) {
        va_list args;
        va_start(args, format);
        NSString* fmt = [NSString stringWithCString:format encoding:NSASCIIStringEncoding];
        NSString* message = [[NSString alloc] initWithFormat:fmt arguments:args];
        NSLog(@"%@", message);

        if ([message containsString:@"ERROR"] || [message containsString:@"Error"]) {
            [[LogManagerBridge shared] addErrorLog:message];
        } else if ([message containsString:@"WARNING"] || [message containsString:@"Warning"]) {
            [[LogManagerBridge shared] addWarningLog:message];
        } else if ([message containsString:@"DEBUG"]) {
            [[LogManagerBridge shared] addDebugLog:message];
        } else {
            [[LogManagerBridge shared] addInfoLog:message];
        }

        if (logger) {
            logger(message);
        }
        va_end(args);
    };
}

- (IdevicePairingFile*)getPairingFileWithError:(NSError**)error {
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* docPathUrl = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL* pairingFileURL = [docPathUrl URLByAppendingPathComponent:@"pairingFile.plist"];

    if (![fm fileExistsAtPath:pairingFileURL.path]) {
        NSLog(@"Pairing file not found!");
        if (error) {
            *error = [self errorWithStr:@"Pairing file not found!" code:-17];
        }
        return nil;
    }

    IdevicePairingFile* pairingFile = NULL;
    IdeviceFfiError* err = idevice_pairing_file_read(pairingFileURL.fileSystemRepresentation, &pairingFile);
    if (err) {
        if (error) {
            *error = [self errorWithStr:@"Failed to read pairing file!" code:err->code];
        }
        return nil;
    }
    return pairingFile;
}

- (void)startHeartbeatWithCompletionHandler:(HeartbeatCompletionHandler)completionHandler
                                   logger:(LogFunc)logger
{
    NSError* err = nil;
    IdevicePairingFile* pairingFile = [self getPairingFileWithError:&err];
    if (err) {
        if (err.code == -17) { // silently ignore "not found"
            return;
        }
        if (logger) { logger(err.localizedDescription); }
        if (completionHandler) { completionHandler((int)err.code, err.localizedDescription); }
        return;
    }

    if (heartbeatRunning) { return; }
    startHeartbeat(
        pairingFile,
        &provider,
        &heartbeatRunning,
        ^(int result, const char *message) {
            if (completionHandler) {
                completionHandler(result,
                                  [NSString stringWithCString:message encoding:NSASCIIStringEncoding]);
            }
        },
        [self createCLogger:logger]
    );
}

- (void)ensureHeartbeat {
    // wait a bit until heartbeat finishes. wait at most 10s
    int deadline = 50;
    while((!lastHeartbeatDate || [[NSDate now] timeIntervalSinceDate:lastHeartbeatDate] > 15) && deadline) {
        --deadline;
        usleep(200);
    }
}

- (BOOL)debugAppWithBundleID:(NSString*)bundleID logger:(LogFunc)logger jsCallback:(DebugAppCallback)jsCallback {
    if (!provider) {
        if (logger) { logger(@"Provider not initialized!"); }
        NSLog(@"Provider not initialized!");
        return NO;
    }
    [self ensureHeartbeat];
    return debug_app(provider, [bundleID UTF8String], [self createCLogger:logger], jsCallback) == 0;
}

- (BOOL)debugAppWithPID:(int)pid logger:(LogFunc)logger jsCallback:(DebugAppCallback)jsCallback {
    if (!provider) {
        if (logger) { logger(@"Provider not initialized!"); }
        NSLog(@"Provider not initialized!");
        return NO;
    }
    [self ensureHeartbeat];
    return debug_app_pid(provider, pid, [self createCLogger:logger], jsCallback) == 0;
}

// Build a simple map bundleID -> appName from the richer structure.
- (NSDictionary<NSString*, NSString*>*)getAppListWithError:(NSError**)error {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        if (error) { *error = [self errorWithStr:@"Provider not initialized!" code:-1]; }
        return nil;
    }

    NSString* errorStr = nil;
    NSDictionary<NSString*, NSDictionary<NSString*, id>*>* full =
        list_installed_apps_with_icons(provider, &errorStr);
    if (errorStr) {
        if (error) { *error = [self errorWithStr:errorStr code:-17]; }
        return nil;
    }
    if (!full) { return @{}; }

    NSMutableDictionary<NSString*, NSString*>* simple = [NSMutableDictionary dictionaryWithCapacity:full.count];
    [full enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSDictionary<NSString *,id> * _Nonnull obj, BOOL * _Nonnull stop) {
        NSString* name = obj[@"name"];
        if (![name isKindOfClass:[NSString class]] || name.length == 0) { name = @"Unknown"; }
        simple[key] = name;
    }];
    return simple.copy;
}

// Per-app icon fetcher using SpringBoardServices, mirroring applist.m behavior.
- (UIImage*)getAppIconWithBundleId:(NSString*)bundleId error:(NSError**)error {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        if (error) { *error = [self errorWithStr:@"Provider not initialized!" code:-1]; }
        return nil;
    }

    SpringBoardServicesClientHandle *sbClient = NULL;
    if (springboard_services_connect(provider, &sbClient)) {
        if (error) { *error = [self errorWithStr:@"Failed to connect to SpringBoard Services" code:-17]; }
        return nil;
    }

    void *pngData = NULL;
    size_t dataLen = 0;
    UIImage *icon = nil;
    int rc = springboard_services_get_icon(sbClient, [bundleId UTF8String], &pngData, &dataLen);
    if (rc == 0 && pngData && dataLen > 0) {
        NSData *data = [NSData dataWithBytes:pngData length:dataLen];
        free(pngData);
        icon = [UIImage imageWithData:data];
    } else {
        if (pngData) { free(pngData); }
        if (error) { *error = [self errorWithStr:@"Failed to fetch icon" code:rc ?: -17]; }
    }

    springboard_services_free(sbClient);
    return icon;
}

// NEW: Expose the full app metadata (name, version, build, icon) to Swift callers.
- (NSDictionary<NSString*, NSDictionary<NSString*, id>*>*)getDetailedAppListWithError:(NSError**)error {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        if (error) { *error = [self errorWithStr:@"Provider not initialized!" code:-1]; }
        return nil;
    }

    NSString* errorStr = nil;
    NSDictionary<NSString*, NSDictionary<NSString*, id>*>* full =
        list_installed_apps_with_icons(provider, &errorStr);
    if (errorStr) {
        if (error) { *error = [self errorWithStr:errorStr code:-17]; }
        return nil;
    }
    return full ?: @{};
}

- (void)dealloc {
    if (provider) {
        idevice_provider_free(provider);
    }
}

@end
