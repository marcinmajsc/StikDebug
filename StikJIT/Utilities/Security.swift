//
//  Security.swift
//  StikJIT
//  from MeloNX
//  Created by s s on 2025/4/6.
//
import Security


typealias SecTaskRef = OpaquePointer
@_silgen_name("SecTaskCopyValueForEntitlement")
func SecTaskCopyValueForEntitlement(
    _ task: SecTaskRef,
    _ entitlement: NSString,
    _ error: NSErrorPointer
) -> CFTypeRef?

@_silgen_name("SecTaskCreateFromSelf")
func SecTaskCreateFromSelf(
    _ allocator: CFAllocator?
) -> SecTaskRef?

func checkAppEntitlement(_ ent: String) -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else {
        print(NSLocalizedString("Failed to create SecTask", comment: ""))
        return false
    }
    
    guard let entitlements = SecTaskCopyValueForEntitlement(task, ent as NSString, nil) else {
        print(NSLocalizedString("Failed to get entitlements", comment: ""))
        return false
    }
    
    return entitlements.boolValue != nil && entitlements.boolValue
}
