//
//  applist.c
//  StikJIT
//
//  Created by Stephen on 3/27/25.
//

#import "idevice.h"
#include <arpa/inet.h>
#include <stdlib.h>
#include <string.h>
#import "applist.h"

NSDictionary<NSString*, NSDictionary<NSString*, id>*>*
list_installed_apps_with_icons(IdeviceProviderHandle* provider, NSString** error) {
    InstallationProxyClientHandle *ipClient = NULL;
    if (installation_proxy_connect_tcp(provider, &ipClient)) {
        *error = @"Failed to connect to installation proxy";
        return nil;
    }

    void *apps = NULL;
    size_t count = 0;
    if (installation_proxy_get_apps(ipClient, "User", NULL, 0, &apps, &count)) {
        installation_proxy_client_free(ipClient);
        *error = @"Failed to get apps";
        return nil;
    }

    NSMutableDictionary<NSString*, NSDictionary<NSString*, id>*> *result =
        [NSMutableDictionary dictionaryWithCapacity:count];

    // Connect SpringBoardServices once for all icon requests
    SpringBoardServicesClientHandle *sbClient = NULL;
    if (springboard_services_connect(provider, &sbClient)) {
        installation_proxy_client_free(ipClient);
        *error = @"Failed to connect to SpringBoard Services";
        return nil;
    }

    for (size_t i = 0; i < count; i++) {
        plist_t app = ((plist_t *)apps)[i];

        // Only include apps with get-task-allow entitlement
        plist_t ent = plist_dict_get_item(app, "Entitlements");
        if (!ent) continue;
        plist_t tnode = plist_dict_get_item(ent, "get-task-allow");
        if (!tnode) continue;
        uint8_t isAllowed = 0;
        plist_get_bool_val(tnode, &isAllowed);
        if (!isAllowed) continue;

        // Bundle ID
        char *bidC = NULL;
        plist_t bidNode = plist_dict_get_item(app, "CFBundleIdentifier");
        plist_get_string_val(bidNode, &bidC);
        if (!bidC || bidC[0] == '\0') {
            free(bidC);
            continue;
        }
        NSString *bundleID = [NSString stringWithUTF8String:bidC];
        free(bidC);

        // App Name
        NSString *appName = @"Unknown";
        char *nameC = NULL;
        plist_t nameNode = plist_dict_get_item(app, "CFBundleName");
        plist_get_string_val(nameNode, &nameC);
        if (nameC && nameC[0] != '\0') {
            appName = [NSString stringWithUTF8String:nameC];
        }
        free(nameC);

        // Version
        NSString *version = @"";
        char *versionC = NULL;
        plist_t versionNode = plist_dict_get_item(app, "CFBundleShortVersionString");
        plist_get_string_val(versionNode, &versionC);
        if (versionC && versionC[0] != '\0') {
            version = [NSString stringWithUTF8String:versionC];
        }
        free(versionC);

        // Build
        NSString *build = @"";
        char *buildC = NULL;
        plist_t buildNode = plist_dict_get_item(app, "CFBundleVersion");
        plist_get_string_val(buildNode, &buildC);
        if (buildC && buildC[0] != '\0') {
            build = [NSString stringWithUTF8String:buildC];
        }
        free(buildC);

        // Icon
        void *pngData = NULL;
        size_t dataLen = 0;
        UIImage *icon = nil;
        if (!springboard_services_get_icon(sbClient, [bundleID UTF8String], &pngData, &dataLen)) {
            NSData *data = [NSData dataWithBytes:pngData length:dataLen];
            free(pngData);
            icon = [UIImage imageWithData:data];
        }

        // Store info
        result[bundleID] = @{
            @"name": appName,
            @"version": version,
            @"build": build,
            @"icon": icon ?: [NSNull null]
        };
    }

    springboard_services_free(sbClient);
    installation_proxy_client_free(ipClient);
    return result;
}
