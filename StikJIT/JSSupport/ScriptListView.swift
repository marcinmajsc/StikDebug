//
//  ScriptListView.swift
//  StikDebug
//
//  Created by s s on 2025/7/4.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ScriptListView: View {
    @State private var scripts: [URL] = []
    @State private var showNewFileAlert = false
    @State private var newFileName = ""
    @State private var showImporter = false
    @AppStorage("DefaultScriptName") private var defaultScriptName = "attachDetach.js"

    @State private var isBusy = false
    @State private var alertVisible = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var alertIsSuccess = false
    @State private var justCopied = false
    @State private var searchText = ""

    @State private var showDeleteConfirmation = false
    @State private var pendingDelete: URL? = nil

    var onSelectScript: ((URL?) -> Void)? = nil

    private var isPickerMode: Bool { onSelectScript != nil }

    private var filteredScripts: [URL] {
        guard !searchText.isEmpty else { return scripts }
        return scripts.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(searchText) }
    }
    
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    private var currentTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .system }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(style: currentTheme.backgroundStyle)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        headerCard

                        if filteredScripts.isEmpty {
                            emptyCard
                        } else {
                            ForEach(filteredScripts, id: \.self) { script in
                                scriptRow(script)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 30)
                }

                if isBusy {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView(NSLocalizedString("Working…", comment: ""))
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

                if alertVisible {
                    CustomErrorView(title: alertTitle,
                                    message: alertMessage,
                                    onDismiss: { alertVisible = false },
                                    messageType: alertIsSuccess ? .success : .error)
                }

                if justCopied {
                    VStack {
                        Spacer()
                        Text(NSLocalizedString("Copied", comment: ""))
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 3)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 30)
                    }
                    .animation(.easeInOut(duration: 0.25), value: justCopied)
                }
            }
            .navigationTitle(isPickerMode ? NSLocalizedString("Choose Script", comment: "") : NSLocalizedString("Scripts", comment: ""))
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !isPickerMode {
                        Button { showNewFileAlert = true } label: {
                            Label(NSLocalizedString("New", comment: ""), systemImage: "doc.badge.plus")
                        }
                        Button { showImporter = true } label: {
                            Label(NSLocalizedString("Import", comment: ""), systemImage: "tray.and.arrow.down")
                        }
                    }
                }
            }
            .onAppear(perform: loadScripts)
            .alert(NSLocalizedString("New Script", comment: ""), isPresented: $showNewFileAlert) {
                TextField(NSLocalizedString("Filename", comment: ""), text: $newFileName)
                Button(NSLocalizedString("Create", comment: ""), action: createNewScript)
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { }
            }
            .alert(NSLocalizedString("Delete Script?", comment: ""), isPresented: $showDeleteConfirmation, presenting: pendingDelete) { script in
                Button(NSLocalizedString("Delete", comment: ""), role: .destructive) { deleteScript(script) }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { pendingDelete = nil }
            } message: { script in
                Text(String(format: NSLocalizedString("Are you sure you want to delete %@? This cannot be undone.", comment: "Confirm file delete"), script.lastPathComponent))
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType(filenameExtension: "js") ?? .plainText]
            ) { result in
                switch result {
                case .success(let fileURL): importScript(from: fileURL)
                case .failure(let error): presentError(title: NSLocalizedString("Import Failed", comment: ""), message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        VStack(spacing: 12) {
            TextField(NSLocalizedString("Search scripts…", comment: ""), text: $searchText)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            HStack(spacing: 12) {
                if isPickerMode {
                    WideGlassyButton(title: NSLocalizedString("None", comment: ""), systemImage: "nosign") {
                        onSelectScript?(nil)
                    }
                    WideGlassyButton(title: NSLocalizedString("Import", comment: ""), systemImage: "tray.and.arrow.down") {
                        showImporter = true
                    }
                } else {
                    WideGlassyButton(title: NSLocalizedString("New", comment: ""), systemImage: "doc.badge.plus") {
                        showNewFileAlert = true
                    }
                    WideGlassyButton(title: NSLocalizedString("Import", comment: ""), systemImage: "tray.and.arrow.down") {
                        showImporter = true
                    }
                }
            }
        }
        .padding(20)
        .background(glassyBackground)
    }

    @ViewBuilder
    private func scriptRow(_ script: URL) -> some View {
        if isPickerMode {
            Button {
                onSelectScript?(script)
            } label: {
                scriptCard(script, showDefaultStar: true, showDelete: false)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                ScriptEditorView(scriptURL: script)
            } label: {
                scriptCard(script, showDefaultStar: true, showDelete: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func scriptCard(_ script: URL, showDefaultStar: Bool, showDelete: Bool) -> some View {
        let isDefault = defaultScriptName == script.lastPathComponent

        return HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .foregroundColor(.blue)
                .imageScale(.large)

            Text(script.lastPathComponent)
                .font(.body.weight(.medium))
                .lineLimit(1)

            Spacer()

            if showDefaultStar, isDefault {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
            }

            if showDelete {
                Button(role: .destructive) {
                    pendingDelete = script
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(20)
        .background(glassyBackground)
        .contextMenu {
            Button { copyName(script) } label: {
                Label(NSLocalizedString("Copy Filename", comment: ""), systemImage: "doc.on.doc")
            }
            Button { copyPath(script) } label: {
                Label(NSLocalizedString("Copy Path", comment: ""), systemImage: "folder")
            }
            if !isPickerMode {
                Button { saveDefaultScript(script) } label: {
                    Label(NSLocalizedString("Set Default", comment: ""), systemImage: "star")
                }
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Label(isPickerMode ? NSLocalizedString("No scripts available", comment: "") : NSLocalizedString("No scripts found", comment: ""),
                  systemImage: "doc.text.magnifyingglass")
                .font(.subheadline.weight(.semibold))
            Text(isPickerMode ? NSLocalizedString("Import a file or choose None.", comment: "") : NSLocalizedString("Tap New or Import to get started.", comment: ""))
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(glassyBackground)
    }

    private var glassyBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    }

    // MARK: - File Ops

    private func scriptsDirectory() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scripts")
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
        do {
            if exists && !isDir.boolValue {
                try FileManager.default.removeItem(at: dir)
            }
            if !exists || !isDir.boolValue {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                if let bundleURL = Bundle.main.url(forResource: "attachDetach", withExtension: "js") {
                    let dest = dir.appendingPathComponent("attachDetach.js")
                    if !FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.copyItem(at: bundleURL, to: dest)
                    }
                }
            }
        } catch {
            presentError(title: NSLocalizedString("Unable to Create Scripts Folder", comment: ""), message: error.localizedDescription)
        }
        return dir
    }

    private func loadScripts() {
        let dir = scriptsDirectory()
        scripts = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "js" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending } ?? []
    }

    private func saveDefaultScript(_ url: URL) {
        defaultScriptName = url.lastPathComponent
        presentSuccess(title: NSLocalizedString("Default Script Set", comment: ""), message: url.lastPathComponent)
    }

    private func createNewScript() {
        guard !newFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var filename = newFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !filename.hasSuffix(".js") { filename += ".js" }
        let newURL = scriptsDirectory().appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            presentError(title: NSLocalizedString("Failed to Create New Script", comment: ""), message: NSLocalizedString("A script with the same name already exists.", comment: ""))
            return
        }
        do {
            try "".write(to: newURL, atomically: true, encoding: .utf8)
            newFileName = ""
            loadScripts()
            presentSuccess(title: NSLocalizedString("Created", comment: ""), message: filename)
        } catch {
            presentError(title: NSLocalizedString("Error Creating File", comment: ""), message: error.localizedDescription)
        }
    }

    private func deleteScript(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            if url.lastPathComponent == defaultScriptName {
                UserDefaults.standard.removeObject(forKey: "DefaultScriptName")
            }
            loadScripts()
        } catch {
            presentError(title: NSLocalizedString("Delete Failed", comment: ""), message: error.localizedDescription)
        }
    }

    private func importScript(from fileURL: URL) {
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            defer { DispatchQueue.main.async { self.isBusy = false } }
            do {
                let dest = self.scriptsDirectory().appendingPathComponent(fileURL.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: fileURL, to: dest)
                DispatchQueue.main.async {
                    self.loadScripts()
                    self.presentSuccess(title: NSLocalizedString("Imported", comment: ""), message: fileURL.lastPathComponent)
                }
            } catch {
                DispatchQueue.main.async {
                    self.presentError(title: NSLocalizedString("Import Failed", comment: ""), message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Feedback helpers

    private func presentError(title: String, message: String) {
        alertTitle = title; alertMessage = message
        alertIsSuccess = false; alertVisible = true
    }

    private func presentSuccess(title: String, message: String) {
        alertTitle = title; alertMessage = message
        alertIsSuccess = true; alertVisible = true
    }

    private func copyName(_ url: URL) {
        UIPasteboard.general.string = url.lastPathComponent
        showCopiedToast()
    }

    private func copyPath(_ url: URL) {
        UIPasteboard.general.string = url.path
        showCopiedToast()
    }

    private func showCopiedToast() {
        withAnimation { justCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { justCopied = false }
        }
    }
}

// MARK: - Equal-width rounded-rectangle button (centered content)
private struct WideGlassyButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .imageScale(.medium)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 14)
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .buttonStyle(.plain)
    }
}
