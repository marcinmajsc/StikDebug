//
//  StikJITApp.swift
//  StikJIT
//
//  Created by Stephen on 3/26/25.
//

import SwiftUI
import Network
import UniformTypeIdentifiers
import NetworkExtension

// Register default settings before the app starts
private func registerAdvancedOptionsDefault() {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    // Enable advanced options by default on iOS 19/26 and above
    let enabled = os.majorVersion >= 19
    UserDefaults.standard.register(defaults: ["enableAdvancedOptions": enabled])
    UserDefaults.standard.register(defaults: ["enablePiP": enabled])
}

// MARK: - Welcome Sheet

struct WelcomeSheetView: View {
    var onDismiss: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    
    private var accent: Color {
        customAccentColorHex.isEmpty ? .accentColor : (Color(hex: customAccentColorHex) ?? .accentColor)
    }
    
    var body: some View {
        ZStack {
            // Background now comes from global BackgroundContainer
            Color.clear.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Card container with glassy material and stroke
                    VStack(alignment: .leading, spacing: 16) {
                        // Title
                        Text(NSLocalizedString("Welcome!", comment: ""))
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundColor(.primary)
                            .padding(.top, 8)
                        
                        // Intro
                        Text(NSLocalizedString("Thanks for installing the app. This brief introduction will help you get started.", comment: ""))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                        
                        // App description
                        VStack(alignment: .leading, spacing: 6) {
                            Label(NSLocalizedString("On‑device debugger", comment: ""), systemImage: "bolt.shield.fill")
                                .foregroundColor(accent)
                                .font(.headline)
                            Text(NSLocalizedString("StikDebug is an on‑device debugger designed specifically for self‑developed apps. It helps streamline testing and troubleshooting without sending any data to external servers.", comment: ""))
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        // VPN explanation
                        VStack(alignment: .leading, spacing: 6) {
                            Label(NSLocalizedString("Why VPN permission?", comment: ""), systemImage: "lock.shield.fill")
                                .foregroundColor(accent)
                                .font(.headline)
                            Text(NSLocalizedString("The next step will prompt you to allow VPN permissions. This is necessary for the app to function properly. The VPN configuration allows your device to securely connect to itself — nothing more. No data is collected or sent externally; everything stays on your device.", comment: ""))
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        // Continue button
                        Button(action: { onDismiss?() }) {
                            Text(NSLocalizedString("Continue", comment: ""))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(accent.contrastText())
                                .frame(height: 44)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(accent)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                                )
                        }
                        .padding(.top, 8)
                        .accessibilityIdentifier("welcome_continue_button")
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.15 : 0.08), radius: 12, x: 0, y: 4)
                    
                    // Footer version info for consistency
                    HStack {
                        Spacer()
                        Text(String(format: NSLocalizedString("iOS %@", comment: "Footer version info"), UIDevice.current.systemVersion))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 30)
            }
        }
        // Inherit preferredColorScheme from BackgroundContainer (no local override)
    }
}

// MARK: - VPN Logger

class VPNLogger: ObservableObject {
    @Published var logs: [String] = []
    static var shared = VPNLogger()
    private init() {}
    
    func log(_ message: Any, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        print("[\(fileName):\(line)] \(function): \(message)")
        #endif
        logs.append("\(message)")
    }
}

// MARK: - Tunnel Manager

class TunnelManager: ObservableObject {
    @Published var tunnelStatus: TunnelStatus = .disconnected
    static var shared = TunnelManager()
    
    private var vpnManager: NETunnelProviderManager?
    private var tunnelDeviceIp: String {
        UserDefaults.standard.string(forKey: "TunnelDeviceIP") ?? "10.7.0.0"
    }
    private var tunnelFakeIp: String {
        UserDefaults.standard.string(forKey: "TunnelFakeIP") ?? "10.7.0.1"
    }
    private var tunnelSubnetMask: String {
        UserDefaults.standard.string(forKey: "TunnelSubnetMask") ?? "255.255.255.0"
    }
    private var tunnelBundleId: String {
        Bundle.main.bundleIdentifier!.appending(".TunnelProv")
    }
    
    enum TunnelStatus: String {
        case disconnected = "Disconnected"
        case connecting = "Connecting"
        case connected = "Connected"
        case disconnecting = "Disconnecting"
        case error = "Error"
        
        var localized: String {
            switch self {
            case .disconnected:
                return NSLocalizedString("Disconnected", comment: "VPN tunnel status")
            case .connecting:
                return NSLocalizedString("Connecting", comment: "VPN tunnel status")
            case .connected:
                return NSLocalizedString("Connected", comment: "VPN tunnel status")
            case .disconnecting:
                return NSLocalizedString("Disconnecting", comment: "VPN tunnel status")
            case .error:
                return NSLocalizedString("Error", comment: "VPN tunnel status")
            }
        }
    }
    
