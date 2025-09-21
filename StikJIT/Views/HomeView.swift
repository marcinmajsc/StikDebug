//
//  ContentView.swift
//  StikJIT
//
//  Created by Stephen on 3/26/25.
//

import SwiftUI
import UniformTypeIdentifiers
import Pipify
import UIKit

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
    
    @State private var showPIDSheet = false
    @AppStorage("recentPIDs") private var recentPIDs: [Int] = []
    @State private var justCopied = false
    
    @State private var viewDidAppeared = false
    @State private var pendingJITEnableConfiguration : JITEnableConfiguration? = nil
    @AppStorage("enableAdvancedOptions") private var enableAdvancedOptions = false

    @AppStorage("useDefaultScript") private var useDefaultScript = false
    @AppStorage("enablePiP") private var enablePiP = true
    @State var scriptViewShow = false
    @State var pipRequired = false
    @AppStorage("DefaultScriptName") var selectedScript = "attachDetach.js"
    @State var jsModel: RunJSViewModel?
    
    @StateObject private var tunnel = TunnelManager.shared
    @State private var heartbeatOK = false

    @AppStorage("showiOS26Disclaimer") private var showiOS26Disclaimer: Bool = true
    
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    private var currentTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .system }
    
    private var accentColor: Color {
        if customAccentColorHex.isEmpty { return .white }
        return Color(hex: customAccentColorHex) ?? .white
    }

    private var ddiMounted: Bool { isMounted() }
    private var canConnectByApp: Bool { pairingFileExists && ddiMounted }
    
    private var isOnOrAfteriOS26: Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion >= 26
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(style: currentTheme.backgroundStyle)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        if isOnOrAfteriOS26 || showiOS26Disclaimer {
                            disclaimerCard
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        topStatusAndActionsCard
                        toolsCard
                        tipsCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 30)
                }

                if isImportingFile {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView(NSLocalizedString("Processing pairing file…", comment: ""))
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

                if showPairingFileMessage && pairingFileIsValid && !isImportingFile {
                    toast(NSLocalizedString("✓ Pairing file successfully imported", comment: ""))
                }
                if justCopied {
                    toast(NSLocalizedString("Copied", comment: ""))
                }
            }
            .navigationTitle(NSLocalizedString("Home", comment: ""))
        }
        .onAppear {
            checkPairingFileExists()
            refreshBackground()
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ShowPairingFilePicker"),
                object: nil,
                queue: .main
            ) { _ in isShowingPairingFilePicker = true }
        }
        .onReceive(timer) { _ in
            refreshBackground()
            checkPairingFileExists()
            heartbeatOK = pubHeartBeat
        }
        .fileImporter(isPresented: $isShowingPairingFilePicker, allowedContentTypes: [UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!, .propertyList]) { result in
            switch result {
            case .success(let url):
                let fileManager = FileManager.default
                let accessing = url.startAccessingSecurityScopedResource()
                
                if fileManager.fileExists(atPath: url.path) {
                    do {
                        let dest = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
                        if FileManager.default.fileExists(atPath: dest.path) {
                            try fileManager.removeItem(at: dest)
                        }
                        try fileManager.copyItem(at: url, to: dest)
                        
                        DispatchQueue.main.async {
                            isImportingFile = true
                            importProgress = 0
                            pairingFileExists = true
                        }
                        
                        startHeartbeatInBackground()
                        
                        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { t in
                            DispatchQueue.main.async {
                                if importProgress < 1 {
                                    importProgress += 0.25
                                } else {
                                    t.invalidate()
                                    isImportingFile = false
                                    pairingFileIsValid = true
                                    withAnimation { showPairingFileMessage = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        withAnimation { showPairingFileMessage = false }
                                    }
                                }
                            }
                        }
                        RunLoop.current.add(progressTimer, forMode: .common)
                    } catch {
                        print("\(NSLocalizedString("Error copying file", comment: "")): \(error)")
                    }
                }
                if accessing { url.stopAccessingSecurityScopedResource() }
            case .failure(let error):
                print("\(NSLocalizedString("Failed to import file", comment: "")): \(error)")
            }
        }
        .sheet(isPresented: $isShowingInstalledApps) {
            InstalledAppsListView { selectedBundle in
                bundleID = selectedBundle
                isShowingInstalledApps = false
                HapticFeedbackHelper.trigger()
                
                var autoScriptData: Data? = nil
                var autoScriptName: String? = nil
                
                let appName: String? = (try? JITEnableContext.shared.getAppList()[selectedBundle])
                
                if #available(iOS 26, *) {
                    if ProcessInfo.processInfo.hasTXM, let appName {
                        if appName == "maciOS" {
                            if let url = Bundle.main.url(forResource: "script1", withExtension: "js"),
                               let data = try? Data(contentsOf: url) {
                                autoScriptData = data
                                autoScriptName = "script1.js"
                            }
                        } else if appName == "Amethyst" {
                            if let url = Bundle.main.url(forResource: "script2", withExtension: "js"),
                               let data = try? Data(contentsOf: url) {
                                autoScriptData = data
                                autoScriptName = "script2.js"
                            }
                        } else if appName == "MeloNX" {
                            if let url = Bundle.main.url(forResource: "melo", withExtension: "js"),
                               let data = try? Data(contentsOf: url) {
                                autoScriptData = data
                                autoScriptName = "melo.js"
                            }
                        } else if appName == "UTM" {
                            if let url = Bundle.main.url(forResource: "utmjit", withExtension: "js"),
                               let data = try? Data(contentsOf: url) {
                                autoScriptData = data
                                autoScriptName = "utmjit.js"
                            }
                        }
                    }
                }
                
                startJITInBackground(bundleID: selectedBundle,
                                     pid: nil,
                                     scriptData: autoScriptData,
                                     scriptName: autoScriptName,
                                     triggeredByURLScheme: false)
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
                                Button(NSLocalizedString("Done", comment: "")) { scriptViewShow = false }
                            }
                        }
                        .navigationTitle(selectedScript)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .sheet(isPresented: $showPIDSheet) {
            ConnectByPIDSheet(
                recentPIDs: $recentPIDs,
                onPasteCopyToast: { showCopiedToast() },
                onConnect: { pid in
                    HapticFeedbackHelper.trigger()
                    startJITInBackground(pid: pid)
                }
            )
        }
        .onOpenURL { url in
            guard url.host == "enable-jit" else { return }
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
        .onAppear {
            viewDidAppeared = true
            if let config = pendingJITEnableConfiguration {
                startJITInBackground(bundleID: config.bundleID, pid: config.pid, scriptData: config.scriptData, scriptName: config.scriptName, triggeredByURLScheme: true)
                pendingJITEnableConfiguration = nil
            }
        }
    }
    
    // MARK: - Styled Sections
    
    private var topStatusAndActionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                indicatorCapsule(ok: pairingFileExists, systemImage: "doc.badge.plus", a11y: "Pairing")
                indicatorCapsule(ok: ddiMounted, systemImage: "externaldrive", a11y: "Developer Disk Image")
                indicatorCapsule(ok: tunnel.tunnelStatus == .connected, systemImage: "lock.shield", a11y: "VPN")
                indicatorCapsule(ok: heartbeatOK, systemImage: "waveform.path.ecg", a11y: "Heartbeat")
                Spacer()
            }
            VStack(spacing: 4) {
                Text(String(format: NSLocalizedString("Welcome", comment: ""), username))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(helperSubtitle())
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)
            
            VStack(spacing: 10) {
                Button(action: primaryActionTapped) {
                    whiteCardButtonLabel(
                        icon: pairingFileExists ? "cable.connector.horizontal" : "doc.badge.plus",
                        title: pairingFileExists ? NSLocalizedString("Connect by App", comment: "") : NSLocalizedString("Select Pairing File", comment: "")
                    )
                }
                .disabled(pairingFileExists && !ddiMounted)
                .opacity(pairingFileExists && !ddiMounted ? 0.6 : 1.0)
                
                if pairingFileExists && enableAdvancedOptions {
                    Button(action: { showPIDSheet = true }) {
                        whiteCardButtonLabel(icon: "number.circle", title: NSLocalizedString("Connect by PID", comment: ""))
                    }
                }
            }

            if isImportingFile {
                VStack(spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("Processing pairing file…", comment: ""))
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(importProgress * 100))%")
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6).fill(Color(UIColor.tertiarySystemFill)).frame(height: 8)
                            RoundedRectangle(cornerRadius: 6).fill(Color.green)
                                .frame(width: geo.size.width * CGFloat(importProgress), height: 8)
                                .animation(.linear(duration: 0.3), value: importProgress)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(.top, 4)
            } else if showPairingFileMessage && pairingFileIsValid {
                HStack(spacing: 10) {
                    StatusDot(color: .green)
                    Text(NSLocalizedString("Pairing file successfully imported", comment: ""))
                        .font(.system(.callout, design: .rounded))
                        .foregroundColor(.green)
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
    
    private func indicatorCapsule(ok: Bool, systemImage: String, a11y: String) -> some View {
        HStack(spacing: 8) {
            StatusDot(color: ok ? .green : .orange)
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .accessibilityLabel(a11y)
        }
        .frame(height: 32)
        .padding(.horizontal, 10)
        .background(Capsule(style: .continuous).fill(Color(UIColor.tertiarySystemBackground)))
    }
    
    private func whiteCardButtonLabel(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon).font(.system(size: 20))
            Text(title).font(.system(.title3, design: .rounded)).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundColor(accentColor.contrastText())
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("Tools", comment: "")).font(.headline).foregroundColor(.secondary)
            Button(action: { showingConsoleLogsView = true }) {
                HStack {
                    Image(systemName: "terminal").font(.system(size: 20))
                    Text(NSLocalizedString("Open Console", comment: "")).font(.system(.title3, design: .rounded)).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(accentColor.contrastText())
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
            }
            .sheet(isPresented: $showingConsoleLogsView) { ConsoleLogsView() }
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
            Text(NSLocalizedString("Tips", comment: "")).font(.headline).foregroundColor(.secondary)
            if !pairingFileExists {
                tipRow(systemImage: "doc.badge.plus", title: NSLocalizedString("Pairing file required", comment: ""), message: NSLocalizedString("Import your device’s pairing file to begin.", comment: ""))
            }
            if pairingFileExists && !ddiMounted {
                tipRow(systemImage: "externaldrive.badge.exclamationmark", title: NSLocalizedString("Developer Disk Image not mounted", comment: ""), message: NSLocalizedString("Go to Settings → Developer Disk Image and ensure it’s mounted.", comment: ""))
            }
            tipRow(systemImage: "lock.shield", title: NSLocalizedString("Local only", comment: ""), message: NSLocalizedString("StikDebug runs entirely on-device. No data leaves your device.", comment: ""))
            
            Button {
                if let url = URL(string: "https://github.com/StephenDev0/StikDebug-Guide/blob/main/pairing_file.md") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(accentColor)
                        .font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Pairing File Guide", comment: ""))
                            .font(.subheadline).fontWeight(.semibold)
                        Text(NSLocalizedString("Learn how to create and import your pairing file.", comment: ""))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.semibold)
                Text(message).font(.footnote).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func helperSubtitle() -> String {
        if canConnectByApp { return NSLocalizedString("Select an app to start debugging.", comment: "") }
        if pairingFileExists { return NSLocalizedString("Mount the Developer Disk Image in Settings.", comment: "") }
        return NSLocalizedString("Import your pairing file to get started.", comment: "")
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
    
    private func showCopiedToast() {
        withAnimation { justCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { justCopied = false }
        }
    }
    
    @ViewBuilder private func toast(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 3)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 30)
        }
        .animation(.easeInOut(duration: 0.25), value: text)
    }
    
    private func checkPairingFileExists() {
        let fileExists = FileManager.default.fileExists(atPath: URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path)
        pairingFileExists = fileExists && isPairing()
    }
    private func refreshBackground() { }
    
    private func getJsCallback(_ script: Data, name: String? = nil) -> DebugAppCallback {
        return { pid, debugProxyHandle, semaphore in
            jsModel = RunJSViewModel(pid: Int(pid), debugProxy: debugProxyHandle, semaphore: semaphore)
            scriptViewShow = true
            DispatchQueue.global(qos: .background).async {
                do { try jsModel?.runScript(data: script, name: name) }
                catch { showAlert(title: "Error Occurred While Executing the Default Script.".localized, message: error.localizedDescription, showOk: true) }
            }
        }
    }
    
    private func startJITInBackground(bundleID: String? = nil, pid : Int? = nil, scriptData: Data? = nil, scriptName: String? = nil, triggeredByURLScheme: Bool = false) {
        isProcessing = true
        LogManager.shared.addInfoLog("Starting Debug for \(bundleID ?? String(pid ?? 0))")
        
        DispatchQueue.global(qos: .background).async {
            var scriptData = scriptData
            var scriptName = scriptName
            if enableAdvancedOptions && scriptData == nil {
                if scriptName == nil, let bundleID, let mapping = UserDefaults.standard.dictionary(forKey: "BundleScriptMap") as? [String: String] {
                    scriptName = mapping[bundleID]
                }
                if useDefaultScript && scriptName == nil { scriptName = selectedScript }
                if scriptData == nil, let scriptName {
                    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("scripts").appendingPathComponent(scriptName)
                    if FileManager.default.fileExists(atPath: url.path) {
                        do { scriptData = try Data(contentsOf: url) } catch { print("script load error: \(error)") }
                    }
                }
            } else {
                // keep passed-in auto script if provided; otherwise nil
            }
            
            var callback: DebugAppCallback? = nil
            if ProcessInfo.processInfo.hasTXM, let sd = scriptData {
                callback = getJsCallback(sd, name: scriptName ?? bundleID ?? "Script")
                if triggeredByURLScheme { usleep(500000) }
                pipRequired = true
            } else {
                pipRequired = false
            }
            
            let logger: LogFunc = { message in if let message { LogManager.shared.addInfoLog(message) } }
            var success: Bool
            if let pid {
                success = JITEnableContext.shared.debugApp(withPID: Int32(pid), logger: logger, jsCallback: callback)
                if success { DispatchQueue.main.async { addRecentPID(pid) } }
            } else if let bundleID {
                success = JITEnableContext.shared.debugApp(withBundleID: bundleID, logger: logger, jsCallback: callback)
            } else {
                DispatchQueue.main.async {
                    showAlert(title: "Failed to Debug App".localized, message: "Either bundle ID or PID should be specified.".localized, showOk: true)
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
    
    private func addRecentPID(_ pid: Int) {
        var list = recentPIDs.filter { $0 != pid }
        list.insert(pid, at: 0)
        if list.count > 8 { list = Array(list.prefix(8)) }
        recentPIDs = list
    }
    
    func base64URLToBase64(_ base64url: String) -> String {
        var base64 = base64url.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = 4 - (base64.count % 4)
        if pad < 4 { base64 += String(repeating: "=", count: pad) }
        return base64
    }
    
    // MARK: - iOS 26+ Disclaimer Card (above main card)
    
    private var disclaimerCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .imageScale(.large)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Important for iOS 26+", comment: ""))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(NSLocalizedString("Limited compatibility on iOS 26 and later. Some apps may not function as expected yet. We’re actively improving support over time.", comment: ""))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            
            if !isOnOrAfteriOS26 {
                Button {
                    withAnimation {
                        showiOS26Disclaimer = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(
                            Circle().fill(Color(UIColor.tertiarySystemBackground))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("Dismiss", comment: ""))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(NSLocalizedString("Important notice for iOS 26 and later. Limited compatibility; improvements are ongoing.", comment: ""))
    }
}

private struct StatusDot: View {
    var color: Color
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.25)).frame(width: 20, height: 20)
            Circle().fill(color).frame(width: 12, height: 12)
                .shadow(color: color.opacity(0.6), radius: 4, x: 0, y: 0)
        }
        .overlay(
            Circle().stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Connect-by-PID Sheet (minus/plus removed)

private struct ConnectByPIDSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var recentPIDs: [Int]
    @State private var pidText: String = ""
    @State private var errorText: String? = nil
    @FocusState private var focused: Bool
    var onPasteCopyToast: () -> Void
    var onConnect: (Int) -> Void
    
    private var isValid: Bool {
        if let v = Int(pidText), v > 0 { return true }
        return false
    }
    
    private let capsuleHeight: CGFloat = 40
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.clear.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(NSLocalizedString("Enter a Process ID", comment: "")).font(.headline).foregroundColor(.primary)
                            
                            TextField(NSLocalizedString("e.g. 1234", comment: ""), text: $pidText)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .font(.system(.title3, design: .rounded))
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                )
                                .focused($focused)
                                .onChange(of: pidText) { _, newVal in validate(newVal) }

                            // Paste + Clear row
                            HStack(spacing: 10) {
                                CapsuleButton(systemName: "doc.on.clipboard", title: NSLocalizedString("Paste", comment: ""), height: capsuleHeight) {
                                    if let n = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                                       let v = Int(n), v > 0 {
                                        pidText = String(v)
                                        validate(pidText)
                                        onPasteCopyToast()
                                    } else {
                                        errorText = NSLocalizedString("No valid PID on the clipboard.", comment: "")
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                }

                                CapsuleButton(systemName: "xmark", title: NSLocalizedString("Clear", comment: ""), height: capsuleHeight) {
                                    pidText = ""
                                    errorText = nil
                                }
                            }

                            
                            if let errorText {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill").font(.footnote)
                                    Text(errorText).font(.footnote)
                                }
                                .foregroundColor(.orange)
                                .transition(.opacity)
                            }
                            
                            if !recentPIDs.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Recents")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.secondary)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(recentPIDs, id: \.self) { pid in
                                                Button {
                                                    pidText = String(pid); validate(pidText)
                                                } label: {
                                                    Text("#\(pid)")
                                                        .font(.footnote.weight(.semibold))
                                                        .padding(.vertical, 6)
                                                        .padding(.horizontal, 10)
                                                        .background(
                                                            Capsule(style: .continuous)
                                                                .fill(Color(UIColor.tertiarySystemBackground))
                                                        )
                                                }
                                                .contextMenu {
                                                    Button(role: .destructive) {
                                                        removeRecent(pid)
                                                    } label: { Label(NSLocalizedString("Remove", comment: ""), systemImage: "trash") }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Button {
                                guard let pid = Int(pidText), pid > 0 else { return }
                                onConnect(pid)
                                addRecent(pid)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "bolt.horizontal.circle").font(.system(size: 20))
                                    Text(NSLocalizedString("Connect", comment: ""))
                                        .font(.system(.title3, design: .rounded))
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundColor(Color.accentColor.contrastText())
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                                )
                            }
                            .disabled(!isValid)
                            .padding(.top, 8)
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 30)
                }
            }
            .navigationTitle(NSLocalizedString("Connect by PID", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
            .onAppear { focused = true }
        }
    }
    
    // Small glassy square icon button
    private func iconSquareButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(UIColor.tertiarySystemBackground))
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
    
    private func validate(_ text: String) {
        if text.isEmpty { errorText = nil; return }
        if Int(text) == nil || Int(text)! <= 0 { errorText = NSLocalizedString("Please enter a positive number.", comment: "") }
        else { errorText = nil }
    }
    private func addRecent(_ pid: Int) {
        var list = recentPIDs.filter { $0 != pid }
        list.insert(pid, at: 0)
        if list.count > 8 { list = Array(list.prefix(8)) }
        recentPIDs = list
    }
    private func removeRecent(_ pid: Int) { recentPIDs.removeAll { $0 == pid } }
    private func prefillFromClipboardIfPossible() {
        if let s = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           let v = Int(s), v > 0 {
            pidText = String(v); errorText = nil
        }
    }
    
    @ViewBuilder private func CapsuleButton(systemName: String, title: String, height: CGFloat = 40, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(height: height) // enforce uniform height
            .padding(.horizontal, 12)
            .background(Capsule(style: .continuous).fill(Color(UIColor.tertiarySystemBackground)))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

#Preview { HomeView() }

// MARK: - TXM detection

public extension ProcessInfo {
    var hasTXM: Bool {
        {
            if let boot = FileManager.default.filePath(atPath: "/System/Volumes/Preboot", withLength: 36),
               let file = FileManager.default.filePath(atPath: "\(boot)/boot", withLength: 96) {
                return access("\(file)/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4", F_OK) == 0
            } else {
                return (FileManager.default.filePath(atPath: "/private/preboot", withLength: 96).map {
                    access("\($0)/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4", F_OK) == 0
                }) ?? false
            }
        }()
    }
}
