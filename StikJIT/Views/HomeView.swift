//
//  ContentView.swift
//  StikJIT
//
//  Created by Stephen on 3/26/25.
//

import SwiftUI
import UniformTypeIdentifiers
import Pipify

struct JITEnableConfiguration {
    var bundleID: String? = nil
    var pid : Int? = nil
    var scriptData: Data? = nil
    var scriptName : String? = nil
}

struct HomeView: View {

    @AppStorage("username") private var username = "User"
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var environmentAccentColor
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @AppStorage("bundleID") private var bundleID: String = ""
    @State private var isProcessing = false
    @State private var isShowingInstalledApps = false
    @State private var isShowingPairingFilePicker = false
    @State private var pairingFileExists: Bool = false
    @State private var showPairingFileMessage = false
    @State private var pairingFileIsValid = false
    @State private var isImportingFile = false
    @State private var showingConsoleLogsView = false
    @State private var importProgress: Float = 0.0
    
    @State private var pidTextAlertShow = false
    @State private var pidStr = ""
    
    @State private var viewDidAppeared = false
    @State private var pendingJITEnableConfiguration : JITEnableConfiguration? = nil
    @AppStorage("enableAdvancedOptions") private var enableAdvancedOptions = false

    @AppStorage("useDefaultScript") private var useDefaultScript = false
    @AppStorage("enablePiP") private var enablePiP = true
    @State var scriptViewShow = false
    @State var pipRequired = false
    @AppStorage("DefaultScriptName") var selectedScript = "attachDetach.js"
    @State var jsModel: RunJSViewModel?
    
    // Observe VPN status
    @StateObject private var tunnel = TunnelManager.shared
    // Mirror heartbeat boolean
    @State private var heartbeatOK = false
    
    private var accentColor: Color {
        if customAccentColorHex.isEmpty {
            return .white
        } else {
            return Color(hex: customAccentColorHex) ?? .white
        }
    }

    // Derived states
    private var ddiMounted: Bool { isMounted() }
    private var canConnectByApp: Bool { pairingFileExists && ddiMounted }