    private init() {
        loadTunnelPreferences()
        NotificationCenter.default.addObserver(self, selector: #selector(statusDidChange(_:)), name: .NEVPNStatusDidChange, object: nil)
    }
    
    private func loadTunnelPreferences() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] (managers, error) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    VPNLogger.shared.log(String(format: NSLocalizedString("Error loading preferences: %@", comment: "Tunnel preferences load failure"), error.localizedDescription))
                    self.tunnelStatus = .error
                    return
                }
                if let managers = managers, !managers.isEmpty {
                    for manager in managers {
                        if let proto = manager.protocolConfiguration as? NETunnelProviderProtocol,
                           proto.providerBundleIdentifier == self.tunnelBundleId {
                            self.vpnManager = manager
                            self.updateTunnelStatus(from: manager.connection.status)
                            VPNLogger.shared.log(NSLocalizedString("Loaded existing tunnel configuration", comment: ""))
                            break
                        }
                    }
                    if self.vpnManager == nil, let firstManager = managers.first {
                        self.vpnManager = firstManager
                        self.updateTunnelStatus(from: firstManager.connection.status)
                        VPNLogger.shared.log(NSLocalizedString("Using existing tunnel configuration", comment: ""))
                    }
                } else {
                    VPNLogger.shared.log(NSLocalizedString("No existing tunnel configuration found", comment: ""))
                }
            }
        }
    }
    
    @objc private func statusDidChange(_ notification: Notification) {
        if let connection = notification.object as? NEVPNConnection {
            updateTunnelStatus(from: connection.status)
        }
    }
    
    private func updateTunnelStatus(from connectionStatus: NEVPNStatus) {
        DispatchQueue.main.async {
            switch connectionStatus {
            case .invalid, .disconnected:
                self.tunnelStatus = .disconnected
            case .connecting:
                self.tunnelStatus = .connecting
            case .connected:
                self.tunnelStatus = .connected
            case .disconnecting:
                self.tunnelStatus = .disconnecting
            case .reasserting:
                self.tunnelStatus = .connecting
            @unknown default:
                self.tunnelStatus = .error
            }
            VPNLogger.shared.log(String(format: NSLocalizedString("VPN status updated: %@", comment: "VPN connection state change"), self.tunnelStatus.rawValue))
        }
    }
    
    private func createOrUpdateTunnelConfiguration(completion: @escaping (Bool) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] (managers, error) in
            guard let self = self else { return completion(false) }
            if let error = error {
                VPNLogger.shared.log(String(format: NSLocalizedString("Error loading preferences: %@", comment: "Tunnel preferences load failure"), error.localizedDescription))
                return completion(false)
            }
            
            let manager: NETunnelProviderManager
            if let existingManagers = managers, !existingManagers.isEmpty {
                if let matchingManager = existingManagers.first(where: {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.tunnelBundleId
                }) {
                    manager = matchingManager
                    VPNLogger.shared.log(NSLocalizedString("Updating existing tunnel configuration", comment: ""))
                } else {
                    manager = existingManagers[0]
                    VPNLogger.shared.log(NSLocalizedString("Using first available tunnel configuration", comment: ""))
                }
            } else {
                manager = NETunnelProviderManager()
                VPNLogger.shared.log(NSLocalizedString("Creating new tunnel configuration", comment: ""))
            }
            
            manager.localizedDescription = "StikDebug"
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = self.tunnelBundleId
            proto.serverAddress = NSLocalizedString("StikDebug's Local Network Tunnel", comment: "")
            manager.protocolConfiguration = proto
            manager.isOnDemandEnabled = true
            manager.isEnabled = true
            
            manager.saveToPreferences { [weak self] error in
                guard let self = self else { return completion(false) }
                DispatchQueue.main.async {
                    if let error = error {
                        VPNLogger.shared.log(String(format: NSLocalizedString("Error saving tunnel configuration: %@", comment: "Tunnel save failure"), error.localizedDescription))
                        completion(false)
                        return
                    }
                    self.vpnManager = manager
                    VPNLogger.shared.log(NSLocalizedString("Tunnel configuration saved successfully", comment: ""))
                    completion(true)
                }
            }
        }
    }
    
    func startVPN() {
        if let manager = vpnManager {
            startExistingVPN(manager: manager)
        } else {
            createOrUpdateTunnelConfiguration { [weak self] success in
                guard let self = self, success else { return }
                self.loadTunnelPreferences()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let manager = self.vpnManager {
                        self.startExistingVPN(manager: manager)
                    }
                }
            }
        }
    }
    
    private func startExistingVPN(manager: NETunnelProviderManager) {
        guard tunnelStatus != .connected else {
            VPNLogger.shared.log(NSLocalizedString("Network tunnel is already connected", comment: ""))
            return
        }
        tunnelStatus = .connecting
        let options: [String: NSObject] = [
            "TunnelDeviceIP": tunnelDeviceIp as NSObject,
            "TunnelFakeIP": tunnelFakeIp as NSObject,
            "TunnelSubnetMask": tunnelSubnetMask as NSObject
        ]
        do {
            try manager.connection.startVPNTunnel(options: options)
            VPNLogger.shared.log(NSLocalizedString("Network tunnel start initiated", comment: ""))
        } catch {
            tunnelStatus = .error
            VPNLogger.shared.log(String(format: NSLocalizedString("Failed to start tunnel: %@", comment: "Start VPN tunnel failure"), error.localizedDescription)
            )
        }
    }
    
    func stopVPN() {
        guard let manager = vpnManager else { return }
        tunnelStatus = .disconnecting
        manager.connection.stopVPNTunnel()
        VPNLogger.shared.log(NSLocalizedString("Network tunnel stop initiated", comment: ""))
    }
}

