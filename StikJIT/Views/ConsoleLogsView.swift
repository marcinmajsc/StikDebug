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
    @State private var autoScroll = true
    @State private var paused = false
    @State private var scrollView: ScrollViewProxy? = nil
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    
    // Alert handling
    @State private var showingCustomAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @State private var isError = false
    
    // Timer to check for log updates
    @State private var logCheckTimer: Timer? = nil
    
    // Track if the view is active (visible)
    @State private var isViewActive = false
    @State private var lastProcessedLineCount = 0
    @State private var isLoadingLogs = false
    @State private var isAtBottom = true
    
    // Search
    @State private var searchText = ""
    // Filter by level
    enum LevelFilter: String, CaseIterable, Identifiable {
        case all = "ALL"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case debug = "DEBUG"
        var id: String { rawValue }
    }
    @State private var level: LevelFilter = .all
    
    // Gutter toggle (line numbers)
    @State private var showGutter = false
    
    // Share / export helpers
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    // Copy toast
    @State private var justCopied = false
    // Blinking cursor
    @State private var showCursor = true
    @State private var cursorTimer: Timer? = nil
    
    // Fixed terminal viewport height (taller)
    private let terminalHeight: CGFloat = 520
    
    private var accentColor: Color {
        if customAccentColorHex.isEmpty {
            return .white
        } else {
            return Color(hex: customAccentColorHex) ?? .white
        }
    }
    
    private var filteredLogs: [LogManager.LogEntry] {
        let base = logManager.logs.filter { entry in
            switch level {
            case .all: return true
            case .info: return entry.type == .info
            case .warning: return entry.type == .warning
            case .error: return entry.type == .error
            case .debug: return entry.type == .debug
            }
        }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.message.localizedCaseInsensitiveContains(searchText)
            || $0.type.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
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
                        consoleCard
                        footerInfo
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 30)
                }
                .sheet(isPresented: $showShareSheet) {
                    ActivityViewController(items: shareItems)
                }
                
                if isLoadingLogs {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Loading logs…")
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
                
                if showingCustomAlert {
                    CustomErrorView(
                        title: alertTitle,
                        message: alertMessage,
                        onDismiss: { showingCustomAlert = false },
                        showButton: true,
                        primaryButtonText: "OK",
                        messageType: isError ? .error : .success
                    )
                }
                
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
            .navigationTitle("Console")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Exit", systemImage: "chevron.left")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await loadIdeviceLogsAsync() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    Button {
                        exportLogs()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Menu {
                        Button {
                            copyLogsToPasteboard()
                        } label: {
                            Label("Copy All", systemImage: "doc.on.doc")
                        }
                        Button {
                            shareAll()
                        } label: {
                            Label("Share…", systemImage: "square.and.arrow.up.on.square")
                        }
                        Divider()
                        Button {
                            showGutter.toggle()
                        } label: {
                            Label(showGutter ? "Hide Line Numbers" : "Show Line Numbers", systemImage: "number")
                        }
                        Divider()
                        Button(role: .destructive) {
                            logManager.clearLogs()
                        } label: {
                            Label("Clear Logs", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                isViewActive = true
                Task { await loadIdeviceLogsAsync() }
                startLogCheckTimer()
                startCursorBlink()
            }
            .onDisappear {
                isViewActive = false
                stopLogCheckTimer()
                stopCursorBlink()
            }
        }
    }
    
    // MARK: - Console UI
    
    private var consoleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            controlStrip
            searchField
            consoleCanvas
            promptBar
        }
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
    
    // Top strip: icon-only controls to avoid smushing
    private var controlStrip: some View {
        HStack(spacing: 10) {
            // Chips in a horizontal scroller to prevent wrapping
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    levelFilterChip(.all)
                    levelFilterChip(.info)
                    levelFilterChip(.warning)
                    levelFilterChip(.error)
                    levelFilterChip(.debug)
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity)
            
            // Right-side icon-only controls
            HStack(spacing: 12) {
                // Pause/Resume
                Button {
                    paused.toggle()
                } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(paused ? .green : .orange)
                        .padding(8)
                        .background(
                            Circle()
                                .fill((paused ? Color.green : Color.orange).opacity(0.18))
                        )
                        .overlay(
                            Circle()
                                .stroke((paused ? Color.green : Color.orange).opacity(0.45), lineWidth: 0.8)
                        )
                }
                .accessibilityLabel(paused ? "Resume" : "Pause")
                .accessibilityHint("Toggle pausing of live output")
                .buttonStyle(.plain)
                
                // Auto-scroll toggle (icon-only)
                Button {
                    autoScroll.toggle()
                } label: {
                    Image(systemName: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(autoScroll ? accentColor : .secondary)
                }
                .accessibilityLabel("Auto Scroll")
                .accessibilityValue(autoScroll ? "On" : "Off")
                .buttonStyle(.plain)
                
                // Clear
                Button {
                    logManager.clearLogs()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Clear Logs")
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.tertiarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
    
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Filter text…", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.caption.monospaced())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(UIColor.tertiarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
    
    // Fixed-size, scrollable terminal viewport with auto-scroll
    private var consoleCanvas: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    consolePreface
                    
                    ForEach(Array(filteredLogs.indices), id: \.self) { idx in
                        let entry = filteredLogs[idx]
                        ConsoleLineRow(
                            index: idx,
                            entry: entry,
                            showGutter: showGutter,
                            attributed: makeAttributed(entry)
                        )
                        .id(entry.id)
                    }
                    
                    CursorLine(showGutter: showGutter, showCursor: showCursor)
                        .opacity(paused ? 0.5 : 1.0)
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("consoleScroll")).minY
                        )
                    }
                )
            }
            .frame(height: terminalHeight)
            .coordinateSpace(name: "consoleScroll")
            .background(consoleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                isAtBottom = offset > -20
            }
            .onChange(of: logManager.logs.count) { _ in
                guard autoScroll && !paused else { return }
                if isAtBottom {
                    withAnimation {
                        if let last = filteredLogs.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .onAppear {
                scrollView = proxy
            }
        }
    }
    
    private var promptBar: some View {
        HStack(spacing: 8) {
            Text("\(UIDevice.current.name.replacingOccurrences(of: " ", with: "")):\u{007E}$")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(accentColor)
            Text(paused ? "Paused — output suppressed" : "Read-only console")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
            Button {
                copyLogsToPasteboard()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.tertiarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
    
    private var consoleBackground: some View {
        ZStack {
            Color.black
            LinearGradient(
                colors: [
                    Color.white.opacity(0.03),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private var consolePreface: some View {
        VStack(alignment: .leading, spacing: 0) {
            consoleLine("# === DEVICE INFORMATION ===", color: .secondary, bold: true)
            consoleLine("# iOS Version: \(UIDevice.current.systemVersion)", color: .secondary)
            consoleLine("# Device: \(UIDevice.current.name)", color: .secondary)
            consoleLine("# Model: \(UIDevice.current.model)", color: .secondary)
            consoleLine("# === LOG ENTRIES ===", color: .secondary, bold: true)
        }
        .padding(.top, 8)
    }
    
    private func levelFilterChip(_ f: LevelFilter) -> some View {
        let selected = level == f
        return Button {
            level = f
        } label: {
            HStack(spacing: 6) {
                if f != .all {
                    Circle()
                        .fill(levelColor(f).opacity(0.9))
                        .frame(width: 8, height: 8)
                }
                Text(f.rawValue)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? accentColor.opacity(0.2) : Color(UIColor.tertiarySystemBackground))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(selected ? accentColor.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 0.8)
            )
            .foregroundColor(selected ? accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
    
    private func levelColor(_ f: LevelFilter) -> Color {
        switch f {
        case .all: return .gray
        case .info: return .green
        case .warning: return .orange
        case .error: return .red
        case .debug: return accentColor
        }
    }
    
    private func consoleLine(_ text: String, color: Color = .secondary, bold: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12, weight: bold ? .semibold : .regular, design: .monospaced))
            .foregroundColor(colorScheme == .dark ? color.opacity(0.8) : color.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .padding(.horizontal, 10)
    }
    
    private var footerInfo: some View {
        HStack {
            Spacer()
            Text("iOS \(UIDevice.current.systemVersion)")
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.top, 6)
    }
    
    // MARK: - Attributed log helpers
    
    private func makeAttributed(_ entry: LogManager.LogEntry) -> AttributedString {
        let ns = createTerminalAttributedString(entry)
        return AttributedString(ns)
    }
    
    private func createTerminalAttributedString(_ logEntry: LogManager.LogEntry) -> NSAttributedString {
        let full = NSMutableAttributedString()
        
        // Timestamp (dim)
        let ts = "[\(formatTime(date: logEntry.timestamp))]"
        full.append(NSAttributedString(
            string: ts + " ",
            attributes: [
                .foregroundColor: UIColor(white: 1.0, alpha: 0.45)
            ]
        ))
        
        // Type (colored)
        let typeColor = UIColor(colorForLogType(logEntry.type))
        full.append(NSAttributedString(
            string: "[\(logEntry.type.rawValue)] ",
            attributes: [.foregroundColor: typeColor]
        ))
        
        // Message (bright)
        full.append(NSAttributedString(
            string: logEntry.message,
            attributes: [.foregroundColor: UIColor.white]
        ))
        
        return full
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
    
    // MARK: - File loading and timer
    
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
            
            // Only last 500 lines
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
            if isViewActive && !paused {
                Task { await checkForNewLogs() }
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
                    
                    // Keep only the last 500 lines
                    let maxLines = 500
                    if logManager.logs.count > maxLines {
                        let excessCount = logManager.logs.count - maxLines
                        logManager.removeOldestLogs(count: excessCount)
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
    
    private func startCursorBlink() {
        stopCursorBlink()
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                showCursor.toggle()
            }
        }
    }
    
    private func stopCursorBlink() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        showCursor = true
    }
    
    // MARK: - Actions (export/copy/share)
    
    private func allLogsText() -> String {
        var logsContent = "=== DEVICE INFORMATION ===\n"
        logsContent += "Version: \(UIDevice.current.systemVersion)\n"
        logsContent += "Name: \(UIDevice.current.name)\n"
        logsContent += "Model: \(UIDevice.current.model)\n"
        logsContent += "StikJIT Version: App Version: 1.0\n\n"
        logsContent += "=== LOG ENTRIES ===\n"
        logsContent += filteredLogs.map {
            "[\(formatTime(date: $0.timestamp))] [\($0.type.rawValue)] \($0.message)"
        }.joined(separator: "\n")
        return logsContent
    }
    
    private func copyLogsToPasteboard() {
        UIPasteboard.general.string = allLogsText()
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
        showCopiedToast()
    }
    
    private func shareAll() {
        shareItems = [allLogsText()]
        showShareSheet = true
    }
    
    private func exportLogs() {
        let logPath = URL.documentsDirectory.appendingPathComponent("idevice_log.txt")
        if FileManager.default.fileExists(atPath: logPath.path) {
            shareItems = [logPath]
            showShareSheet = true
        } else {
            alertTitle = "Export Failed"
            alertMessage = "No idevice logs found"
            isError = true
            showingCustomAlert = true
        }
    }
    
    private func showCopiedToast() {
        withAnimation { justCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { justCopied = false }
        }
    }
}

private struct ConsoleLineRow: View {
    let index: Int
    let entry: LogManager.LogEntry
    let showGutter: Bool
    let attributed: AttributedString
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if showGutter {
                Text(String(format: "%5d", index + 1))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(width: 44, alignment: .trailing)
            }
            Text(attributed)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 10)
    }
}

private struct CursorLine: View {
    let showGutter: Bool
    let showCursor: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            if showGutter {
                Text("     ")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.clear)
                    .frame(width: 44, alignment: .trailing)
            }
            Text(" ")
                .font(.system(size: 12, design: .monospaced))
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(showCursor ? 0.9 : 0.0))
                        .frame(width: 8, height: 14)
                        .offset(x: 0, y: 1),
                    alignment: .leading
                )
                .frame(height: 16)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 10)
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

// MARK: - UIKit Share Sheet wrapper

private struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
