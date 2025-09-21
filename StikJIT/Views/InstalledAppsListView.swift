//
//  InstalledAppsListView.swift
//  StikJIT
//
//  Created by Stossy11 on 28/03/2025.
//

import SwiftUI
import UIKit
import WidgetKit
import Combine

// MARK: - Installed Apps List

struct InstalledAppsListView: View {
    @StateObject private var viewModel = InstalledAppsViewModel()

    @State private var appIcons: [String: UIImage] = [:]
    private let sharedDefaults = UserDefaults(suiteName: "group.com.stik.sj")!

    @AppStorage("recentApps") private var recentApps: [String] = []
    @AppStorage("favoriteApps") private var favoriteApps: [String] = [] {
        didSet {
            if favoriteApps.count > 4 {
                favoriteApps = Array(favoriteApps.prefix(4))
            }
            persistIfChanged()
        }
    }

    @AppStorage("performanceMode") private var performanceMode = false
    @State private var showPerformanceToast = false

    @Environment(\.dismiss) private var dismiss
    var onSelectApp: (String) -> Void

    private var filteredRecents: [String] {
        recentApps.filter { !favoriteApps.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.ignoresSafeArea()

                if viewModel.apps.isEmpty {
                    emptyState
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .scale))
                } else {
                    appsList
                        .transition(.opacity)
                        .transaction { t in t.disablesAnimations = true }
                }