// MARK: - AccentColor Environment Key (leave available but unused)

struct AccentColorKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

extension EnvironmentValues {
    var accentColor: Color {
        get { self[AccentColorKey.self] }
        set { self[AccentColorKey.self] = newValue }
    }
}

// MARK: - Helper Functions and Globals

let fileManager = FileManager.default

func httpGet(_ urlString: String, result: @escaping (String?) -> Void) {
    if let url = URL(string: urlString) {
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print(String(format: NSLocalizedString("Error: %@", comment: "General HTTP GET error"), error.localizedDescription))
                result(nil)
                return
            }
            
            if let data = data, let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print(String(format: NSLocalizedString("Response: %d", comment: "HTTP 200 OK status response"), httpResponse.statusCode))
                    if let dataString = String(data: data, encoding: .utf8) {
                        result(dataString)
                    }
                } else {
                    print(String(format: NSLocalizedString("Received non-200 status code: %d", comment: "HTTP response not OK"), httpResponse.statusCode))
                }
            }
        }
        task.resume()
    }
}

func UpdateRetrieval() -> Bool {
    var ver: String {
        let marketingVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return marketingVersion
    }
    let urlString = "https://raw.githubusercontent.com/0-Blu/StikJIT/refs/heads/main/version.txt"
    var res = false
    httpGet(urlString) { result in
        if let fc = result {
            if ver != fc {
                res = true
            }
        }
    }
    return res
}

// MARK: - DNS Checker

class DNSChecker: ObservableObject {
    @Published var appleIP: String?
    @Published var controlIP: String?
    @Published var dnsError: String?
    
