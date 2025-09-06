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

    // Overlays / feedback
    @State private var isBusy = false
    @State private var alertVisible = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var alertIsSuccess = false
    @State private var justCopied = false

    // Search
    @State private var searchText = ""

    var onSelectScript: ((URL?) -> Void)? = nil

    private var filteredScripts: [URL] {
        guard !searchText.isEmpty else { return scripts }
        return scripts.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(UIColor.systemBackground),
                        Color(UIColor.secondarySystemBackground)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                List {
                    actionsSection

                    if let onSelectScript {
                        Section {
                            Button {
                                onSelectScript(nil)
                            } label: {
                                HStack {
                                    Image(systemName: "nosign")
                                        .foregroundStyle(.secondary)
                                    Text("None")
                                }
                            }
                        }
                    }

                    Section {
                        if filteredScripts.isEmpty {
                            emptyRow
                        } else {
                            ForEach(filteredScripts, id: \.self) { script in
                                scriptRow(script)
                            }
                        }
                    } footer: {
                        Text("Swipe left on a script to set it as default or delete it. Enable script execution after connecting in settings.")
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("JavaScript Files")
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search scripts")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showNewFileAlert = true
                        } label: {
                            Label("New Script", systemImage: "plus")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showImporter = true
                        } label: {
                            Label("Import", systemImage: "tray.and.arrow.down")
                        }
                    }
                }
                .onAppear(perform: loadScripts)
                .alert("New Script", isPresented: $showNewFileAlert) {
                    TextField("Filename", text: $newFileName)
                    Button("Create", action: createNewScript)
                    Button("Cancel", role: .cancel) { }
                }
                .fileImporter(
                    isPresented: $showImporter,
                    allowedContentTypes: [UTType(filenameExtension: "js") ?? .plainText],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        if let fileURL = urls.first {
                            importScript(from: fileURL)
                        }
                    case .failure(let error):
                        presentError(title: "File Import Error", message: error.localizedDescription)
                    }
                }

                // Busy overlay
                if isBusy {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Working…")
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                // Custom alert overlay
                if alertVisible {
                    CustomErrorView(
                        title: alertTitle,
                        message: alertMessage,
                        onDismiss: { alertVisible = false },
                        showButton: true,
                        primaryButtonText: "OK",
                        messageType: alertIsSuccess ? .success : .error
                    )
                }

                // Toast
                if justCopied {
                    VStack {
                        Spacer()
                        Text("Copied")
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
        }
    }

    // MARK: - Sections

    private var actionsSection: some View {
        Section {
            Button {
                showNewFileAlert = true
            } label: {
                Label("New Script", systemImage: "doc.badge.plus")
            }
            Button {
                showImporter = true
            } label: {
                Label("Import", systemImage: "tray.and.arrow.down")
            }
        }
    }

    private var emptyRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("No scripts found")
                    .font(.subheadline.weight(.semibold))
                Text("Tap New Script or Import to get started.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func scriptRow(_ script: URL) -> some View {
        let isDefault = defaultScriptName == script.lastPathComponent

        return Group {
            if let onSelectScript {
                Button {
                    onSelectScript(script)
                } label: {
                    HStack {
                        Text(script.lastPathComponent)
                        Spacer()
                        if isDefault {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                        }
                    }
                }
                .contextMenu {
                    Button {
                        copyName(script)
                    } label: {
                        Label("Copy Filename", systemImage: "doc.on.doc")
                    }
                }
            } else {
                NavigationLink {
                    ScriptEditorView(scriptURL: script)
                } label: {
                    HStack {
                        Text(script.lastPathComponent)
                        Spacer()
                        if isDefault {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteScript(script)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        saveDefaultScript(script)
                    } label: {
                        Label("Set Default", systemImage: "star")
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    Button {
                        copyName(script)
                    } label: {
                        Label("Copy Filename", systemImage: "doc.on.doc")
                    }
                    Button {
                        copyPath(script)
                    } label: {
                        Label("Copy Path", systemImage: "folder")
                    }
                }
            }
        }
    }

    // MARK: - File Ops

    private func scriptsDirectory() -> URL {
        let dir = FileManager
            .default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scripts")

        var isDir: ObjCBool = false
        var exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)

        do {
            if exists && !isDir.boolValue {
                try FileManager.default.removeItem(at: dir)
                exists = false
            }
            if !exists {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                if let bundleURL = Bundle.main.url(forResource: "attachDetach", withExtension: "js") {
                    let dest = dir.appendingPathComponent("attachDetach.js")
                    if !FileManager.default.fileExists(atPath: dest.path) {
                        try FileManager.default.copyItem(at: bundleURL, to: dest)
                    }
                }
            }
        } catch {
            presentError(title: "Unable to Create Scripts Folder", message: error.localizedDescription)
        }

        return dir
    }

    private func loadScripts() {
        let dir = scriptsDirectory()
        scripts = (try? FileManager
            .default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "js" }
            .sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) ?? []
    }

    private func saveDefaultScript(_ url: URL) {
        defaultScriptName = url.lastPathComponent
        presentSuccess(title: "Default Script Set", message: url.lastPathComponent)
    }

    private func createNewScript() {
        guard !newFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var filename = newFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !filename.hasSuffix(".js") {
            filename += ".js"
        }
        let newURL = scriptsDirectory().appendingPathComponent(filename)

        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            presentError(title: "Failed to Create New Script",
                         message: "A script with the same name already exists.")
            return
        }

        do {
            try "".write(to: newURL, atomically: true, encoding: .utf8)
            newFileName = ""
            loadScripts()
            presentSuccess(title: "Created", message: filename)
        } catch {
            presentError(title: "Error Creating File", message: error.localizedDescription)
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
            presentError(title: "Delete Failed", message: error.localizedDescription)
        }
    }

    private func importScript(from fileURL: URL) {
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                DispatchQueue.main.async { self.isBusy = false }
            }
            do {
                let dest = scriptsDirectory().appendingPathComponent(fileURL.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: fileURL, to: dest)
                DispatchQueue.main.async {
                    self.loadScripts()
                    self.presentSuccess(title: "Imported", message: fileURL.lastPathComponent)
                }
            } catch {
                DispatchQueue.main.async {
                    self.presentError(title: "Import Failed", message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Feedback helpers

    private func presentError(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        alertIsSuccess = false
        alertVisible = true
    }

    private func presentSuccess(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        alertIsSuccess = true
        alertVisible = true
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