    var body: some View {
        NavigationStack {
            ZStack {
                // DeviceInfo-style subtle gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(UIColor.systemBackground),
                        Color(UIColor.secondarySystemBackground)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Top card: status + both actions
                        topStatusAndActionsCard
                        
                        // Tools (Console)
                        toolsCard
                        
                        // Helpful tips
                        tipsCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 30)
                }
                
                // Busy overlay during pairing import (DeviceInfo-style)
                if isImportingFile {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView("Processing pairing file...")
                        VStack(spacing: 8) {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(UIColor.tertiarySystemFill))
                                        .frame(height: 8)
                                    
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.green)
                                        .frame(width: geometry.size.width * CGFloat(importProgress), height: 8)
                                        .animation(.linear(duration: 0.3), value: importProgress)
                                }
                            }
                            .frame(height: 8)
                            Text("\(Int(importProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 6)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
                }
                
                // Success toast after import (DeviceInfo-style)
                if showPairingFileMessage && pairingFileIsValid && !isImportingFile {
                    VStack {
                        Spacer()
                        Text("✓ Pairing file successfully imported")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 3)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 30)
                    }
                    .animation(.easeInOut(duration: 0.25), value: showPairingFileMessage)
                }
            }
            .navigationTitle("Home")
        }
        .onAppear {
            checkPairingFileExists()
            refreshBackground()
            
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ShowPairingFilePicker"),
                object: nil,
                queue: .main
            ) { _ in
                isShowingPairingFilePicker = true
            }
        }
        .onReceive(timer) { _ in
            refreshBackground()
            checkPairingFileExists()
            // Update heartbeat mirror from global
            heartbeatOK = pubHeartBeat
        }
        .fileImporter(isPresented: $isShowingPairingFilePicker, allowedContentTypes: [UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!, .propertyList]) {result in
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
                        print("File copied successfully!")
                        
                        // Show progress bar and initialize progress
                        DispatchQueue.main.async {
                            isImportingFile = true
                            importProgress = 0.0
                            pairingFileExists = true
                        }
                        
                        // Start heartbeat in background
                        startHeartbeatInBackground()
                        
                        // Create timer to update progress instead of sleeping
                        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                            DispatchQueue.main.async {
                                if importProgress < 1.0 {
                                    importProgress += 0.25
                                } else {
                                    timer.invalidate()
                                    isImportingFile = false
                                    pairingFileIsValid = true
                                    
                                    // Show success message
                                    withAnimation {
                                        showPairingFileMessage = true
                                    }
                                    
                                    // Hide message after delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        withAnimation {
                                            showPairingFileMessage = false
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Ensure timer keeps running
                        RunLoop.current.add(progressTimer, forMode: .common)
                        
                    } catch {
                        print("Error copying file: \(error)")
                    }
                } else {
                    print("Source file does not exist.")
                }
                
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            case .failure(let error):
                print("Failed to import file: \(error)")
            }
        }
        .sheet(isPresented: $isShowingInstalledApps) {
            InstalledAppsListView { selectedBundle in
                bundleID = selectedBundle
                isShowingInstalledApps = false
                HapticFeedbackHelper.trigger()
                startJITInBackground(bundleID: selectedBundle)
            }
        }
        .pipify(isPresented: Binding(
            get: { pipRequired && enablePiP },
            set: { newValue in pipRequired = newValue }
        )) {
            RunJSViewPiP(model: $jsModel)
        }
        .sheet(isPresented: $scriptViewShow) {
            NavigationView {
                if let jsModel {
                    RunJSView(model: jsModel)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    scriptViewShow = false
                                }
                            }
                        }
                        .navigationTitle(selectedScript)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .onChange(of: scriptViewShow) { oldValue, newValue in
            if !newValue, let jsModel {
                jsModel.executionInterrupted = true
                jsModel.semaphore?.signal()
            }
        }
        .textFieldAlert(
            isPresented: $pidTextAlertShow,
            title: "Please enter the PID of the process you want to connect to".localized,
            text: $pidStr,
            placeholder: "",
            action: { newText in

                guard let pidStr = newText, pidStr != "" else {
                    return
                }
                
                guard let pid = Int(pidStr) else {
                    showAlert(title: "", message: "Invalid PID".localized, showOk: true, completion: { _ in })
                    return
                }
                startJITInBackground(pid: pid)
                
            },
            actionCancel: {_ in
                pidStr = ""
            }
        )
        .onOpenURL { url in
            print(url.path)
            if url.host != "enable-jit" {
                return
            }
            
            var config = JITEnableConfiguration()
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            
            if let pidStr = components?.queryItems?.first(where: { $0.name == "pid" })?.value, let pid = Int(pidStr) {
                config.pid = pid
            }
            if let bundleId = components?.queryItems?.first(where: { $0.name == "bundle-id" })?.value {
                config.bundleID = bundleId
            }
            if let scriptBase64URL = components?.queryItems?.first(where: { $0.name == "script-data" })?.value?.removingPercentEncoding {
                let base64 = base64URLToBase64(scriptBase64URL)
                if let scriptData = Data(base64Encoded: base64) {
                    config.scriptData = scriptData
                }
            }
            if let scriptName = components?.queryItems?.first(where: { $0.name == "script-name" })?.value {
                config.scriptName = scriptName
            }
            
            if viewDidAppeared {
                startJITInBackground(bundleID: config.bundleID, pid: config.pid, scriptData: config.scriptData, scriptName: config.scriptName, triggeredByURLScheme: true)
            } else {
                pendingJITEnableConfiguration = config
            }
            
        }
        .onAppear() {
            viewDidAppeared = true
            if let config = pendingJITEnableConfiguration {
                startJITInBackground(bundleID: config.bundleID, pid: config.pid, scriptData: config.scriptData, scriptName: config.scriptName, triggeredByURLScheme: true)
                self.pendingJITEnableConfiguration = nil
            }
        }
    }
    
    // MARK: - Styled Sections
    
    // Top card that includes: status icons + both actions
    private var topStatusAndActionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header row with icon-only indicators
            HStack(spacing: 12) {
                // Pairing
                indicatorCapsule(
                    ok: pairingFileExists,
                    systemImage: "doc.badge.plus",
                    a11y: "Pairing"
                )
                // DDI
                indicatorCapsule(
                    ok: ddiMounted,
                    systemImage: "externaldrive",
                    a11y: "Developer Disk Image"
                )
                // VPN
                indicatorCapsule(
                    ok: tunnel.tunnelStatus == .connected,
                    systemImage: "lock.shield",
                    a11y: "VPN"
                )
                // Heartbeat
                indicatorCapsule(
                    ok: heartbeatOK,
                    systemImage: "waveform.path.ecg",
                    a11y: "Heartbeat"
                )
                
                Spacer()
            }
            
            // Welcome text
            VStack(spacing: 4) {
                Text("Welcome, \(username)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(helperSubtitle())
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 4)
            
            // Buttons in one vertical stack
            VStack(spacing: 10) {
                // Connect by App / Select Pairing File
                Button(action: primaryActionTapped) {
                    HStack {
                        Image(systemName: pairingFileExists ? "cable.connector.horizontal" : "doc.badge.plus")
                            .font(.system(size: 20))
                        Text(pairingFileExists ? "Connect by App" : "Select Pairing File")
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundColor(.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
                }
                .disabled(pairingFileExists && !ddiMounted)
                .opacity(pairingFileExists && !ddiMounted ? 0.6 : 1.0)
                
                // Connect by PID (Advanced only)
                if pairingFileExists && enableAdvancedOptions {
                    Button(action: { pidTextAlertShow = true }) {
                        HStack {
                            Image(systemName: "number.circle")
                                .font(.system(size: 20))
                            Text("Connect by PID")
                                .font(.system(.title3, design: .rounded))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundColor(.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                    }
                }
            }
            
            // Inline status / progress
            if isImportingFile {
                VStack(spacing: 8) {
                    HStack {
                        Text("Processing pairing file…")
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(importProgress * 100))%")
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(UIColor.tertiarySystemFill))
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.green)
                                .frame(width: geometry.size.width * CGFloat(importProgress), height: 8)
                                .animation(.linear(duration: 0.3), value: importProgress)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(.top, 4)
            } else if showPairingFileMessage && pairingFileIsValid {
                HStack(spacing: 10) {
                    StatusDot(color: .green)
                    Text("Pairing file successfully imported")
                        .font(.system(.callout, design: .rounded))
                        .foregroundColor(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    }
    
    // Compact indicator builder: dot + SF Symbol in a capsule
    private func indicatorCapsule(ok: Bool, systemImage: String, a11y: String) -> some View {
        let fixedHeight: CGFloat = 32
        return HStack(spacing: 8) {
            StatusDot(color: ok ? .green : .orange)
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .accessibilityLabel(a11y)
        }
        .frame(height: fixedHeight)
        .padding(.horizontal, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color(UIColor.tertiarySystemBackground))
        )
    }
    
    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tools")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Button(action: { showingConsoleLogsView = true }) {
                // Centered icon + text, no chevron
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 20))
                    Text("Open Console")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundColor(.black)
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
            }
            .sheet(isPresented: $showingConsoleLogsView) {
                ConsoleLogsView()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    }
    
    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tips")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if !pairingFileExists {
                tipRow(
                    systemImage: "doc.badge.plus",
                    title: "Pairing file required",
                    message: "Import your device’s pairing file to begin."
                )
            }
            
            if pairingFileExists && !ddiMounted {
                tipRow(
                    systemImage: "externaldrive.badge.exclamationmark",
                    title: "Developer Disk Image not mounted",
                    message: "Go to Settings → Developer Disk Image and ensure it’s mounted."
                )
            }
            
            tipRow(
                systemImage: "lock.shield",
                title: "Local only",
                message: "StikDebug runs entirely on-device. No data leaves your device."
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    }
    
    private func tipRow(systemImage: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundColor(accentColor)
                .font(.system(size: 18))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.semibold)
                Text(message).font(.footnote).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Helpers (UI)
    
    private func helperSubtitle() -> String {
        if canConnectByApp { return "Select an app to start debugging." }
        if pairingFileExists { return "Mount the Developer Disk Image in Settings." }
        return "Import your pairing file to get started."
    }
    
    private func primaryActionTapped() {
        if pairingFileExists {
            if !ddiMounted {
                showAlert(title: "Device Not Mounted".localized, message: "The Developer Disk Image has not been mounted yet. Check in settings for more information.".localized, showOk: true) { _ in }
                return
            }
            isShowingInstalledApps = true
        } else {
            isShowingPairingFilePicker = true
        }
    }
    
    // MARK: - Logic
    
    private func checkPairingFileExists() {
        let fileExists = FileManager.default.fileExists(atPath: URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path)
        pairingFileExists = fileExists && isPairing()
    }
    
    private func refreshBackground() {
        // kept for compatibility
    }
    
    private func getJsCallback(_ script: Data, name: String? = nil) -> DebugAppCallback {
        return { pid, debugProxyHandle, semaphore in
            jsModel = RunJSViewModel(pid: Int(pid), debugProxy: debugProxyHandle, semaphore: semaphore)
            scriptViewShow = true
            
            DispatchQueue.global(qos: .background).async {
                do {
                    try jsModel?.runScript(data: script, name: name)
                } catch {
                    showAlert(title: "Error Occurred While Executing the Default Script.".localized, message: error.localizedDescription, showOk: true)
                }
            }
        }
    }
    
    // launch app following this order: pid > bundleID
    // load script following this order: scriptData > script file from script name > saved script for bundleID > default script
    // if advanced mode is disabled the whole script loading will be skipped. If use default script is disabled default script will not be loaded
    private func startJITInBackground(bundleID: String? = nil, pid : Int? = nil, scriptData: Data? = nil, scriptName : String? = nil, triggeredByURLScheme: Bool = false) {
        isProcessing = true
        LogManager.shared.addInfoLog("Starting Debug for \(bundleID ?? String(pid ?? 0))")
        
        DispatchQueue.global(qos: .background).async {
            var scriptData = scriptData
            var scriptName = scriptName
            if enableAdvancedOptions && scriptData == nil {
                if scriptName == nil, let bundleID, let mapping = UserDefaults.standard.dictionary(forKey: "BundleScriptMap") as? [String: String] {
                    scriptName = mapping[bundleID]
                }
                
                if useDefaultScript && scriptName == nil {
                    scriptName = selectedScript
                }
                
                if scriptData == nil, let scriptName {
                    let selectedScriptURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("scripts").appendingPathComponent(scriptName)
                    
                    if FileManager.default.fileExists(atPath: selectedScriptURL.path) {
                        do {
                            scriptData = try Data(contentsOf: selectedScriptURL)
                        } catch {
                            print("failed to load data from script \(error)")
                        }
                        
                    }
                }
            } else {
                scriptData = nil
            }
            
            var callback: DebugAppCallback? = nil
            
            if let scriptData {
                callback = getJsCallback(scriptData, name: scriptName ?? bundleID ?? "Script")
                if triggeredByURLScheme {
                    usleep(500000)
                }

                pipRequired = true
            }
            
            let logger: LogFunc = { message in
                if let message = message {
                    LogManager.shared.addInfoLog(message)
                }
            }
            var success : Bool
            if let pid {
                success = JITEnableContext.shared.debugApp(withPID: Int32(pid), logger: logger, jsCallback: callback)
            } else if let bundleID {
                success = JITEnableContext.shared.debugApp(withBundleID: bundleID, logger: logger, jsCallback: callback)
            } else {
                DispatchQueue.main.async {
                    showAlert(title: "Failed to Debug App".localized, message:  "Either bundle ID or PID should be specified.".localized, showOk: true)
                }
                success = false
            }
            
            if success {
                DispatchQueue.main.async {
                    LogManager.shared.addInfoLog("Debug process completed for \(bundleID ?? String(pid ?? 0))")
                }
            }
            isProcessing = false
            pipRequired = false
        }
    }
    
    func base64URLToBase64(_ base64url: String) -> String {
        var base64 = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad with "=" to make length a multiple of 4
        let paddingLength = 4 - (base64.count % 4)
        if paddingLength < 4 {
            base64 += String(repeating: "=", count: paddingLength)
        }

        return base64
    }

}

// MARK: - Status Light Components

private struct StatusLight: View {
    enum State { case ok, warn }
    var title: String
    var state: State
    
    var body: some View {
        let fixedHeight: CGFloat = 32
        HStack(spacing: 8) {
            StatusDot(color: state == .ok ? .green : .orange)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
        }
        .frame(height: fixedHeight)
        .padding(.horizontal, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color(UIColor.tertiarySystemBackground))
        )
    }
}

private struct StatusDot: View {
    var color: Color
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 20, height: 20)
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .shadow(color: color.opacity(0.6), radius: 4, x: 0, y: 0)
        }
        .overlay(
            Circle()
                .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1), lineWidth: 0.5)
        )
    }
}

class InstalledAppsViewModel: ObservableObject {
    @Published var apps: [String: String] = [:]
    
    init() {
        loadApps()
    }
    
    func loadApps() {
        do {
            self.apps = try JITEnableContext.shared.getAppList()
        } catch {
            print(error)
            self.apps = [:]
        }
    }
}



#Preview {
    HomeView()
}
