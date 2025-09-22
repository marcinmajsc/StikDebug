//
//  ConsoleLogsView.swift
//  StikJIT
//
//  Created by neoarz on 3/29/25.
//

import SwiftUI
import UIKit

struct ConsoleLogsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accentColor) private var environmentAccentColor
    @StateObject private var logManager = LogManager.shared
    @StateObject private var systemLogStream = SystemLogStream()
    @State private var selectedTab: ConsoleLogsTab = .jit
    @State private var jitScrollView: ScrollViewProxy? = nil
    @State private var systemScrollView: ScrollViewProxy? = nil
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    
    @State private var showingCustomAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @State private var isError = false
    
    @State private var logCheckTimer: Timer? = nil
    
    @State private var isViewActive = false
    @State private var lastProcessedLineCount = 0
    @State private var isLoadingLogs = false
    @State private var jitIsAtBottom = true
    @State private var systemIsAtBottom = true
    @State private var systemFilterText: String = ""
    @State private var systemFilterLevel: SystemLogFilterLevel = .all
    
    private var accentColor: Color {
        if customAccentColorHex.isEmpty {
            return .blue
        } else {
            return Color(hex: customAccentColorHex) ?? .blue
        }
    }

    private let systemSpeedOptions: [(title: String, interval: TimeInterval)] = [
        ("Real-time", 0),
        ("0.25s", 0.25),
        ("0.5s", 0.5),
        ("1s", 1),
        ("2s", 2)
    ]

    private enum ConsoleLogsTab: Int, CaseIterable, Identifiable {
        case jit
        case system

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .jit: return "App Logs"
            case .system: return "System Logs"
            }
        }
    }

    private enum SystemLogFilterLevel: String, CaseIterable, Identifiable {
        case all
        case warnings
        case errors

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .warnings: return "Warnings"
            case .errors: return "Errors"
            }
        }

        func matches(_ line: String) -> Bool {
            let lower = line.lowercased()
            switch self {
            case .all:
                return true
            case .warnings:
                return lower.contains("warn") || lower.contains("warning")
            case .errors:
                return lower.contains("err") || lower.contains("fail") || lower.contains("fault") || lower.contains("critical")
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .white)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    tabPicker
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    Divider()
                        .background(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.15))

                    if selectedTab == .jit {
                        jitLogsPane
                    } else {
                        systemLogsPane
                    }

                    Spacer(minLength: 0)

                    if selectedTab == .jit {
                        jitFooter
                    } else {
                        systemFooter
                    }
                }
                .onChange(of: selectedTab) { tab in
                    if tab == .system {
                        systemLogStream.start()
                    } else {
                        systemLogStream.stop()
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Console Logs")
                            .font(.headline)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { dismiss() }) {
                            HStack(spacing: 2) {
                                Text("Exit")
                                    .fontWeight(.regular)
                            }
                            .foregroundColor(accentColor)
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack {
                            Button(action: {
                                Task { await loadIdeviceLogsAsync() }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(accentColor)
                            }
                            
                            Button(action: {
                                logManager.clearLogs()
                            }) {
                                Text("Clear")
                                    .foregroundColor(accentColor)
                            }
                        }
                    }
                }
            }
            .overlay(
                Group {
                    if showingCustomAlert {
                        Color.black.opacity(0.4)
                            .edgesIgnoringSafeArea(.all)
                            .overlay(
                                CustomErrorView(
                                    title: alertTitle,
                                    message: alertMessage,
                                    onDismiss: {
                                        showingCustomAlert = false
                                    },
                                    showButton: true,
                                    primaryButtonText: "OK",
                                    messageType: isError ? .error : .success
                                )
                            )
                    }
                }
            )
            .onDisappear {
                systemLogStream.stop()
            }
            .onAppear {
                if selectedTab == .system {
                    systemLogStream.start()
                }
            }
        }
    }
    
    private var tabPicker: some View {
        Picker("Log Source".localized, selection: $selectedTab) {
            ForEach(ConsoleLogsTab.allCases) { tab in
                Text(tab.title.localized).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var jitLogsPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("=== DEVICE INFORMATION ===")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.vertical, 4)

                        Text("iOS Version: \(UIDevice.current.systemVersion)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text("Device: \(UIDevice.current.name)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text("Model: \(UIDevice.current.model)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text("=== LOG ENTRIES ===")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.vertical, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                    ForEach(logManager.logs) { logEntry in
                        Text(AttributedString(createLogAttributedString(logEntry)))
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 1)
                            .padding(.horizontal, 4)
                            .id(logEntry.id)
                    }
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("jitScroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "jitScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                jitIsAtBottom = offset > -20
            }
            .onChange(of: logManager.logs.count) { _ in
                guard jitIsAtBottom, let lastLog = logManager.logs.last else { return }
                withAnimation {
                    proxy.scrollTo(lastLog.id, anchor: .bottom)
                }
            }
            .onAppear {
                jitScrollView = proxy
                isViewActive = true
                Task { await loadIdeviceLogsAsync() }
                startLogCheckTimer()
            }
            .onDisappear {
                isViewActive = false
                stopLogCheckTimer()
            }
        }
        .onDisappear {
            systemLogStream.stop()
        }
    }

    private var systemLogsPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    systemFilterControls

                    if let error = systemLogStream.lastError {
                        Text(error)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.red)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 4)
                    }

                    ForEach(filteredSystemLogs) { entry in
                        Text(AttributedString(systemLogAttributedString(entry)))
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 1)
                            .padding(.horizontal, 4)
                            .id(entry.id)
                    }
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("systemScroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "systemScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                systemIsAtBottom = offset > -20
            }
            .onChange(of: systemLogStream.entries.count) { _ in
                guard systemIsAtBottom, let last = systemLogStream.entries.last else { return }
                withAnimation {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onAppear {
                systemScrollView = proxy
                systemLogStream.start()
            }
            .onDisappear {
                systemScrollView = nil
            }
        }
    }

    private var filteredSystemLogs: [SystemLogStream.Entry] {
        var entries = systemLogStream.entries
        let trimmed = systemFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let query = trimmed.lowercased()
            entries = entries.filter { entry in
                entry.raw.lowercased().contains(query)
            }
        }

        if systemFilterLevel != .all {
            entries = entries.filter { systemFilterLevel.matches($0.raw) }
        }

        return entries
    }

    private var systemSpeedSymbol: String {
        switch systemLogStream.updateInterval {
        case 0:
            return "hare.fill"
        case ..<0.5:
            return "tortoise.fill"
        case ..<1.5:
            return "tortoise"
        default:
            return "tortoise"
        }
    }

    private var systemFilterControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)

                TextField("Filter".localized, text: $systemFilterText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(.system(size: 12, design: .monospaced))

                if !systemFilterText.isEmpty {
                    Button {
                        systemFilterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear filter".localized)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )

            Picker("Severity".localized, selection: $systemFilterLevel) {
                ForEach(SystemLogFilterLevel.allCases) { level in
                    Text(level.title.localized).tag(level)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    private var jitFooter: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .imageScale(.small)
                    .foregroundColor(.red)
                Text("\(logManager.errorCount) Errors")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)

            Button {
                var logsContent = "=== DEVICE INFORMATION ===\n"
                logsContent += "Version: \(UIDevice.current.systemVersion)\n"
                logsContent += "Name: \(UIDevice.current.name)\n"
                logsContent += "Model: \(UIDevice.current.model)\n"
                logsContent += "StikJIT Version: App Version: 1.0\n\n"
                logsContent += "=== LOG ENTRIES ===\n"

                logsContent += logManager.logs.map {
                    "[\(formatTime(date: $0.timestamp))] [\($0.type.rawValue)] \($0.message)"
                }.joined(separator: "\n")

                UIPasteboard.general.string = logsContent

                alertTitle = "Logs Copied"
                alertMessage = "Logs have been copied to clipboard."
                isError = false
                showingCustomAlert = true
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(accentColor)
            }
            .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
            .accessibilityLabel("Copy app logs")

            exportControl
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var systemFooter: some View {
        HStack(spacing: 12) {
            if let error = systemLogStream.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .lineLimit(2)
            } else {
                let status = systemStatusDisplay()
                Label(status.text, systemImage: status.icon)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                UIPasteboard.general.string = systemLogStream.concatenatedLog()
                alertTitle = "System Logs Copied"
                alertMessage = "Recent system logs copied to clipboard.".localized
                isError = false
                showingCustomAlert = true
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(accentColor)
            }
            .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
            .accessibilityLabel("Copy system logs")

            Button {
                systemLogStream.clear()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(accentColor)
            }
            .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
            .accessibilityLabel("Clear system logs")

            Button {
                systemLogStream.togglePause()
            } label: {
                Image(systemName: systemLogStream.isPaused ? "play.fill" : "pause.fill")
                    .foregroundColor(accentColor)
            }
            .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
            .accessibilityLabel(systemLogStream.isPaused ? "Resume stream" : "Pause stream")

            Menu {
                ForEach(systemSpeedOptions, id: \.title) { option in
                    Button(option.title.localized) {
                        systemLogStream.updateInterval = option.interval
                    }
                }
            } label: {
                Image(systemName: systemSpeedSymbol)
                    .foregroundColor(accentColor)
            }
            .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
            .accessibilityLabel("Adjust speed")

            if !systemLogStream.isStreaming {
                Button {
                    systemLogStream.start()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(accentColor)
                }
                .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
                .accessibilityLabel("Restart stream")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var exportControl: some View {
        let logURL: URL = URL.documentsDirectory.appendingPathComponent("idevice_log.txt")
        if FileManager.default.fileExists(atPath: logURL.path) {
            ShareLink(
                item: logURL,
                preview: SharePreview("idevice_log.txt", image: Image(systemName: "doc.text"))
            ) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(accentColor)
            }
            .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
            .accessibilityLabel("Export app logs")
        } else {
            Button {
                alertTitle = "Export Failed"
                alertMessage = "No idevice logs found"
                isError = true
                showingCustomAlert = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(accentColor)
            }
            .buttonStyle(GlassOvalButtonStyle(height: 36, strokeOpacity: 0.18))
            .accessibilityLabel("Export app logs")
        }
    }
    
    private func createLogAttributedString(_ logEntry: LogManager.LogEntry) -> NSAttributedString {
        let fullString = NSMutableAttributedString()
        
        let timestampString = "[\(formatTime(date: logEntry.timestamp))]"
        let timestampAttr = NSAttributedString(
            string: timestampString,
            attributes: [.foregroundColor: colorScheme == .dark ? UIColor.gray : UIColor.darkGray]
        )
        fullString.append(timestampAttr)
        fullString.append(NSAttributedString(string: " "))
        
        let typeString = "[\(logEntry.type.rawValue)]"
        let typeColor = UIColor(colorForLogType(logEntry.type))
        let typeAttr = NSAttributedString(
            string: typeString,
            attributes: [.foregroundColor: typeColor]
        )
        fullString.append(typeAttr)
        fullString.append(NSAttributedString(string: " "))
        
        let messageAttr = NSAttributedString(
            string: logEntry.message,
            attributes: [.foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black]
        )
        fullString.append(messageAttr)
        
        return fullString
    }

    private func systemLogAttributedString(_ entry: SystemLogStream.Entry) -> NSAttributedString {
        let fullString = NSMutableAttributedString()

        let timestamp = "[\(formatTime(date: entry.timestamp))]"
        let tsAttr = NSAttributedString(string: timestamp,
                                        attributes: [.foregroundColor: colorScheme == .dark ? UIColor.gray : UIColor.darkGray])
        fullString.append(tsAttr)
        fullString.append(NSAttributedString(string: " "))

        let type = systemLogType(for: entry.raw)
        let typeString = "[\(type.rawValue)]"
        let typeAttr = NSAttributedString(string: typeString,
                                         attributes: [.foregroundColor: UIColor(colorForLogType(type))])
        fullString.append(typeAttr)
        fullString.append(NSAttributedString(string: " "))

        let messageAttr = NSAttributedString(string: entry.message,
                                             attributes: [.foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black])
        fullString.append(messageAttr)

        return fullString
    }
    
    private func formatTime(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func colorForLogType(_ type: LogManager.LogEntry.LogType) -> Color {
        switch type {
        case .info:
            return .green
        case .error:
            return .red
        case .debug:
            return accentColor
        case .warning:
            return .orange
        }
    }

    private func systemLogType(for raw: String) -> LogManager.LogEntry.LogType {
        let lower = raw.lowercased()
        if lower.contains("error") || lower.contains("failed") || lower.contains("fatal") || lower.contains("fault") {
            return .error
        }
        if lower.contains("warn") {
            return .warning
        }
        if lower.contains("debug") || lower.contains("trace") {
            return .debug
        }
        return .info
    }

    private func systemStatusDisplay() -> (text: String, icon: String) {
        if !systemLogStream.isStreaming {
            return ("Stopped".localized, "pause.circle")
        }
        if systemLogStream.isPaused {
            return ("Paused".localized, "pause.circle")
        }
        if systemLogStream.updateInterval > 0 {
            return ("Throttled".localized, systemSpeedSymbol)
        }
        return ("Streaming".localized, "dot.radiowaves.left.and.right")
    }
    
    private func loadIdeviceLogsAsync() async {
        guard !isLoadingLogs else { return }
        isLoadingLogs = true
        
        let logPath = URL.documentsDirectory.appendingPathComponent("idevice_log.txt").path
        
        guard FileManager.default.fileExists(atPath: logPath) else {
            await MainActor.run {
                logManager.addInfoLog("No idevice logs found (Restart the app to continue reading)")
                isLoadingLogs = false
            }
            return
        }
        
        do {
            let logContent = try String(contentsOfFile: logPath, encoding: .utf8)
            let lines = logContent.components(separatedBy: .newlines)
            
            let maxLines = 500
            let startIndex = max(0, lines.count - maxLines)
            let recentLines = Array(lines[startIndex..<lines.count])
            
            lastProcessedLineCount = lines.count
            
            await MainActor.run {
                logManager.clearLogs()
                
                for line in recentLines {
                    if line.isEmpty { continue }
                    
                    if line.contains("=== DEVICE INFORMATION ===") ||
                       line.contains("Version:") ||
                       line.contains("Name:") ||
                       line.contains("Model:") ||
                       line.contains("=== LOG ENTRIES ===") {
                        continue
                    }
                    
                    if line.contains("ERROR") || line.contains("Error") {
                        logManager.addErrorLog(line)
                    } else if line.contains("WARNING") || line.contains("Warning") {
                        logManager.addWarningLog(line)
                    } else if line.contains("DEBUG") {
                        logManager.addDebugLog(line)
                    } else {
                        logManager.addInfoLog(line)
                    }
                }

                if jitIsAtBottom, let last = logManager.logs.last {
                    jitScrollView?.scrollTo(last.id, anchor: .bottom)
                }
            }
        } catch {
            await MainActor.run {
                logManager.addErrorLog("Failed to read idevice logs: \(error.localizedDescription)")
            }
        }
        
        await MainActor.run {
            isLoadingLogs = false
        }
    }
    
    private func startLogCheckTimer() {
        logCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            if isViewActive {
                Task {
                    await checkForNewLogs()
                }
            }
        }
    }
    
    private func checkForNewLogs() async {
        guard !isLoadingLogs else { return }
        isLoadingLogs = true
        
        let logPath = URL.documentsDirectory.appendingPathComponent("idevice_log.txt").path
        
        guard FileManager.default.fileExists(atPath: logPath) else {
            isLoadingLogs = false
            return
        }
        
        do {
            let logContent = try String(contentsOfFile: logPath, encoding: .utf8)
            let lines = logContent.components(separatedBy: .newlines)
            
            if lines.count > lastProcessedLineCount {
                let newLines = Array(lines[lastProcessedLineCount..<lines.count])
                lastProcessedLineCount = lines.count
                
                await MainActor.run {
                    for line in newLines {
                        if line.isEmpty { continue }
                        
                        if line.contains("ERROR") || line.contains("Error") {
                            logManager.addErrorLog(line)
                        } else if line.contains("WARNING") || line.contains("Warning") {
                            logManager.addWarningLog(line)
                        } else if line.contains("DEBUG") {
                            logManager.addDebugLog(line)
                        } else {
                            logManager.addInfoLog(line)
                        }
                    }
                    
                    let maxLines = 500
                    if logManager.logs.count > maxLines {
                        let excessCount = logManager.logs.count - maxLines
                        logManager.removeOldestLogs(count: excessCount)
                    }

                    if jitIsAtBottom, let last = logManager.logs.last {
                        jitScrollView?.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        } catch {
            await MainActor.run {
                logManager.addErrorLog("Failed to read new logs: \(error.localizedDescription)")
            }
        }
        
        isLoadingLogs = false
    }
    
    private func stopLogCheckTimer() {
        logCheckTimer?.invalidate()
        logCheckTimer = nil
    }
}

private struct GlassOvalButtonStyle: ButtonStyle {
    var height: CGFloat = 36
    var strokeOpacity: Double = 0.16
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(.white.opacity(strokeOpacity), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: configuration.isPressed ? 4 : 10, x: 0, y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct ConsoleLogsView_Previews: PreviewProvider {
    static var previews: some View {
        ConsoleLogsView()
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