    func checkDNS() {
        checkIfConnectedToWifi { [weak self] wifiConnected in
            guard let self = self else { return }
            if wifiConnected {
                let group = DispatchGroup()
                
                group.enter()
                self.lookupIPAddress(for: "gs.apple.com") { ip in
                    DispatchQueue.main.async {
                        self.appleIP = ip
                    }
                    group.leave()
                }
                
                group.enter()
                self.lookupIPAddress(for: "google.com") { ip in
                    DispatchQueue.main.async {
                        self.controlIP = ip
                    }
                    group.leave()
                }
                
                group.notify(queue: .main) {
                    if self.controlIP == nil {
                        self.dnsError = NSLocalizedString("No internet connection.", comment: "")
                        print(NSLocalizedString("Control host lookup failed, so no internet connection.", comment: ""))
                    } else if self.appleIP == nil {
                        self.dnsError = NSLocalizedString("Apple DNS blocked. Your network might be filtering Apple traffic.", comment: "")
                        print(NSLocalizedString("Control lookup succeeded, but Apple lookup failed: likely blocked.", comment: ""))
                    } else {
                        self.dnsError = nil
                        print(String(format: NSLocalizedString("DNS lookups succeeded: Apple -> %@, Control -> %@", comment: "DNS lookup success log"), self.appleIP!, self.controlIP!))
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.dnsError = nil
                    print(NSLocalizedString("Not connected to WiFi; continuing without DNS check.", comment: ""))
                }
            }
        }
    }
    
    private func checkIfConnectedToWifi(completion: @escaping (Bool) -> Void) {
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        monitor.pathUpdateHandler = { path in
            completion(path.status == .satisfied)
            monitor.cancel()
        }
        let queue = DispatchQueue.global(qos: .background)
        monitor.start(queue: queue)
    }
    
    private func lookupIPAddress(for host: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            var hints = addrinfo(
                ai_flags: 0,
                ai_family: AF_UNSPEC,
                ai_socktype: SOCK_STREAM,
                ai_protocol: 0,
                ai_addrlen: 0,
                ai_canonname: nil,
                ai_addr: nil,
                ai_next: nil
            )
            var res: UnsafeMutablePointer<addrinfo>?
            let err = getaddrinfo(host, nil, &hints, &res)
            if err != 0 {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            var ipAddress: String?
            var ptr = res
            while ptr != nil {
                if let addr = ptr?.pointee.ai_addr {
                    var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, ptr!.pointee.ai_addrlen,
                                   &hostBuffer, socklen_t(hostBuffer.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        ipAddress = String(cString: hostBuffer)
                        break
                    }
                }
                ptr = ptr?.pointee.ai_next
            }
            freeaddrinfo(res)
            DispatchQueue.main.async { completion(ipAddress) }
        }
    }
}

// MARK: - Main App

// Global state variable for the heartbeat response.
var pubHeartBeat = false

@main
struct HeartbeatApp: App {
    @AppStorage("hasLaunchedBefore") var hasLaunchedBefore: Bool = false
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @State private var showWelcomeSheet: Bool = false
    @State private var isLoading2 = true
    @State private var isPairing = false
    @State private var heartBeat = false
    @State private var error: Int32? = nil
    @State private var show_alert = false
    @State private var alert_string = ""
    @State private var alert_title = ""
    @State private var showTimeoutError = false
    @State private var showLogs = false
    @State private var showContinueWarning = false
    @State private var timeoutTimer: Timer?
    @StateObject private var mount = MountingProgress.shared
    @StateObject private var dnsChecker = DNSChecker()
    @Environment(\.scenePhase) private var scenePhase   // Observe scene lifecycle
    
    let urls: [String] = [
        "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/BuildManifest.plist",
        "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/Image.dmg",
        "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/Image.dmg.trustcache"
    ]
    
    let outputDir: String = "DDI"
    
    let outputFiles: [String] = [
        "DDI/BuildManifest.plist",
        "DDI/Image.dmg",
        "DDI/Image.dmg.trustcache"
    ]

    init() {
        registerAdvancedOptionsDefault()
        newVerCheck()
        let fixMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.fix_init(forOpeningContentTypes:asCopy:)))!
        let origMethod = class_getInstanceMethod(UIDocumentPickerViewController.self, #selector(UIDocumentPickerViewController.init(forOpeningContentTypes:asCopy:)))!
        method_exchangeImplementations(origMethod, fixMethod)
        
        // Initialize UIKit tint from stored accent at launch
        HeartbeatApp.updateUIKitTintFromStoredAccent()
    }
    
    // Make this static so we can call it without capturing self in init
    private static func updateUIKitTintFromStoredAccent() {
        let hex = UserDefaults.standard.string(forKey: "customAccentColor") ?? ""
        let color = hex.isEmpty ? UIColor.tintColor : UIColor(Color(hex: hex) ?? .accentColor)
        UIView.appearance().tintColor = color
    }
    
    func newVerCheck() {
        let currentDate = Calendar.current.startOfDay(for: Date())
        let VUA = UserDefaults.standard.object(forKey: "VersionUpdateAlert") as? Date ?? Date.distantPast
        
        if currentDate > Calendar.current.startOfDay(for: VUA) {
            if UpdateRetrieval() {
                alert_title = NSLocalizedString("Update Avaliable!", comment: "")
                let urlString = "https://raw.githubusercontent.com/0-Blu/StikJIT/refs/heads/main/version.txt"
                httpGet(urlString) { result in
                    if result == nil { return }
                    alert_string = String(format: NSLocalizedString("Update to: version %@!", comment: "Prompt to update to a newer app version"), result!)
                    show_alert = true
                }
            }
            UserDefaults.standard.set(currentDate, forKey: "VersionUpdateAlert")
        }
    }
    
    private var globalAccent: Color {
        let hex = customAccentColorHex
        return hex.isEmpty ? .accentColor : (Color(hex: hex) ?? .accentColor)
    }
    
