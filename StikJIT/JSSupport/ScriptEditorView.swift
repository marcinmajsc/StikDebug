//
//  ScriptEditorView.swift
//  StikDebug
//
//  Created by s s on 2025/7/4.
//

import SwiftUI
import CodeEditorView
import LanguageSupport

struct ScriptEditorView: View {
    let scriptURL: URL

    @State private var scriptContent: String = ""
    @State private var position: CodeEditor.Position = .init()
    @State private var messages: Set<TextLocated<Message>> = []

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            CodeEditor(
                text:     $scriptContent,
                position: $position,
                messages: $messages,
                language: .swift()
            )
            .font(.system(.footnote, design: .monospaced))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(
                \.codeEditorTheme,
                colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight
            )

            Divider()

            HStack(spacing: 12) {
                WideGlassyButton(title: "Cancel", systemImage: "xmark") {
                    dismiss()
                }
                WideGlassyButton(title: "Save", systemImage: "checkmark") {
                    saveScript()
                    dismiss()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .navigationTitle(scriptURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadScript)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadScript() {
        scriptContent = (try? String(contentsOf: scriptURL)) ?? ""
    }

    private func saveScript() {
        try? scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
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
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 10)
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
