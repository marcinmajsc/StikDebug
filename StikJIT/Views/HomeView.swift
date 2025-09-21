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
    @AppStorage("enableAdvancedOptions") private var enableAdvancedOptions = true

    @AppStorage("useDefaultScript") private var useDefaultScript = false
    @AppStorage("enablePiP") private var enablePiP = true
    @State var scriptViewShow = false
    @State var pipRequired = false
    @AppStorage("DefaultScriptName") var selectedScript = "attachDetach.js"
    @State var jsModel: RunJSViewModel?
    
    // New: allow overriding TXM requirement for scripts
    @AppStorage("ignoreTXMForScripts") private var ignoreTXMForScripts = false
    
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
    private var isDismissibleDisclaimer: Bool { !isOnOrAfteriOS26 }
    
    // Observe VPN status
    @StateObject private var tunnelManager = TunnelManager.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(style: currentTheme.backgroundStyle)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        if isOnOrAfteriOS26 || showiOS26Disclaimer {
                            disclaimerCard
                                .transition(.opacity .combined(with: .move(edge: .top)))
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
                    ProgressView("Processing pairing file…")
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
                    toast("✓ Pairing file successfully imported")
                }
                if justCopied {
                    toast("Copied")
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
            ) { _ in isShowingPairingFilePicker = true }
        }
        .onReceive(timer) { _ in
            refreshBackground()
            checkPairingFileExists()
            heartbeatOK = pubHeartBeat
        }
        .fileImporter(
            isPresented: $isShowingPairingFilePicker,
            allowedContentTypes: [
                UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!,
                .propertyList
            ]
        ) { result in
            if case .success(let url) = result {
                importPairingFile(from: url)
            } else if case .failure(let error) = result {
                print("Failed to import file: \(error)")
            }
        }
        .sheet(isPresented: $isShowingInstalledApps) {
            InstalledAppsListView { selectedBundle in
                handleAppSelection(selectedBundle)
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
                                Button("Done") { scriptViewShow = false }
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
                indicatorCapsule(ok: tunnelManager.tunnelStatus == .connected, systemImage: "lock.shield", a11y: "VPN")
                indicatorCapsule(ok: heartbeatOK, systemImage: "waveform.path.ecg", a11y: "Heartbeat")
                Spacer()
            }
            VStack(spacing: 4) {
                Text("Welcome, \(username)")
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
                        title: pairingFileExists ? "Connect by App" : "Select Pairing File"
                    )
                }
                .disabled(pairingFileExists && !ddiMounted)
                .opacity(pairingFileExists && !ddiMounted ? 0.6 : 1.0)
                
                if pairingFileExists && enableAdvancedOptions {
                    Button(action: { showPIDSheet = true }) {
                        whiteCardButtonLabel(icon: "number.circle", title: "Connect by PID")
                    }
                }
            }

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
                    Text("Pairing file successfully imported")
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
            Text("Tools").font(.headline).foregroundColor(.secondary)
            
            // Console
            Button(action: { showingConsoleLogsView = true }) {
                HStack {
                    Image(systemName: "terminal").font(.system(size: 20))
                    Text("Open Console").font(.system(.title3, design: .rounded)).fontWeight(.semibold)
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
            Text("Tips").font(.headline).foregroundColor(.secondary)
            if !pairingFileExists {
                tipRow(systemImage: "doc.badge.plus", title: "Pairing file required", message: "Import your device’s pairing file to begin.")
            }
            if pairingFileExists && !ddiMounted {
                tipRow(systemImage: "externaldrive.badge.exclamationmark", title: "Developer Disk Image not mounted", message: "Go to Settings → Developer Disk Image and ensure it’s mounted.")
            }
            tipRow(systemImage: "lock.shield", title: "Local only", message: "StikDebug runs entirely on-device. No data leaves your device.")
            
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
                        Text("Pairing File Guide")
                            .font(.subheadline).fontWeight(.semibold)
                        Text("Learn how to create and import your pairing file.")
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
            // …existing script selection logic…

            var callback: DebugAppCallback? = nil
            // Allow script if TXM is present OR user chose to ignore TXM requirement
            if (ProcessInfo.processInfo.hasTXM || ignoreTXMForScripts), let sd = scriptData {
                callback = getJsCallback(sd, name: scriptName ?? bundleID ?? "Script")
                if triggeredByURLScheme { usleep(500000) }
                pipRequired = true
            } else {
                pipRequired = false
            }

            // …rest unchanged…
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
                Text("Important for iOS 26+")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text("Limited compatibility on iOS 26 and later. Some apps may not function as expected yet. We’re actively improving support over time.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            
            if isDismissibleDisclaimer {
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
                .accessibilityLabel("Dismiss")
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
        .accessibilityLabel("Important notice for iOS 26 and later. Limited compatibility; improvements are ongoing.")
    }
    
    // MARK: - Helpers extracted to avoid heavy type-check
    
    private func importPairingFile(from url: URL) {
        let fileManager = FileManager.default
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            let dest = URL.documentsDirectory.appendingPathComponent("pairingFile.plist")
            if fileManager.fileExists(atPath: dest.path) {
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
            print("Error copying file: \(error)")
        }
    }
    
    private func handleAppSelection(_ selectedBundle: String) {
        bundleID = selectedBundle
        isShowingInstalledApps = false
        HapticFeedbackHelper.trigger()
        
        let auto = computeAutoScript(for: selectedBundle)
        startJITInBackground(bundleID: selectedBundle,
                             pid: nil,
                             scriptData: auto.data,
                             scriptName: auto.name,
                             triggeredByURLScheme: false)
    }
    
    private func computeAutoScript(for bundleID: String) -> (data: Data?, name: String?) {
        var autoScriptData: Data? = nil
        var autoScriptName: String? = nil
        
        let appName: String? = (try? JITEnableContext.shared.getAppList()[bundleID])
        if #available(iOS 26, *) {
            if ProcessInfo.processInfo.hasTXM, let appName {
                func loadScript(resource: String, name: String) {
                    if let url = Bundle.main.url(forResource: resource, withExtension: "js"),
                       let data = try? Data(contentsOf: url) {
                        autoScriptData = data
                        autoScriptName = name
                    }
                }
                switch appName {
                case "maciOS":
                    loadScript(resource: "script1", name: "script1.js")
                case "Amethyst":
                    loadScript(resource: "script2", name: "script2.js")
                case "MeloNX":
                    loadScript(resource: "melo", name: "melo.js")
                case "UTM", "DolphiniOS":
                    loadScript(resource: "utmjit", name: "utmjit.js")
                default:
                    break
                }
            }
        }
        return (autoScriptData, autoScriptName)
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
                            Text("Enter a Process ID").font(.headline).foregroundColor(.primary)
                            
                            TextField("e.g. 1234", text: $pidText)
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
                                CapsuleButton(systemName: "doc.on.clipboard", title: "Paste", height: capsuleHeight) {
                                    if let n = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                                       let v = Int(n), v > 0 {
                                        pidText = String(v)
                                        validate(pidText)
                                        onPasteCopyToast()
                                    } else {
                                        errorText = "No valid PID on the clipboard."
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                }

                                CapsuleButton(systemName: "xmark", title: "Clear", height: capsuleHeight) {
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
                                                    } label: { Label("Remove", systemImage: "trash") }
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
                                    Text("Connect")
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
            .navigationTitle("Connect by PID")
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
        if Int(text) == nil || Int(text)! <= 0 { errorText = "Please enter a positive number." }
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