    var body: some Scene {
        WindowGroup {
            BackgroundContainer {
                Group {
                    if isLoading2 {
                        LoadingView(showAlert: $show_alert, alertTitle: $alert_title, alertMessage: $alert_string)
                            .onAppear {
                                dnsChecker.checkDNS()
                                timeoutTimer?.invalidate()
                                timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in
                                    if isLoading2 {
                                        showTimeoutError = true
                                    }
                                }
                                checkVPNConnection() { result, vpn_error in
                                    if result {
                                        if FileManager.default.fileExists(atPath: URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path) {
                                            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                                                if pubHeartBeat {
                                                    isLoading2 = false
                                                    timer.invalidate()
                                                } else {
                                                    if let error {
                                                        if error == -9 {  // InvalidHostID is -9
                                                            isPairing = true
                                                        } else {
                                                            startHeartbeatInBackground()
                                                        }
                                                        self.error = nil
                                                    }
                                                }
                                            }
                                            startHeartbeatInBackground()
                                        } else {
                                            isLoading2 = false
                                        }
                                    } else if let vpn_error {
                                        showAlert(
                                            title: NSLocalizedString("Error", comment: ""),
                                            message: String(format: NSLocalizedString("EM Proxy failed to connect: %@", comment: "VPN connection failure with reason"), vpn_error),
                                            showOk: true
                                        ) { _ in
                                            exit(0)
                                        }
                                    }
                                }
                            }
                            .fileImporter(
                                isPresented: $isPairing,
                                allowedContentTypes: [
                                    UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!,
                                    .propertyList
                                ]
                            ) { result in
                                switch result {
                                case .success(let url):
                                    let fileManager = FileManager.default
                                    let accessing = url.startAccessingSecurityScopedResource()
                                    
                                    if fileManager.fileExists(atPath: url.path) {
                                        do {
                                            if fileManager.fileExists(atPath: URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path) {
                                                try fileManager.removeItem(at: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                                            }
                                            try fileManager.copyItem(at: url, to: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                                            print(NSLocalizedString("File copied successfully!", comment: ""))
                                            startHeartbeatInBackground()
                                        } catch {
                                            print(String(format: NSLocalizedString("Error copying file: %@", comment: "File copy error in pairing flow"), String(describing: error)))
                                        }
                                    } else {
                                        print(NSLocalizedString("Source file does not exist.", comment: ""))
                                    }
                                    
                                    if accessing {
                                        url.stopAccessingSecurityScopedResource()
                                    }
                                case .failure(_):
                                    print(NSLocalizedString("Failed", comment: ""))
                                }
                            }
                            .overlay(
                                ZStack {
                                    if showTimeoutError {
                                        CustomErrorView(
                                            title: NSLocalizedString("Connection Error", comment: ""),
                                            message: NSLocalizedString("Check your connection and ensure your pairing file is valid and try again.", comment: ""),
                                            onDismiss: {
                                                showTimeoutError = false
                                            },
                                            showButton: true,
                                            primaryButtonText: NSLocalizedString("Continue Anyway", comment: ""),
                                            secondaryButtonText: NSLocalizedString("View Logs", comment: ""),
                                            onPrimaryButtonTap: {
                                                showContinueWarning = true
                                            },
                                            onSecondaryButtonTap: {
                                                showLogs = true
                                            },
                                            showSecondaryButton: true
                                        )
                                    }

                                    if showContinueWarning {
                                        CustomErrorView(
                                            title: NSLocalizedString("Proceeding Without Connection", comment: ""),
                                            message: NSLocalizedString("StikDebug will not function as expected if you choose to continue.", comment: ""),
                                            onDismiss: {
                                                showContinueWarning = false
                                            },
                                            showButton: true,
                                            primaryButtonText: NSLocalizedString("I Understand", comment: ""),
                                            onPrimaryButtonTap: {
                                                showContinueWarning = false
                                                isLoading2 = false
                                            }
                                        )
                                    }
                                }
                            )
                            .sheet(isPresented: $showLogs, onDismiss: {
                                isLoading2 = false
                            }) {
                                ConsoleLogsView()
                            }
                    } else {
                        MainTabView()
                            .onAppear {
                                let fileManager = FileManager.default
                                for (index, urlString) in urls.enumerated() {
                                    let destinationURL = URL.documentsDirectory.appendingPathComponent(outputFiles[index])
                                    if !fileManager.fileExists(atPath: destinationURL.path) {
                                        downloadFile(from: urlString, to: destinationURL) { result in
                                            if (result != "") {
                                                alert_title = NSLocalizedString("An Error has Occurred", comment: "")
                                                alert_string = NSLocalizedString("[Download DDI Error]: ", comment: "") + result
                                                show_alert = true
                                            }
                                        }
                                    }
                                }
                            }
                            .overlay(
                                ZStack {
                                    if show_alert {
                                        CustomErrorView(
                                            title: alert_title,
                                            message: alert_string,
                                            onDismiss: {
                                                show_alert = false
                                            },
                                            showButton: true,
                                            primaryButtonText: "OK"
                                        )
                                    }
                                }
                            )
                    }
                }
                // Apply global tint to all SwiftUI views in this window
                .tint(globalAccent)
                .onAppear {
                    // On first launch, present the welcome sheet.
                    // Otherwise, start the VPN automatically.
                    if !hasLaunchedBefore {
                        showWelcomeSheet = true
                    } else {
                        TunnelManager.shared.startVPN()
                    }
                    // Update UIKit tint now and subscribe to changes without capturing self
                    HeartbeatApp.updateUIKitTintFromStoredAccent()
                    NotificationCenter.default.addObserver(
                        forName: UserDefaults.didChangeNotification,
                        object: nil,
                        queue: .main
                    ) { _ in
                        HeartbeatApp.updateUIKitTintFromStoredAccent()
                    }
                }
                .sheet(isPresented: $showWelcomeSheet) {
                    WelcomeSheetView {
                        // When the user taps "Continue", mark the app as launched and start the VPN.
                        hasLaunchedBefore = true
                        showWelcomeSheet = false
                        TunnelManager.shared.startVPN()
                    }
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                print(NSLocalizedString("App became active – restarting heartbeat", comment: ""))
                startHeartbeatInBackground()
            }
        }
    }
    
    private func checkVPNConnection(callback: @escaping (Bool, String?) -> Void) {
        let host = NWEndpoint.Host("10.7.0.1")
        let port = NWEndpoint.Port(rawValue: 62078)!
        let connection = NWConnection(host: host, port: port, using: .tcp)
        var timeoutWorkItem: DispatchWorkItem?
        
        timeoutWorkItem = DispatchWorkItem { [weak connection] in
            if connection?.state != .ready {
                connection?.cancel()
                DispatchQueue.main.async {
                    if timeoutWorkItem?.isCancelled == false {
                        callback(false, NSLocalizedString("[TIMEOUT] The loopback VPN is not connected. Try closing this app, turn it off and back on.", comment: ""))
                    }
                }
            }
        }
        
        connection.stateUpdateHandler = { [weak connection] state in
            switch state {
            case .ready:
                timeoutWorkItem?.cancel()
                connection?.cancel()
                DispatchQueue.main.async {
                    callback(true, nil)
                }
            case .failed(let error):
                timeoutWorkItem?.cancel()
                connection?.cancel()
                DispatchQueue.main.async {
                    if error == NWError.posix(.ETIMEDOUT) {
                        callback(false, NSLocalizedString("The loopback VPN is not connected. Try closing the app, turn it off and back on.", comment: ""))
                    } else if error == NWError.posix(.ECONNREFUSED) {
                        callback(false, NSLocalizedString("Wifi is not connected. StikJIT won't work on cellular data.", comment: ""))
                    } else {
                        callback(false, String(format: NSLocalizedString("em proxy check error: %@", comment: "Generic EM proxy failure with error detail"), error.localizedDescription))
                    }
                }
            default:
                break
            }
        }
        
        connection.start(queue: .global())
        if let workItem = timeoutWorkItem {
            DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: workItem)
        }
    }
}

