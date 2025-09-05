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

    @State private var isShowingPairingFilePicker = false
    @Environment(\.colorScheme) private var colorScheme

    @State private var showIconPopover = false
    @State private var showPairingFileMessage = false
    @State private var pairingFileIsValid = false
    @State private var isImportingFile = false
    @State private var importProgress: Float = 0.0
    @State private var is_lc = false
    @State private var showColorPickerPopup = false
    
    @StateObject private var mountProg = MountingProgress.shared
    
    @State private var mounted = false
    
    @State private var showingConsoleLogsView = false
    @State private var showingDisplayView = false
    
    private var appVersion: String {
        let marketingVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return marketingVersion
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
                        headerCard
                        appearanceCard
                        pairingCard
                        ddiCard
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
                        ProgressView("Processing pairing file…")
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
            .navigationTitle("Settings")
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
                        print("File copied successfully!")
                        
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
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Cards
    
    private var headerCard: some View {
        materialCard {
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
        materialCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Appearance")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Button(action: { showingDisplayView = true }) {
                    HStack {
                        Image(systemName: "paintbrush")
                            .font(.system(size: 18))
                            .foregroundColor(.primary.opacity(0.85))
                        Text("Display")
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
        materialCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Pairing File")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Button {
                    isShowingPairingFilePicker = true
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 18))
                        Text("Import New Pairing File")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundColor(.black)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                
                if showPairingFileMessage && pairingFileIsValid && !isImportingFile {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Pairing file successfully imported")
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
    
    private var ddiCard: some View {
        materialCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Developer Disk Image")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 12) {
                    Image(systemName: mounted || (mountProg.mountProgress == 100) ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(mounted || (mountProg.mountProgress == 100) ? .green : .red)
                    
                    Text(mounted || (mountProg.mountProgress == 100) ? "Successfully Mounted" : "Not Mounted")
                        .font(.body.weight(.medium))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(UIColor.tertiarySystemBackground))
                )
                
                if !(mounted || (mountProg.mountProgress == 100)) {
                    Text("Import pairing file and restart the app to mount DDI")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if mountProg.mountProgress > 0 && mountProg.mountProgress < 100 && !mounted {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Mounting in progress…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(mountProg.mountProgress))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(UIColor.tertiarySystemFill))
                                    .frame(height: 8)
                                
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.green)
                                    .frame(width: geometry.size.width * CGFloat(mountProg.mountProgress / 100.0), height: 8)
                                    .animation(.linear(duration: 0.3), value: mountProg.mountProgress)
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
            .onAppear {
                self.mounted = isMounted()
            }
        }
    }
    
    private var behaviorCard: some View {
        materialCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Behavior")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Toggle("Run Default Script After Connecting", isOn: $useDefaultScript)
                    .foregroundColor(.primary)
                Toggle("Picture in Picture", isOn: $enablePiP)
                    .foregroundColor(.primary)
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
    
    private var aboutCard: some View {
        materialCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("About")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Creators")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        creatorTile(name: "Stephen", role: "App Creator", url: "https://github.com/StephenDev0", imageUrl: developerProfiles["Stephen"] ?? "")
                        creatorTile(name: "jkcoxson", role: "idevice & em_proxy", url: "https://jkcoxson.com/", imageUrl: developerProfiles["jkcoxson"] ?? "")
                    }
                }
                
                Divider().background(Color.white.opacity(0.12))
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Developers")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 10) {
                        CollaboratorRow(name: "Stossy11", url: "https://github.com/Stossy11", imageUrl: developerProfiles["Stossy11"] ?? "")
                        CollaboratorRow(name: "Neo", url: "https://neoarz.xyz/", imageUrl: developerProfiles["Neo"] ?? "")
                        CollaboratorRow(name: "Se2crid", url: "https://github.com/Se2crid", imageUrl: developerProfiles["Se2crid"] ?? "")
                        CollaboratorRow(name: "Huge_Black", url: "https://github.com/HugeBlack", imageUrl: developerProfiles["Huge_Black"] ?? "")
                        CollaboratorRow(name: "Wynwxst", url: "https://github.com/Wynwxst", imageUrl: developerProfiles["Wynwxst"] ?? "")
                    }
                }
            }
        }
    }
    
    private var advancedCard: some View {
        materialCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Advanced")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Button(action: { showingConsoleLogsView = true }) {
                    HStack {
                        Image(systemName: "terminal")
                            .font(.system(size: 18))
                            .foregroundColor(.primary.opacity(0.8))
                        Text("System Logs")
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
                        Text("App Folder")
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
        materialCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Help")
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
                        Text("Pairing File Guide")
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
                        Text("Need support? Join the Discord!")
                            .foregroundColor(.primary.opacity(0.8))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "shield.slash")
                        .font(.system(size: 18))
                        .foregroundColor(.primary.opacity(0.8))
                    Text("You can turn off the VPN in the Settings app.")
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }
    
    private var versionInfo: some View {
        HStack {
            Spacer()
            Text("Version \(appVersion) • iOS \(UIDevice.current.systemVersion)")
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.top, 6)
    }
    
    // MARK: - Helpers (UI + logic)
    
    private func materialCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
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
    
    private func creatorTile(name: String, role: String, url: String, imageUrl: String) -> some View {
        Button(action: {
            if let u = URL(string: url) { UIApplication.shared.open(u) }
        }) {
            VStack(spacing: 8) {
                ProfileImage(url: imageUrl)
                    .frame(width: 60, height: 60)
                Text(name).fontWeight(.semibold)
                Text(role)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(UIColor.tertiarySystemBackground))
            )
        }
    }
    
    private func changeAppIcon(to iconName: String) {
        selectedAppIcon = iconName
        UIApplication.shared.setAlternateIconName(iconName == "AppIcon" ? nil : iconName) { error in
            if let error = error {
                print("Error changing app icon: \(error.localizedDescription)")
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
                        print("Failed to open app folder")
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

struct CollaboratorGridItem: View {
    var name: String
    var url: String
    var imageUrl: String
    
    var body: some View {
        Button(action: {
            if let url = URL(string: url) {
                UIApplication.shared.open(url)
            }
        }) {
            VStack(spacing: 8) {
                ProfileImage(url: imageUrl)
                    .frame(width: 50, height: 50)
                Text(name)
                    .foregroundColor(.primary)
                    .fontWeight(.medium)
                    .font(.subheadline)
            }
            .frame(minWidth: 80)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(12)
        }
        .preferredColorScheme(.dark)
    }
}

struct ProfileImage: View {
    var url: String
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            } else {
                Circle()
                    .fill(Color(UIColor.systemGray4))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    )
                    .onAppear {
                        loadImage()
                    }
            }
        }
    }
    
    private func loadImage() {
        guard let imageUrl = URL(string: url) else { return }
        URLSession.shared.dataTask(with: imageUrl) { data, response, error in
            if let data = data, let downloadedImage = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.image = downloadedImage
                }
            }
        }.resume()
    }
}

struct CollaboratorRow: View {
    var name: String
    var url: String
    var imageUrl: String
    var quote: String?
    
    var body: some View {
        Button(action: {
            if let url = URL(string: url) {
                UIApplication.shared.open(url)
            }
        }) {
            HStack(spacing: 12) {
                ProfileImage(url: imageUrl)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .foregroundColor(.primary)
                        .fontWeight(.medium)
                    if let quote = quote {
                        Text("“\(quote)”")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer()
                Image(systemName: "link")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
            }
            .padding(.vertical, 8)
        }
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

