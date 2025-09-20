//
//  applist.h
//  StikJIT
//
//  Created by Stephen on 3/27/25.
//

#ifndef APPLIST_H
#define APPLIST_H
@import Foundation;
@import UIKit;

#ifdef __cplusplus
extern "C" {
#endif

// Returns a dictionary keyed by bundle ID.
// Each value is a dictionary with keys: "name" (NSString), "version" (NSString),
// "build" (NSString), and "icon" (UIImage or NSNull).
NSDictionary<NSString*, NSDictionary<NSString*, id>*>*
list_installed_apps_with_icons(IdeviceProviderHandle* provider, NSString** error);

#ifdef __cplusplus
} // extern "C"
#endif

#endif /* APPLIST_H */