// MARK: - Additional Helpers

actor FunctionGuard<T> {
    private var runningTask: Task<T, Never>?
    
    func execute(_ work: @escaping @Sendable () -> T) async -> T {
        if let task = runningTask {
            return await task.value
        }
        let task = Task.detached { work() }
        runningTask = task
        let result = await task.value
        runningTask = nil
        return result
    }
}

class MountingProgress: ObservableObject {
    static var shared = MountingProgress()
    @Published var mountProgress: Double = 0.0
    @Published var mountingThread: Thread?
    @Published var coolisMounted: Bool = false
    
    func checkforMounted() {
        DispatchQueue.main.async {
            self.coolisMounted = isMounted()
        }
    }
    
    func progressCallback(progress: size_t, total: size_t, context: UnsafeMutableRawPointer?) {
        let percentage = Double(progress) / Double(total) * 100.0
        print(String(format: NSLocalizedString("Mounting progress: %.1f%%", comment: "Progress percentage while mounting DDI"), percentage))
        DispatchQueue.main.async {
            self.mountProgress = percentage
        }
    }
    
    func pubMount() {
        mount()
    }
    
    private func mount() {
        self.coolisMounted = isMounted()
        let pairingpath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
        
        if isPairing(), !isMounted() {
            if let mountingThread = mountingThread {
                mountingThread.cancel()
                self.mountingThread = nil
            }
            
            mountingThread = Thread {
                let mountResult = mountPersonalDDI(
                    imagePath: URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg").path,
                    trustcachePath: URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg.trustcache").path,
                    manifestPath: URL.documentsDirectory.appendingPathComponent("DDI/BuildManifest.plist").path,
                    pairingFilePath: pairingpath
                )
                
                if mountResult != 0 {
                    showAlert(title: NSLocalizedString("Error", comment: ""), message: String.localizedStringWithFormat(NSLocalizedString("An Error Occurred when Mounting the DDI\nError Code: %d", comment: ""), mountResult), showOk: true, showTryAgain: true) { shouldTryAgain in
                        if shouldTryAgain {
                            self.mount()
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.coolisMounted = isMounted()
                    }
                }
            }
            
            mountingThread!.qualityOfService = .background
            mountingThread!.name = "mounting"
            mountingThread!.start()
        }
    }
}

func isPairing() -> Bool {
    let pairingpath = URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path
    var pairingFile: IdevicePairingFile?
    let err = idevice_pairing_file_read(pairingpath, &pairingFile)
    if let err {
        print(String.localizedStringWithFormat(NSLocalizedString("Failed to read pairing file: %d", comment: ""), err.pointee.code))
        if err.pointee.code == -9 {  // InvalidHostID is -9
            return false
        }
        return false
    }
    return true
}

func startHeartbeatInBackground() {
    let heartBeatThread = Thread {
        let completionHandler: @convention(block) (Int32, String?) -> Void = { result, message in
            if result == 0 {
                print(String(format: NSLocalizedString("Heartbeat started successfully: %@", comment: ""), message ?? ""))
                pubHeartBeat = true
                
                if FileManager.default.fileExists(atPath: URL.documentsDirectory.appendingPathComponent("DDI/Image.dmg.trustcache").path) {
                    MountingProgress.shared.pubMount()
                }
            } else {
                print("Error: \(message ?? "") (Code: \(result))")
                DispatchQueue.main.async {
                    if result == -9 {
                        do {
                            try FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                            print(NSLocalizedString("Removed invalid pairing file", comment: ""))
                        } catch {
                            print(String(format: NSLocalizedString("Error removing invalid pairing file: %@", comment: ""), String(describing: error)))
                        }
                        
                        showAlert(
                            title: NSLocalizedString("Invalid Pairing File", comment: ""),
                            message: NSLocalizedString("The pairing file is invalid or expired. Please select a new pairing file.", comment: ""),
                            showOk: true,
                            showTryAgain: false,
                            primaryButtonText: NSLocalizedString("Select New File", comment: "")
                        ) { _ in
                            NotificationCenter.default.post(name: NSNotification.Name("ShowPairingFilePicker"), object: nil)
                        }
                    } else {
                        showAlert(
                            title: NSLocalizedString("Heartbeat Error", comment: ""),
                            message: String.localizedStringWithFormat(NSLocalizedString("Failed to connect to Heartbeat (%d). Are you connected to WiFi or is Airplane Mode enabled? Cellular data isn’t supported. Please launch the app at least once with WiFi enabled. After that, you can switch to cellular data to turn on the VPN, and once the VPN is active you can use Airplane Mode.", comment: ""), result),
                            showOk: false,
                            showTryAgain: true
                        ) { shouldTryAgain in
                            if shouldTryAgain {
                                startHeartbeatInBackground()
                            }
                        }
                    }
                }
            }
        }
        JITEnableContext.shared.startHeartbeat(completionHandler: completionHandler, logger: nil)
    }
    
    heartBeatThread.qualityOfService = .background
    heartBeatThread.name = "Heartbeat"
    heartBeatThread.start()
}

struct LoadingView: View {
    @Binding var showAlert: Bool
    @Binding var alertTitle: String
    @Binding var alertMessage: String
    