                if showPerformanceToast {
                    VStack {
                        Spacer()
                        Text(performanceMode ? "Performance Mode On" : "Performance Mode Off")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .shadow(radius: 4)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 40)
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showPerformanceToast)
                }
            }
            .navigationTitle("Installed Apps".localized)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        performanceMode.toggle()
                        Haptics.selection()
                        showPerformanceToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation {
                                showPerformanceToast = false
                            }
                        }
                    } label: {
                        Image(systemName: performanceMode ? "bolt.fill" : "bolt.slash.fill")
                            .imageScale(.large)
                            .foregroundStyle(performanceMode ? .yellow : .secondary)
                            .accessibilityLabel("Toggle Performance Mode")
                            .accessibilityValue(performanceMode ? "On" : "Off")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundStyle(.secondary)

            Text("No Debuggable App Found")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Text("""
            StikDebug can only connect to apps with the “get-task-allow” entitlement.
            Please check if the app you want to connect to is signed with a development certificate.
            """)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
        .padding(24)
        .glassCard(cornerRadius: 24, material: .thinMaterial, strokeOpacity: 0.12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No debuggable app found. Ensure the app is signed for development.")
    }

    // MARK: Apps List

    private var appsList: some View {
        ScrollView {
            VStack(spacing: 18) {
                if !favoriteApps.isEmpty {
                    glassSection(
                        title: String(format: "Favorites (%d/4)".localized, favoriteApps.count)
                    ) {
                        LazyVStack(spacing: 12) {
                            ForEach(favoriteApps, id: \.self) { bundleID in
                                AppButton(
                                    bundleID: bundleID,
                                    appName: viewModel.apps[bundleID] ?? bundleID,
                                    recentApps: $recentApps,
                                    favoriteApps: $favoriteApps,
                                    appIcons: $appIcons,
                                    onSelectApp: onSelectApp,
                                    sharedDefaults: sharedDefaults,
                                    performanceMode: performanceMode
                                )
                            }
                        }
                    }
                }

                if !filteredRecents.isEmpty {
                    glassSection(title: "Recents".localized) {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredRecents, id: \.self) { bundleID in
                                AppButton(
                                    bundleID: bundleID,
                                    appName: viewModel.apps[bundleID] ?? bundleID,
                                    recentApps: $recentApps,
                                    favoriteApps: $favoriteApps,
                                    appIcons: $appIcons,
                                    onSelectApp: onSelectApp,
                                    sharedDefaults: sharedDefaults,
                                    performanceMode: performanceMode
                                )
                            }
                        }
                    }
                }

                glassSection(title: "All Applications".localized) {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.apps.sorted(by: { $0.key < $1.key }), id: \.key) { bundleID, appName in
                            AppButton(
                                bundleID: bundleID,
                                appName: appName,
                                recentApps: $recentApps,
                                favoriteApps: $favoriteApps,
                                appIcons: $appIcons,
                                onSelectApp: onSelectApp,
                                sharedDefaults: sharedDefaults,
                                performanceMode: performanceMode
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    // MARK: Section Wrapper

    private func glassSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            content()
        }
        .padding(20)
        .glassCard(material: .thinMaterial, strokeOpacity: 0.12)
    }

    // MARK: Persistence gate (avoid redundant writes + reloads)

    private func persistIfChanged() {
        var touched = false
        let prevR = (sharedDefaults.array(forKey: "recentApps") as? [String]) ?? []
        let prevF = (sharedDefaults.array(forKey: "favoriteApps") as? [String]) ?? []

        if prevR != recentApps {
            sharedDefaults.set(recentApps, forKey: "recentApps")
            touched = true
        }
        if prevF != favoriteApps {
            sharedDefaults.set(favoriteApps, forKey: "favoriteApps")
            touched = true
        }
        if touched { WidgetCenter.shared.reloadAllTimelines() }
    }
}

// MARK: - App Button Row

struct AppButton: View {
    let bundleID: String
    let appName: String

    @Binding var recentApps: [String]
    @Binding var favoriteApps: [String]
    @Binding var appIcons: [String: UIImage]

    @AppStorage("loadAppIconsOnJIT") private var loadAppIconsOnJIT = true
    @AppStorage("enableAdvancedOptions") private var enableAdvancedOptions = false

    var onSelectApp: (String) -> Void
    let sharedDefaults: UserDefaults
    let performanceMode: Bool

    @State private var showScriptPicker = false

    var body: some View {
        Button(action: selectApp) {
            HStack(spacing: loadAppIconsOnJIT ? 16 : 12) {
                iconView

                VStack(alignment: .leading, spacing: 3) {
                    Text(appName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(bundleID)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                Spacer()

                if favoriteApps.contains(bundleID) {
                    Image(systemName: "star.fill")
                        .imageScale(.medium)
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, loadAppIconsOnJIT ? 8 : 12)
            .padding(.horizontal, 12)
            .background(rowBackground)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: toggleFavorite) {
                Label(
                    favoriteApps.contains(bundleID) ? "Remove Favorite" : "Add to Favorites",
                    systemImage: favoriteApps.contains(bundleID) ? "star.slash" : "star"
                )
                .disabled(!favoriteApps.contains(bundleID) && favoriteApps.count >= 4)
            }
            Button {
                UIPasteboard.general.string = bundleID
                Haptics.light()
            } label: {
                Label("Copy Bundle ID", systemImage: "doc.on.doc")
            }
            if enableAdvancedOptions {
                Button { showScriptPicker = true } label: {
                    Label("Assign Script", systemImage: "chevron.left.slash.chevron.right")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                toggleFavorite()
            } label: {
                Label(favoriteApps.contains(bundleID) ? "Unfavorite" : "Favorite", systemImage: "star")
            }
            .tint(.yellow)

            Button {
                UIPasteboard.general.string = bundleID
                Haptics.light()
            } label: {
                Label("Copy ID", systemImage: "doc.on.doc")
            }
        }
        .sheet(isPresented: $showScriptPicker) {
            ScriptListView { url in
                assignScript(url)
                showScriptPicker = false
            }
        }
        .onAppear {
            if loadAppIconsOnJIT {
                loadAppIcon(for: bundleID)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(appName)")
        .accessibilityHint("Double-tap to select. Swipe for actions, long-press for options.")
    }

    // MARK: Icon

    private var iconView: some View {
        Group {
            if loadAppIconsOnJIT, let image = appIcons[bundleID] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1.5)
                    .transition(.opacity.combined(with: .scale))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(UIColor.systemGray5))
                    .frame(width: 54, height: 54)
                    .overlay(
                        Image(systemName: "app")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(.gray)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Row Background

    private var rowBackground: some View {
        Group {
            if performanceMode {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground).opacity(0.65))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
            }
        }
    }

    // MARK: Actions

    private func selectApp() {
        Haptics.selection()
        recentApps.removeAll { $0 == bundleID }
        recentApps.insert(bundleID, at: 0)
        if recentApps.count > 3 {
            recentApps = Array(recentApps.prefix(3))
        }
        persistIfChanged()
        onSelectApp(bundleID)
    }

    private func toggleFavorite() {
        Haptics.light()
        if favoriteApps.contains(bundleID) {
            favoriteApps.removeAll { $0 == bundleID }
        } else if favoriteApps.count < 4 {
            favoriteApps.insert(bundleID, at: 0)
            recentApps.removeAll { $0 == bundleID }
        }
        persistIfChanged()
    }

    private func assignScript(_ url: URL?) {
        var mapping = UserDefaults.standard.dictionary(forKey: "BundleScriptMap") as? [String: String] ?? [:]
        if let url {
            mapping[bundleID] = url.lastPathComponent
        } else {
            mapping.removeValue(forKey: bundleID)
        }
        UserDefaults.standard.set(mapping, forKey: "BundleScriptMap")
        Haptics.light()
    }

    private func persistIfChanged() {
        var touched = false
        let prevR = (sharedDefaults.array(forKey: "recentApps") as? [String]) ?? []
        let prevF = (sharedDefaults.array(forKey: "favoriteApps") as? [String]) ?? []

        if prevR != recentApps {
            sharedDefaults.set(recentApps, forKey: "recentApps")
            touched = true
        }
        if prevF != favoriteApps {
            sharedDefaults.set(favoriteApps, forKey: "favoriteApps")
            touched = true
        }
        if touched { WidgetCenter.shared.reloadAllTimelines() }
    }

    private func loadAppIcon(for bundleID: String) {
        guard loadAppIconsOnJIT else { return }
        if let mem = IconCache.shared.cached(bundleID) {
            appIcons[bundleID] = mem
            return
        }
        if let disk = loadCachedIcon(bundleID: bundleID) {
            IconCache.shared.store(disk, for: bundleID)
            appIcons[bundleID] = disk
            return
        }
        IconCache.shared.enqueue { [bundleID] in
            AppStoreIconFetcher.getIcon(for: bundleID) { image in
                guard let image else { return }
                IconCache.shared.store(image, for: bundleID)
                DispatchQueue.main.async {
                    withAnimation(.linear(duration: 0.12)) {
                        appIcons[bundleID] = image
                    }
                    saveIconToGroup(image, bundleID: bundleID)
                }
            }
        }
    }

    private func loadCachedIcon(bundleID: String) -> UIImage? {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.stik.sj") else {
            return nil
        }
        let iconsDir = containerURL.appendingPathComponent("icons", isDirectory: true)
        let fileURL = iconsDir.appendingPathComponent("\(bundleID).png")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return UIImage(contentsOfFile: fileURL.path)
        }
        return nil
    }
}

// MARK: - IconCache

final class IconCache {
    static let shared = IconCache()
    private let mem = NSCache<NSString, UIImage>()
    private let queue = OperationQueue()
    private init() {
        queue.maxConcurrentOperationCount = 4
        mem.countLimit = 1000
        mem.totalCostLimit = 64 * 1024 * 1024
    }
    func cached(_ key: String) -> UIImage? { mem.object(forKey: key as NSString) }
    func store(_ image: UIImage, for key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale)
        mem.setObject(image, forKey: key as NSString, cost: cost)
    }
    func enqueue(_ op: @escaping () -> Void) { queue.addOperation(op) }
}

// MARK: - Shared UI Bits

private struct BackgroundGradient: View {
    var body: some View {
        LinearGradient(
            colors: [Color(UIColor.systemBackground), Color(UIColor.secondarySystemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 20
    var material: Material = .ultraThinMaterial
    var strokeOpacity: Double = 0.15
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(.white.opacity(strokeOpacity), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    }
}

private extension View {
    func glassCard(
        cornerRadius: CGFloat = 20,
        material: Material = .ultraThinMaterial,
        strokeOpacity: Double = 0.15
    ) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, material: material, strokeOpacity: strokeOpacity))
    }
}

fileprivate func saveIconToGroup(_ image: UIImage, bundleID: String) {
    guard let data = image.pngData(),
          let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.stik.sj")
    else { return }
    let iconsDir = container.appendingPathComponent("icons", isDirectory: true)
    try? FileManager.default.createDirectory(at: iconsDir, withIntermediateDirectories: true)
    let fileURL = iconsDir.appendingPathComponent("\(bundleID).png")
    try? data.write(to: fileURL)
}

enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - Utilities

extension Array: @retroactive RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Element].self, from: data)
        else { return nil }
        self = result
    }
    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else { return "[]" }
        return result
    }
}

// MARK: - Preview

#Preview {
    InstalledAppsListView { _ in }
        .environment(\.colorScheme, .dark)
}

class InstalledAppsViewModel: ObservableObject {
    @Published var apps: [String: String] = [:]
    init() { loadApps() }
    func loadApps() {
        do { self.apps = try JITEnableContext.shared.getAppList() }
        catch { print(error); self.apps = [:] }
    }
}
