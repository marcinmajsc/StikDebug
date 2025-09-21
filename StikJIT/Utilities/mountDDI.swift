//
//  mountDDI.swift
//  StikJIT
//
//  Created by Stossy11 on 29/03/2025.
//

import Foundation

typealias IdevicePairingFile = OpaquePointer
typealias TcpProviderHandle = OpaquePointer
typealias CoreDeviceProxyHandle = OpaquePointer
typealias AdapterHandle = OpaquePointer
typealias ImageMounterHandle = OpaquePointer
typealias LockdowndClientHandle = OpaquePointer

func progressCallback(progress: size_t, total: size_t, context: UnsafeMutableRawPointer?) {
    MountingProgress.shared.progressCallback(progress: progress, total: total, context: context)
}

func readFile(path: String) -> Data? {
    guard let file = fopen(path, "rb") else {
        perror(NSLocalizedString("Failed to open file", comment: ""))
        return nil
    }
    
    fseek(file, 0, SEEK_END)
    let fileSize = ftell(file)
    fseek(file, 0, SEEK_SET)
    
    guard fileSize > 0 else {
        fclose(file)
        return nil
    }
    
    var buffer = Data(count: fileSize)
    buffer.withUnsafeMutableBytes { ptr in
        fread(ptr.baseAddress, 1, fileSize, file)
    }
    
    fclose(file)
    return buffer
}

func htons(_ value: UInt16) -> UInt16 {
    return CFSwapInt16HostToBig(value)
}

