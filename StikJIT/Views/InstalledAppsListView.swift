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
    @State private var selectedTab: AppListTab = .debuggable
    @State private var launchingBundles: Set<String> = []
    @State private var launchFeedback: LaunchFeedback? = nil
    @State private var otherSearchText: String = ""

    @Environment(\.dismiss) private var dismiss
    var onSelectApp: (String) -> Void

    private var filteredRecents: [String] {
        recentApps.filter { viewModel.debuggableApps[$0] != nil && !favoriteApps.contains($0) }
    }

    private enum AppListTab: String, CaseIterable, Identifiable {
        case debuggable
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .debuggable: return "Debuggable"
            case .other: return "Other"
            }
        }
    }

    private struct LaunchFeedback: Identifiable {
        let id = UUID()
        let message: String
        let success: Bool
    }

    private var sortedOtherApps: [(key: String, value: String)] {
        viewModel.nonDebuggableApps.sorted { lhs, rhs in
            let comparison = lhs.value.localizedCaseInsensitiveCompare(rhs.value)
            if comparison == .orderedSame {
                return lhs.key < rhs.key
            }
            return comparison == .orderedAscending
        }
    }

    private var otherSearchIsActive: Bool {
        !otherSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredOtherApps: [(key: String, value: String)] {
        let base = sortedOtherApps
        guard otherSearchIsActive else { return base }
        let query = otherSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        return base.filter {
            let identifier = $0.key
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
            let name = $0.value
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
            return identifier.contains(query) || name.contains(query)
        }
    }

    private func isEmpty(for tab: AppListTab) -> Bool {
        switch tab {
        case .debuggable:
            return viewModel.debuggableApps.isEmpty
        case .other:
            return filteredOtherApps.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView("Loading Apps…".localized)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(.white.opacity(0.15), lineWidth: 1)
                                )
                        )
                        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
                        .transition(.opacity.combined(with: .scale))
                } else {
                    tabbedContent
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

                if let feedback = launchFeedback {
                    VStack {
                        Spacer()
                        Text(feedback.message)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Capsule()
                                            .stroke(feedback.success ? Color.green.opacity(0.35) : Color.red.opacity(0.35), lineWidth: 1)
                                    )
                            )
                            .foregroundStyle(feedback.success ? .green : .red)
                            .shadow(radius: 4)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 40)
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: launchFeedback?.id)
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

    private func emptyState(for tab: AppListTab) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundStyle(.secondary)

            switch tab {
            case .debuggable:
                Text("No Debuggable App Found".localized)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("""
                StikDebug can only connect to apps with the “get-task-allow” entitlement.
                Please check if the app you want to connect to is signed with a development certificate.
                """.localized)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            case .other:
                Text("Nothing To Show".localized)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("""
                Once your device pairing file is imported and CoreDevice is connected, every installed app will appear here for quick access.
                """.localized)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            }
        }
        .padding(24)
        .glassCard(cornerRadius: 24, material: .thinMaterial, strokeOpacity: 0.12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Empty list. Import pairing file or sign app appropriately.".localized)
    }

    // MARK: Apps List

    private var debuggableSections: some View {
        VStack(spacing: 18) {
            if !favoriteApps.isEmpty {
                glassSection(
                    title: String(format: "Favorites (%d/4)".localized, favoriteApps.count)
                ) {
                    LazyVStack(spacing: 12) {
                        ForEach(favoriteApps, id: \.self) { bundleID in
                            AppButton(
                                bundleID: bundleID,
                                appName: viewModel.debuggableApps[bundleID] ?? bundleID,
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
                                appName: viewModel.debuggableApps[bundleID] ?? bundleID,
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
                    ForEach(viewModel.debuggableApps.sorted(by: { $0.key < $1.key }), id: \.key) { bundleID, appName in
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
    }

    private func otherSections(apps: [(key: String, value: String)]) -> some View {
        VStack(spacing: 18) {
            glassSection(title: "How It Works".localized) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Launch apps without get-task-allow by tunneling through CoreDevice. This only starts the app; attach debugging from Recents once it exposes get-task-allow.".localized)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            glassSection(title: "All Installed Apps".localized) {
                LazyVStack(spacing: 12) {
                    ForEach(apps, id: \.key) { bundleID, appName in
                        LaunchAppRow(
                            bundleID: bundleID,
                            appName: appName,
                            isLaunching: launchingBundles.contains(bundleID),
                            appIcons: $appIcons,
                            performanceMode: performanceMode
                        ) {
                            startLaunching(bundleID: bundleID)
                        }
                    }
                }
            }
        }
    }

    private var tabbedContent: some View {
        TabView(selection: $selectedTab) {
            tabContent(for: .debuggable)
                .tag(AppListTab.debuggable)
                .tabItem { Text(AppListTab.debuggable.title.localized) }

            tabContent(for: .other)
                .tag(AppListTab.other)
                .tabItem { Text(AppListTab.other.title.localized) }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppListTab) -> some View {
        switch tab {
        case .debuggable:
            if isEmpty(for: .debuggable) {
                VStack {
                    Spacer(minLength: 0)
                    emptyState(for: .debuggable)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .transition(.opacity.combined(with: .scale))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        if let error = viewModel.lastError {
                            errorBanner(error)
                        }

                        debuggableSections
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
        case .other:
            otherTabContent(apps: filteredOtherApps)
        }
    }

    private func otherTabContent(apps: [(key: String, value: String)]) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                searchBar

                if let error = viewModel.lastError {
                    errorBanner(error)
                }

                if apps.isEmpty {
                    if otherSearchIsActive {
                        otherSearchEmptyState
                            .transition(.opacity.combined(with: .scale))
                    } else {
                        emptyState(for: .other)
                            .transition(.opacity.combined(with: .scale))
                    }
                } else {
                    otherSections(apps: apps)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    private var otherSearchEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)

            Text("No matches".localized)
                .font(.title3.weight(.semibold))

            Text("Try another name or bundle identifier.".localized)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .glassCard(cornerRadius: 20, material: .thinMaterial, strokeOpacity: 0.12)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search".localized, text: $otherSearchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            if !otherSearchText.isEmpty {
                Button {
                    otherSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search".localized)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
            )
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

    private func startLaunching(bundleID: String) {
        guard !launchingBundles.contains(bundleID) else { return }
        launchingBundles.insert(bundleID)
        Haptics.selection()

        viewModel.launchWithoutDebug(bundleID: bundleID) { success in
            launchingBundles.remove(bundleID)

            let message = success ? "Launch request sent".localized : "Launch failed".localized
            let feedback = LaunchFeedback(message: message, success: success)

            if success {
                Haptics.light()
            }

            withAnimation {
                launchFeedback = feedback
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if launchFeedback?.id == feedback.id {
                    withAnimation {
                        launchFeedback = nil
                    }
                }
            }
        }
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
        IconCache.shared.fetchIcon(for: bundleID) { image in
            guard let image else { return }
            let shouldAnimate = appIcons[bundleID] == nil
            if shouldAnimate {
                withAnimation(.linear(duration: 0.12)) {
                    appIcons[bundleID] = image
                }
            } else {
                appIcons[bundleID] = image
            }
        }
    }
}

// MARK: - IconCache

struct LaunchAppRow: View {
    let bundleID: String
    let appName: String
    let isLaunching: Bool

    @Binding var appIcons: [String: UIImage]

    @AppStorage("loadAppIconsOnJIT") private var loadAppIconsOnJIT = true

    let performanceMode: Bool
    var launchAction: () -> Void

    var body: some View {
        Button {
            guard !isLaunching else { return }
            launchAction()
        } label: {
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

                if isLaunching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Launch".localized)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.18))
                        )
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, loadAppIconsOnJIT ? 8 : 12)
            .padding(.horizontal, 12)
            .background(rowBackground)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLaunching)
        .onAppear {
            if loadAppIconsOnJIT {
                loadAppIcon(for: bundleID)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(appName)")
        .accessibilityHint("Double-tap to launch via CoreDevice.")
    }

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

    private func loadAppIcon(for bundleID: String) {
        IconCache.shared.fetchIcon(for: bundleID) { image in
            guard let image else { return }
            let shouldAnimate = appIcons[bundleID] == nil
            if shouldAnimate {
                withAnimation(.linear(duration: 0.12)) {
                    appIcons[bundleID] = image
                }
            } else {
                appIcons[bundleID] = image
            }
        }
    }
}

final class IconCache {
    static let shared = IconCache()

    private let mem = NSCache<NSString, UIImage>()
    private let queue = OperationQueue()
    private let callbackQueue = DispatchQueue(label: "com.stik.iconcache.callbacks")
    private var pendingCallbacks: [String: [(UIImage?) -> Void]] = [:]

    private init() {
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInitiated
        mem.countLimit = 1000
        mem.totalCostLimit = 64 * 1024 * 1024
    }

    func fetchIcon(for bundleID: String, completion: @escaping (UIImage?) -> Void) {
        if let memImage = mem.object(forKey: bundleID as NSString) {
            DispatchQueue.main.async { completion(memImage) }
            return
        }

        var shouldStartLoad = false
        callbackQueue.sync {
            if var existing = pendingCallbacks[bundleID] {
                existing.append(completion)
                pendingCallbacks[bundleID] = existing
            } else {
                pendingCallbacks[bundleID] = [completion]
                shouldStartLoad = true
            }
        }

        guard shouldStartLoad else { return }

        queue.addOperation { [weak self] in
            guard let self else { return }

            var loadedFromDisk = false
            var result = self.diskCachedIcon(for: bundleID)
            if result != nil {
                loadedFromDisk = true
            }

            if result == nil {
                let semaphore = DispatchSemaphore(value: 0)
                AppStoreIconFetcher.getIcon(for: bundleID) { image in
                    result = image
                    semaphore.signal()
                }
                _ = semaphore.wait(timeout: .now() + 10)
            }

            if let image = result {
                let cost = Int(image.size.width * image.size.height * image.scale * image.scale)
                self.mem.setObject(image, forKey: bundleID as NSString, cost: cost)
                if !loadedFromDisk {
                    saveIconToGroup(image, bundleID: bundleID)
                }
            }

            let callbacks = self.callbackQueue.sync { () -> [(UIImage?) -> Void] in
                let handlers = self.pendingCallbacks[bundleID] ?? []
                self.pendingCallbacks[bundleID] = nil
                return handlers
            }

            DispatchQueue.main.async {
                callbacks.forEach { $0(result) }
            }
        }
    }

    private func diskCachedIcon(for bundleID: String) -> UIImage? {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.stik.sj")
        else { return nil }

        let iconsDir = containerURL.appendingPathComponent("icons", isDirectory: true)
        let fileURL = iconsDir.appendingPathComponent("\(bundleID).png")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return UIImage(contentsOfFile: fileURL.path)
    }
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
    @Published var debuggableApps: [String: String] = [:]
    @Published var nonDebuggableApps: [String: String] = [:]
    @Published var isLoading = false
    @Published var lastError: String? = nil

    private let workQueue = DispatchQueue(label: "com.stik.installedApps", qos: .userInitiated)

    init() { refreshAppLists() }

    func refreshAppLists() {
        isLoading = true
        lastError = nil

        workQueue.async { [weak self] in
            guard let self else { return }
            do {
                let debuggable = try JITEnableContext.shared.getAppList()
                let allApps = try JITEnableContext.shared.getAllApps()

                let nonDebuggableSequence = allApps.filter { debuggable[$0.key] == nil }
                let nonDebuggable = Dictionary(uniqueKeysWithValues: nonDebuggableSequence.map { ($0.key, $0.value) })

                DispatchQueue.main.async {
                    self.debuggableApps = debuggable
                    self.nonDebuggableApps = nonDebuggable
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.debuggableApps = [:]
                    self.nonDebuggableApps = [:]
                    self.isLoading = false
                    self.lastError = error.localizedDescription
                    print("Failed to load apps: \(error)")
                }
            }
        }
    }

    func launchWithoutDebug(bundleID: String, completion: @escaping (Bool) -> Void) {
        workQueue.async {
            let success = JITEnableContext.shared.launchAppWithoutDebug(bundleID, logger: nil)
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
}