    @State private var animate = false
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    
    private var accentColor: Color {
        if customAccentColorHex.isEmpty {
            return .accentColor
        } else {
            return Color(hex: customAccentColorHex) ?? .accentColor
        }
    }
    
    var body: some View {
        ZStack {
            // Background now comes from global BackgroundContainer
            Color.clear.ignoresSafeArea()
            
            VStack {
                ZStack {
                    Circle()
                        .stroke(lineWidth: 8)
                        .foregroundColor(accentColor.opacity(0.18))
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    accentColor.opacity(0.95),
                                    accentColor.opacity(0.45)
                                ]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(animate ? 360 : 0))
                        .frame(width: 80, height: 80)
                        .animation(Animation.linear(duration: 1.2).repeatForever(autoreverses: false), value: animate)
                }
                .shadow(color: accentColor.opacity(0.25), radius: 10, x: 0, y: 0)
                .onAppear {
                    animate = true
                    let os = ProcessInfo.processInfo.operatingSystemVersion
                    if os.majorVersion < 17 || (os.majorVersion == 17 && os.minorVersion < 4) {
                        alertTitle = NSLocalizedString("Unsupported OS Version", comment: "")
                        alertMessage = String(format: NSLocalizedString("StikJIT only supports 17.4 and above. Your device is running iOS/iPadOS %@", comment: ""), "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
                        showAlert = true
                    }
                }
                
                Text(NSLocalizedString("Loading...", comment: ""))
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                    .padding(.top, 20)
                    .opacity(animate ? 1.0 : 0.5)
                    .animation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animate)
            }
        }
        // Inherit system color scheme
    }
}