func isMounted() -> Bool {
    var addr = sockaddr_in()
    memset(&addr, 0, MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = htons(UInt16(LOCKDOWN_PORT))
    let sockaddrPointer = UnsafeRawPointer(&addr).bindMemory(to: sockaddr.self, capacity: 1)
    
    let pairingFilePath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
    
    guard inet_pton(AF_INET, "10.7.0.1", &addr.sin_addr) == 1 else {
        print(NSLocalizedString("Invalid IP address", comment: ""))
        return false
    }

    // Read pairing file
    var pairingFile: IdevicePairingFile?
    let err = idevice_pairing_file_read(pairingFilePath, &pairingFile)
    if let err {
        print(String(format: NSLocalizedString("Failed to read pairing file: %@", comment: "Pairing file read failure"), String(describing: err)))
        return false
    }

    // Create TCP provider
    var provider: TcpProviderHandle?
    let providerError = idevice_tcp_provider_new(sockaddrPointer, pairingFile, "ImageMounterTest", &provider)
    if let providerError {
        print(String(format: NSLocalizedString("Failed to create TCP provider: %@", comment: "TCP provider creation failure"), String(describing: providerError)))
        return false
    }

    // Connect to image mounter
    var client: ImageMounterHandle?
    let connectError = image_mounter_connect(provider, &client)
    if let connectError {
        print(String(format: NSLocalizedString("Failed to connect to image mounter: %@", comment: "Image mounter connect failure"), String(describing: connectError)))
        return false
    }
    idevice_provider_free(provider)
    
    var devices: UnsafeMutableRawPointer?
    var devicesLen: size_t = 0
    let listError = image_mounter_copy_devices(client, &devices, &devicesLen)
    if listError == nil {
        let deviceList = devices?.assumingMemoryBound(to: plist_t.self)
        var devices: [String] = []
        for i in 0..<devicesLen {
            let device = deviceList?[i]
            var xmlData: UnsafeMutablePointer<CChar>?
            var xmlLength: Int32 = 0
            
            // Use libplist function to convert to XML
            plist_to_xml(device, &xmlData, &xmlLength)
            if let xml = xmlData {
                devices.append("\(xml)")
            }
            plist_mem_free(xmlData)
            plist_free(device)
        }

        image_mounter_free(client)
        return devices.count != 0
    } else {
        print(String(format: NSLocalizedString("Failed to get device list: %@", comment: "Device list retrieval failure"), String(describing: listError)))
        return false
    }
}

func mountPersonalDDI(deviceIP: String = "10.7.0.1", imagePath: String, trustcachePath: String, manifestPath: String, pairingFilePath: String) -> Int {
    idevice_init_logger(Debug, Disabled, nil)
    
    print(String(format: NSLocalizedString("Mounting %@ %@ %@", comment: "Mounting image, trustcache, manifest paths"), imagePath, trustcachePath, manifestPath))
    
    guard let image = readFile(path: imagePath),
          let trustcache = readFile(path: trustcachePath),
          let buildManifest = readFile(path: manifestPath) else {
        print(NSLocalizedString("Failed to read one or more files", comment: ""))
        return 1 // EC: 1
    }
    
    var addr = sockaddr_in()
    memset(&addr, 0, MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = htons(UInt16(LOCKDOWN_PORT))
    let sockaddrPointer = UnsafeRawPointer(&addr).bindMemory(to: sockaddr.self, capacity: 1)
    
    guard inet_pton(AF_INET, deviceIP, &addr.sin_addr) == 1 else {
        print(NSLocalizedString("Invalid IP address", comment: ""))
        return 2 // EC: 2
    }

    var pairingFile: IdevicePairingFile?
    let err = idevice_pairing_file_read(pairingFilePath.cString(using: .utf8), &pairingFile)
    if let err {
        print(String(format: NSLocalizedString("Failed to read pairing file: %d", comment: "Pairing file read failure code"), err.pointee.code))
        return 3 // EC: 3
    }


    var provider: TcpProviderHandle?
    let providerError = idevice_tcp_provider_new(sockaddrPointer, pairingFile, "ImageMounterTest".cString(using: .utf8), &provider)
    if let providerError {
        print(String(format: NSLocalizedString("Failed to create TCP provider: %@", comment: "TCP provider creation failure"), String(describing: providerError)))
        return 4 // EC: 4
    }
    
    
    var pairingFile2: IdevicePairingFile?
    let P2err = idevice_pairing_file_read(pairingFilePath.cString(using: .utf8), &pairingFile2)
    if let P2err {
        print(String(format: NSLocalizedString("Failed to read pairing file: %d", comment: "Pairing file read failure code"), P2err.pointee.code))
        return 5 // EC: 5
    }
    
    var lockdownClient: LockdowndClientHandle?
    if let err = lockdownd_connect(provider, &lockdownClient) {
        print(NSLocalizedString("Failed to connect to lockdownd", comment: ""))
        return 6 // EC: 6
    }
    
    if let err = lockdownd_start_session(lockdownClient, pairingFile2) {
        print(NSLocalizedString("Failed to start session", comment: ""))
        return 7 // EC: 7
    }
    
    var uniqueChipIDPlist: plist_t?
    if let err = lockdownd_get_value(lockdownClient, "UniqueChipID".cString(using: .utf8), nil, &uniqueChipIDPlist) {
        print(NSLocalizedString("Failed to get UniqueChipID", comment: ""))
        return 8 // EC: 8
    }
    
    var uniqueChipID: UInt64 = 0
    plist_get_uint_val(uniqueChipIDPlist, &uniqueChipID)
    plist_free(uniqueChipIDPlist)
    print(uniqueChipID)
    
    
    var mounterClient: ImageMounterHandle?
    if let err = image_mounter_connect(provider, &mounterClient) {
        print(NSLocalizedString("Failed to connect to image mounter", comment: ""))
        return 9 // EC: 9
    }
    
    let result = image.withUnsafeBytes { imagePtr in
        trustcache.withUnsafeBytes { trustcachePtr in
            buildManifest.withUnsafeBytes { manifestPtr in
                image_mounter_mount_personalized(
                    mounterClient,
                    provider,
                    imagePtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    image.count,
                    trustcachePtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    trustcache.count,
                    manifestPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    buildManifest.count,
                    nil,
                    uniqueChipID
                )
            }
        }
    }
    
    return Int(result?.pointee.code ?? -1)
}
