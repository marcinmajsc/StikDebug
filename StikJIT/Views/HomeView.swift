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
    @AppStorage("recentApps") private var recentApps: [String] = []
    @AppStorage("favoriteApps") private var favoriteApps: [String] = []
    @State private var isProcessing = false
    @State private var isShowingInstalledApps = false
    @State private var isShowingPairingFilePicker = false
    @State private var pairingFileExists: Bool = false
    @State private var showPairingFileMessage = false
    @State private var pairingFileIsValid = false
    @State private var isImportingFile = false
    @State private var importProgress: Float = 0.0
    
    @State private var showPIDSheet = false
    @AppStorage("recentPIDs") private var recentPIDs: [Int] = []
    @State private var justCopied = false
    @State private var showingConsoleLogsView = false
    
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
    @State private var cachedAppNames: [String: String] = [:]
    @State private var isLoadingQuickApps = false

    @AppStorage("showiOS26Disclaimer") private var showiOS26Disclaimer: Bool = true
    
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @Environment(\.themeExpansionManager) private var themeExpansion
    private var backgroundStyle: BackgroundStyle { themeExpansion?.backgroundStyle(for: appThemeRaw) ?? AppTheme.system.backgroundStyle }
    private var preferredScheme: ColorScheme? { themeExpansion?.preferredColorScheme(for: appThemeRaw) }

    private var accentColor: Color {
        themeExpansion?.resolvedAccentColor(from: customAccentColorHex) ?? .blue
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
                ThemedBackground(style: backgroundStyle)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        if isOnOrAfteriOS26 || showiOS26Disclaimer {
                            disclaimerCard
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        readinessCard
                        quickConnectCard
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
        .preferredColorScheme(preferredScheme)
        .onAppear {
            checkPairingFileExists()
            refreshBackground()
            loadAppListIfNeeded()
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
        .onChange(of: pairingFileExists) { _, newValue in
            if newValue {
                loadAppListIfNeeded(force: cachedAppNames.isEmpty)
            } else {
                cachedAppNames = [:]
            }
        }
        .onChange(of: favoriteApps) { _, _ in
            loadAppListIfNeeded()
        }
        .onChange(of: recentApps) { _, _ in
            loadAppListIfNeeded()
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
                        print("Error copying file: \(error)")
                    }
                }
                if accessing { url.stopAccessingSecurityScopedResource() }
            case .failure(let error):
                print("Failed to import file: \(error)")
            }
        }
        .sheet(isPresented: $showingConsoleLogsView) {
            if let manager = themeExpansion {
                ConsoleLogsView().themeExpansionManager(manager)
            } else {
                ConsoleLogsView()
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
    
    private var readinessCard: some View {
        homeCard {
            VStack(alignment: .leading, spacing: 16) {
                let summary = readinessSummary

                HStack(alignment: .top, spacing: 12) {
                    StatusGlyph(icon: summary.icon, tint: summary.tint)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Welcome, \(username)")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(.primary)

                        Text(summary.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(summary.tint)

                        Text(summary.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(readinessChecklist) { item in
                        ChecklistRow(item: item, accentColor: accentColor)
                    }
                }

                VStack(spacing: 10) {
                    Button(action: primaryActionTapped) {
                        whiteCardButtonLabel(icon: primaryActionIcon, title: primaryActionTitle, isLoading: isProcessing)
                    }
                    .disabled(isProcessing)

                    if pairingFileExists && enableAdvancedOptions {
                        Button(action: { showPIDSheet = true }) {
                            secondaryButtonLabel(icon: "number.circle", title: "Connect by PID")
                        }
                        .disabled(isProcessing)
                    }
                }

                if isImportingFile {
                    pairingImportProgressView
                } else if showPairingFileMessage && pairingFileIsValid {
                    pairingSuccessMessage
                }
            }
        }
    }

    private var readinessSummary: ReadinessSummary {
        if !pairingFileExists {
            return .init(
                title: "Import your pairing file",
                subtitle: "Grab the pairing file from your computer to unlock app discovery.",
                icon: "doc.badge.plus",
                tint: .orange
            )
        }
        if !ddiMounted {
            return .init(
                title: "Mount the Developer Disk Image",
                subtitle: "Open Settings → Developer Disk Image and follow the prompts before connecting.",
                icon: "externaldrive.badge.exclamationmark",
                tint: .yellow
            )
        }
        if tunnel.tunnelStatus != .connected {
            return .init(
                title: "Connect the VPN",
                subtitle: "Tap Allow when iOS prompts you, then flip the toggle in Settings if needed.",
                icon: "lock.slash",
                tint: .orange
            )
        }
        if !heartbeatOK {
            return .init(
                title: "Waiting for heartbeat",
                subtitle: "StikDebug is reaching out to your device. We’ll connect automatically once it responds.",
                icon: "waveform.path.ecg",
                tint: .orange
            )
        }
        return .init(
            title: "Ready when you are",
            subtitle: "Everything is ready. Select an app to enable debugging or JIT in seconds.",
            icon: "bolt.horizontal.circle.fill",
            tint: .green
        )
    }

    private var primaryActionTitle: String {
        if !pairingFileExists { return "Import Pairing File" }
        if !ddiMounted { return "Mount Developer Disk Image" }
        return "Connect by App"
    }

    private var primaryActionIcon: String {
        if !pairingFileExists { return "doc.badge.plus" }
        if !ddiMounted { return "externaldrive" }
        return "cable.connector.horizontal"
    }

    private var readinessChecklist: [ChecklistItem] {
        let vpnConnected = tunnel.tunnelStatus == .connected

        return [
            ChecklistItem(
                title: "Pairing file",
                subtitle: pairingFileExists ? "Imported and valid." : "Import the pairing file generated from your trusted computer.",
                status: pairingFileExists ? .ready : .actionRequired,
                actionTitle: pairingFileExists ? nil : "Import",
                action: pairingFileExists ? nil : { isShowingPairingFilePicker = true }
            ),
            ChecklistItem(
                title: "Developer Disk Image",
                subtitle: ddiMounted ? "Mounted successfully." : "Open Settings → Developer Disk Image and tap Mount.",
                status: ddiMounted ? .ready : .attention,
                actionTitle: nil,
                action: nil
            ),
            ChecklistItem(
                title: "VPN tunnel",
                subtitle: vpnConnected ? "Active." : "Connect the StikDebug VPN from the Settings app if it’s not already on.",
                status: vpnConnected ? .ready : .attention,
                actionTitle: nil,
                action: nil
            ),
            ChecklistItem(
                title: "Heartbeat",
                subtitle: heartbeatOK ? "Active." : "We retry automatically—leave the app open for a moment.",
                status: heartbeatOK ? .ready : .waiting,
                actionTitle: nil,
                action: nil
            )
        ]
    }

    private var pairingImportProgressView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Processing pairing file…")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(importProgress * 100))%")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(UIColor.tertiarySystemFill))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(accentColor)
                        .frame(width: geo.size.width * CGFloat(importProgress), height: 8)
                        .animation(.linear(duration: 0.25), value: importProgress)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }

    private var pairingSuccessMessage: some View {
        HStack(spacing: 10) {
            StatusDot(color: .green)
            Text("Pairing file successfully imported")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.green)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .transition(.opacity)
    }

    private func whiteCardButtonLabel(icon: String, title: String, isLoading: Bool = false) -> some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(accentColor.contrastText())
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
            }

            Text(title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundColor(accentColor.contrastText())
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }

    private func secondaryButtonLabel(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .foregroundStyle(.primary)
    }

    private var quickConnectCard: some View {
        homeCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("Quick Connect")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if isLoadingQuickApps {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                    }
                }

                Text("Favorites and recents stay within reach so you can enable JIT without leaving Home.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if quickConnectItems.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pin apps from the Installed Apps list to see them here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            isShowingInstalledApps = true
                        } label: {
                            secondaryButtonLabel(icon: "star", title: "Choose Favorites")
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(quickConnectItems) { item in
                            QuickConnectRow(
                                item: item,
                                accentColor: accentColor,
                                isEnabled: canConnectByApp && !isProcessing,
                                action: {
                                    HapticFeedbackHelper.trigger()
                                    startJITInBackground(bundleID: item.bundleID,
                                                         pid: nil,
                                                         scriptData: nil,
                                                         scriptName: nil,
                                                         triggeredByURLScheme: false)
                                }
                            )
                        }
                    }
                }

                if !canConnectByApp {
                    Text("Finish the pairing and mounting steps above to enable quick launches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var quickConnectItems: [QuickConnectItem] {
        var seen = Set<String>()
        var ordered: [QuickConnectItem] = []
        for bundle in favoriteApps + recentApps {
            guard seen.insert(bundle).inserted else { continue }
            ordered.append(QuickConnectItem(bundleID: bundle, displayName: friendlyName(for: bundle)))
            if ordered.count >= 4 { break }
        }
        return ordered
    }

    private func friendlyName(for bundleID: String) -> String {
        if let cached = cachedAppNames[bundleID], !cached.isEmpty { return cached }
        let components = bundleID.split(separator: ".")
        if let last = components.last {
            let cleaned = last.replacingOccurrences(of: "_", with: " ")
            let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed.capitalized }
        }
        return bundleID
    }

    private func loadAppListIfNeeded(force: Bool = false) {
        guard pairingFileExists else {
            cachedAppNames = [:]
            isLoadingQuickApps = false
            return
        }

        if isLoadingQuickApps { return }
        if !force && !cachedAppNames.isEmpty { return }

        isLoadingQuickApps = true

        DispatchQueue.global(qos: .userInitiated).async {
            let result = (try? JITEnableContext.shared.getAppList()) ?? [:]
            DispatchQueue.main.async {
                cachedAppNames = result
                isLoadingQuickApps = false
            }
        }
    }

    private func homeCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
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

    private var toolsCard: some View {
        homeCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tools")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    Button {
                        showingConsoleLogsView = true
                    } label: {
                        whiteCardButtonLabel(icon: "terminal", title: "Open Console")
                    }

             //       Button {
              //          isShowingInstalledApps = true
              //      } label: {
               //         secondaryButtonLabel(icon: "list.bullet", title: "Installed Apps")
               //     }
               //     .buttonStyle(.plain)
                }
            }
        }
    }

    private var tipsCard: some View {
        homeCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tips")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if !pairingFileExists {
                    tipRow(systemImage: "doc.badge.plus", title: "Pairing file required", message: "Import your device’s pairing file to begin.")
                }
                if pairingFileExists && !ddiMounted {
                    tipRow(systemImage: "externaldrive.badge.exclamationmark", title: "Developer Disk Image not mounted", message: "Go to Settings → Developer Disk Image and ensure it’s mounted.")
                }
                tipRow(systemImage: "lock.shield", title: "Local only", message: "StikDebug runs entirely on-device. No data leaves your device.")

                Divider().background(Color.white.opacity(0.1))

                Button {
                    if let url = URL(string: "https://github.com/StephenDev0/StikDebug-Guide/blob/main/pairing_file.md") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(accentColor)
                            .font(.system(size: 18, weight: .semibold))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pairing File Guide")
                                .font(.subheadline.weight(.semibold))
                            Text("Step-by-step instructions from the community wiki.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tipRow(systemImage: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(accentColor)
                .font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
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
                Text("Important for iOS 26+")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text("Limited compatibility on iOS 26 and later. Some apps may not function as expected yet. We’re actively improving support over time.")
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

private struct StatusGlyph: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 48
    var iconSize: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: size, height: size)

            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

private struct ChecklistRow: View {
    let item: ChecklistItem
    let accentColor: Color

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            StatusGlyph(icon: item.status.iconName, tint: item.status.tint, size: 40, iconSize: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let actionTitle = item.actionTitle, let action = item.action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(accentColor.opacity(0.18))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(accentColor.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct QuickConnectRow: View {
    let item: QuickConnectItem
    let accentColor: Color
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                QuickAppBadge(title: item.displayName, accentColor: accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(item.bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)

                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isEnabled ? accentColor : Color.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground).opacity(isEnabled ? 0.65 : 0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

private struct QuickAppBadge: View {
    let title: String
    let accentColor: Color

    private var initials: String {
        let words = title.split(separator: " ")
        if let first = words.first, !first.isEmpty {
            return String(first.prefix(1)).uppercased()
        }
        return String(title.prefix(1)).uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentColor.opacity(0.16))
            )
            .foregroundStyle(accentColor)
    }
}

private struct ReadinessSummary {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
}

private enum ChecklistStatus {
    case ready
    case waiting
    case attention
    case actionRequired

    var iconName: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .waiting: return "clock.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .actionRequired: return "exclamationmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready: return .green
        case .waiting: return .orange
        case .attention: return .yellow
        case .actionRequired: return .red
        }
    }
}

private struct ChecklistItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let status: ChecklistStatus
    let actionTitle: String?
    let action: (() -> Void)?
}

private struct QuickConnectItem: Identifiable {
    let bundleID: String
    let displayName: String
    var id: String { bundleID }
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