public func showAlert(title: String, message: String, showOk: Bool, showTryAgain: Bool = false, primaryButtonText: String? = nil, messageType: MessageType = .error, completion: ((Bool) -> Void)? = nil) {
    DispatchQueue.main.async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }
        let rootViewController = scene.windows.first?.rootViewController
        if showTryAgain {
            let customErrorView = CustomErrorView(
                title: title,
                message: message,
                onDismiss: {
                    rootViewController?.presentedViewController?.dismiss(animated: true)
                    completion?(false)
                },
                showButton: true,
                primaryButtonText: primaryButtonText ?? NSLocalizedString("Try Again", comment: ""),
                onPrimaryButtonTap: {
                    completion?(true)
                },
                messageType: messageType
            )
            let hostingController = UIHostingController(rootView: customErrorView)
            hostingController.modalPresentationStyle = .overFullScreen
            hostingController.modalTransitionStyle = .crossDissolve
            hostingController.view.backgroundColor = .clear
            rootViewController?.present(hostingController, animated: true)
        } else if showOk {
            let customErrorView = CustomErrorView(
                title: title,
                message: message,
                onDismiss: {
                    rootViewController?.presentedViewController?.dismiss(animated: true)
                    completion?(true)
                },
                showButton: true,
                primaryButtonText: primaryButtonText ?? "OK",
                onPrimaryButtonTap: {
                    rootViewController?.presentedViewController?.dismiss(animated: true)
                    completion?(true)
                },
                messageType: messageType
            )
            let hostingController = UIHostingController(rootView: customErrorView)
            hostingController.modalPresentationStyle = .overFullScreen
            hostingController.modalTransitionStyle = .crossDissolve
            hostingController.view.backgroundColor = .clear
            rootViewController?.present(hostingController, animated: true)
        } else {
            let customErrorView = CustomErrorView(
                title: title,
                message: message,
                onDismiss: {
                    rootViewController?.presentedViewController?.dismiss(animated: true)
                    completion?(false)
                },
                showButton: false,
                messageType: messageType
            )
            let hostingController = UIHostingController(rootView: customErrorView)
            hostingController.modalPresentationStyle = .overFullScreen
            hostingController.modalTransitionStyle = .crossDissolve
            hostingController.view.backgroundColor = .clear
            rootViewController?.present(hostingController, animated: true)
        }
    }
}

func downloadFile(from urlString: String, to destinationURL: URL, completion: @escaping (String) -> Void) {
    let fileManager = FileManager.default
    let documentsDirectory = URL.documentsDirectory
    
    guard let url = URL(string: urlString) else {
        print(String(format: NSLocalizedString("Invalid URL: %@", comment: ""), urlString))
        completion("[Internal Invalid URL error]")
        return
    }
    
    let task = URLSession.shared.downloadTask(with: url) { (tempLocalUrl, response, error) in
        guard let tempLocalUrl = tempLocalUrl, error == nil else {
            print(String(format: NSLocalizedString("Error downloading file from %@: %@", comment: ""), urlString, String(describing: error)))
            completion(NSLocalizedString("Are you connected to the internet? [Download Failed]", comment: ""))
            return
        }
        
        do {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try fileManager.moveItem(at: tempLocalUrl, to: destinationURL)
            print(String(format: NSLocalizedString("Downloaded %@ to %@", comment: ""), urlString, destinationURL.path))
        } catch {
            print(String(format: NSLocalizedString("Error saving file: %@", comment: ""), String(describing: error)))
        }
    }
    task.resume()
    completion("")
}

