//  SettingsView.swift
//  StikJIT
//
//  Created by Stephen on 3/27/25.

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @AppStorage("username") private var username = "User"
    @AppStorage("selectedAppIcon") private var selectedAppIcon: String = "AppIcon"
    @AppStorage("useDefaultScript") private var useDefaultScript = false
    @AppStorage("enableAdvancedOptions") private var enableAdvancedOptions = false
    @AppStorage("enableAdvancedBetaOptions") private var enableAdvancedBetaOptions = false
    @AppStorage("enableTesting") private var enableTesting = false
    @AppStorage("enablePiP") private var enablePiP = false
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    private var currentTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .system }
    
    @State private var isShowingPairingFilePicker = false
    @Environment(\.colorScheme) private var colorScheme

    @State private var showIconPopover = false
    @State private var showPairingFileMessage = false
    @State private var pairingFileIsValid = false
    @State private var isImportingFile = false
    @State private var importProgress: Float = 0.0
    @State private var is_lc = false
    @State private var showColorPickerPopup = false
    
    @State private var showingConsoleLogsView = false
    @State private var showingDisplayView = false
    
    private var appVersion: String {
        let marketingVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return marketingVersion
    }
    
    private var accentColor: Color {
        if customAccentColorHex.isEmpty { return .white }
        return Color(hex: customAccentColorHex) ?? .white
    }
    // Developer profile image URLs
    private let developerProfiles: [String: String] = [
        "Stephen": "https://github.com/StephenDev0.png",
        "jkcoxson": "https://github.com/jkcoxson.png",
        "Stossy11": "https://github.com/Stossy11.png",
        "Neo": "https://github.com/neoarz.png",
        "Se2crid": "https://github.com/Se2crid.png",
        "Huge_Black": "https://github.com/HugeBlack.png",
        "Wynwxst": "https://github.com/Wynwxst.png"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                // Subtle depth gradient background
                ThemedBackground(style: currentTheme.backgroundStyle)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        headerCard
                        appearanceCard
                        pairingCard
                        behaviorCard
                        advancedCard
                        helpCard
                        versionInfo
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 30)
                }
                
                // Busy overlay while importing pairing file
                if isImportingFile {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView(NSLocalizedString("Processing pairing file…", comment: ""))
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
                
                // Success toast after import
                if showPairingFileMessage && pairingFileIsValid && !isImportingFile {
                    VStack {
                        Spacer()
                        Text(NSLocalizedString("✓ Pairing file successfully imported", comment: ""))
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
            .navigationTitle(NSLocalizedString("Settings", comment: ""))
        }
        // Force a white tint in Settings, overriding any global/user tint
        .tint(Color.white)
        .fileImporter(
            isPresented: $isShowingPairingFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "mobiledevicepairing", conformingTo: .data)!, .propertyList],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                
                let fileManager = FileManager.default
                let accessing = url.startAccessingSecurityScopedResource()
                
                if fileManager.fileExists(atPath: url.path) {
                    do {
                        if fileManager.fileExists(atPath: URL.documentsDirectory.appendingPathComponent("pairingFile.plist").path) {
                            try fileManager.removeItem(at: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                        }
                        
                        try fileManager.copyItem(at: url, to: URL.documentsDirectory.appendingPathComponent("pairingFile.plist"))
                        print(NSLocalizedString("File copied successfully!", comment: ""))
                        
                        DispatchQueue.main.async {
                            isImportingFile = true
                            importProgress = 0.0
                            pairingFileIsValid = false
                        }
                        
                        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                            DispatchQueue.main.async {
                                if importProgress < 1.0 {
                                    importProgress += 0.05
                                } else {
                                    timer.invalidate()
                                    isImportingFile = false
                                    pairingFileIsValid = true
                                    
                                    withAnimation {
                                        showPairingFileMessage = true
                                    }
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        withAnimation {
                                            showPairingFileMessage = false
                                        }
                                    }
                                }
                            }
                        }
                        
                        RunLoop.current.add(progressTimer, forMode: .common)
                        startHeartbeatInBackground()
                        
                    } catch {
                        print(String(format: NSLocalizedString("Error copying file: %@", comment: ""), String(describing: error)))
                    }
                } else {
                    print(NSLocalizedString("Source file does not exist.", comment: ""))
                }
                
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            case .failure(let error):
                print(String(format: NSLocalizedString("Failed to import file: %@", comment: ""), String(describing: error)))
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Cards
    
    private var headerCard: some View {
        glassCard {
            VStack(spacing: 16) {
                VStack {
                    Image("StikJIT")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
                Text("StikDebug")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.primary)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    private var appearanceCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(NSLocalizedString("Appearance", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Button(action: { showingDisplayView = true }) {
                    HStack {
                        Image(systemName: "paintbrush")
                            .font(.system(size: 18))
                            .foregroundColor(.primary.opacity(0.85))
                        Text(NSLocalizedString("Display", comment: ""))
                            .foregroundColor(.primary.opacity(0.85))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(4)
        }
        .sheet(isPresented: $showingDisplayView) {
            DisplayView()
                .preferredColorScheme(.dark)
        }
    }
    
    private var pairingCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(NSLocalizedString("Pairing File", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Button {
                    isShowingPairingFilePicker = true
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 18))
                        Text(NSLocalizedString("Import New Pairing File", comment: ""))
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundColor(accentColor.contrastText())
                    .background(accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
                }
                
                if showPairingFileMessage && pairingFileIsValid && !isImportingFile {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text(NSLocalizedString("Pairing file successfully imported", comment: ""))
                            .font(.callout)
                            .foregroundColor(.green)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .transition(.opacity)
                }
            }
        }
    }
    
    private var behaviorCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("Behavior", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Toggle(NSLocalizedString("Run Default Script After Connecting", comment: ""), isOn: $useDefaultScript)
                    .tint(accentColor)
                Toggle(NSLocalizedString("Picture in Picture", comment: ""), isOn: $enablePiP)
                    .tint(accentColor)
            }
            .onChange(of: enableAdvancedOptions) { _, newValue in
                if !newValue {
                    useDefaultScript = false
                    enablePiP = false
                    enableAdvancedBetaOptions = false
                    enableTesting = false
                }
            }
            .onChange(of: enableAdvancedBetaOptions) { _, newValue in
                if !newValue {
                    enableTesting = false
                }
            }
        }
    }
        
    private var advancedCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(NSLocalizedString("Advanced", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Button(action: { showingConsoleLogsView = true }) {
                    HStack {
                        Image(systemName: "terminal")
                            .font(.system(size: 18))
                            .foregroundColor(.primary.opacity(0.8))
                        Text(NSLocalizedString("System Logs", comment: ""))
                            .foregroundColor(.primary.opacity(0.8))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 8)
                }
                
                Button(action: { openAppFolder() }) {
                    HStack {
                        Image(systemName: "folder")
                            .font(.system(size: 18))
                            .foregroundColor(.primary.opacity(0.8))
                        Text(NSLocalizedString("App Folder", comment: ""))
                            .foregroundColor(.primary.opacity(0.8))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $showingConsoleLogsView) {
            ConsoleLogsView()
                .preferredColorScheme(.dark)
        }
    }
    
    private var helpCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(NSLocalizedString("Help", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Button(action: {
                    if let url = URL(string: "https://github.com/StephenDev0/StikDebug-Guide/blob/main/pairing_file.md") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 18))
                            .foregroundColor(.primary.opacity(0.8))
                        Text(NSLocalizedString("Pairing File Guide", comment: ""))
                            .foregroundColor(.primary.opacity(0.8))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                Button(action: {
                    if let url = URL(string: "https://discord.gg/qahjXNTDwS") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 18))
                            .foregroundColor(.primary.opacity(0.8))
                        Text(NSLocalizedString("Need support? Join the Discord!", comment: ""))
                            .foregroundColor(.primary.opacity(0.8))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "shield.slash")
                        .font(.system(size: 18))
                        .foregroundColor(.primary.opacity(0.8))
                    Text(NSLocalizedString("You can turn off the VPN in the Settings app.", comment: ""))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }
    
    private var versionInfo: some View {
        let txmLabel = ProcessInfo.processInfo.hasTXM ? "TXM" : "Non TXM"
        return HStack {
            Spacer()
            Text(String(format: NSLocalizedString("Version %@ • iOS %@ • %@", comment: "App version • iOS version • TXM label"), appVersion, UIDevice.current.systemVersion, txmLabel))
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.top, 6)
    }
    
    // MARK: - Helpers (UI + logic)
    
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
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
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    }
        
    private func changeAppIcon(to iconName: String) {
        selectedAppIcon = iconName
        UIApplication.shared.setAlternateIconName(iconName == "AppIcon" ? nil : iconName) { error in
            if let error = error {
                print(String(format: NSLocalizedString("Error changing app icon: %@", comment: ""), error.localizedDescription))
            }
        }
    }
    
    private func iconButton(_ label: String, icon: String) -> some View {
        Button(action: {
            changeAppIcon(to: icon)
            showIconPopover = false
        }) {
            HStack {
                Image(uiImage: UIImage(named: icon) ?? UIImage())
                    .resizable()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Text(label)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(10)
        }
        .padding(.horizontal)
    }
    
    private func openAppFolder() {
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let path = documentsURL.absoluteString.replacingOccurrences(of: "file://", with: "shareddocuments://")
            if let url = URL(string: path) {
                UIApplication.shared.open(url, options: [:]) { success in
                    if !success {
                        print(NSLocalizedString("Failed to open app folder", comment: ""))
                    }
                }
            }
        }
    }
}

// MARK: - Helper Components

struct SettingsCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 2)
    }
}

struct InfoRow: View {
    var title: String
    var value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .foregroundColor(.primary)
                .fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }
}

struct LinkRow: View {
    var icon: String
    var title: String
    var url: String
    
    var body: some View {
        Button(action: {
            if let url = URL(string: url) {
                UIApplication.shared.open(url)
            }
        }) {
            HStack(alignment: .center) {
                Text(title)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 24)
            }
        }
        .padding(.vertical, 8)
        .preferredColorScheme(.dark)
    }
}

struct ConsoleLogsView_Preview: PreviewProvider {
    static var previews: some View {
        ConsoleLogsView()
            .preferredColorScheme(.dark)
    }
}

class FolderViewController: UIViewController {
    func openAppFolder() {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        guard let documentsDirectory = paths.first else { return }
        let containerPath = (documentsDirectory as NSString).deletingLastPathComponent
        
        if let folderURL = URL(string: "shareddocuments://\(containerPath)") {
            UIApplication.shared.open(folderURL, options: [:]) { success in
                if !success {
                    let regularURL = URL(fileURLWithPath: containerPath)
                    UIApplication.shared.open(regularURL, options: [:], completionHandler: nil)
                }
            }
        }
    }
}
