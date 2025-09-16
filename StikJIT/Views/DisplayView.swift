//  DisplayView.swift
//  StikJIT
//
//  Created by neoarz on 4/9/25.

import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Accent Color Picker (Glassy style)
struct AccentColorPicker: View {
    @Binding var selectedColor: Color
    
    let colors: [Color] = [
        .blue,
        .init(hex: "#7FFFD4")!,
        .init(hex: "#50C878")!,
        .red,
        .init(hex: "#6A5ACD")!,
        .init(hex: "#DA70D6")!,
        .white,
        .black
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Accent Color")
                .font(.headline)
                .foregroundColor(.primary)
            
            LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 12), count: 9), spacing: 12) {
                ForEach(colors, id: \.self) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .overlay(
                            Circle().stroke(selectedColor == color ? Color.primary : .clear, lineWidth: 2)
                        )
                        .onTapGesture {
                            selectedColor = color
                        }
                }
                
                ColorPicker("", selection: $selectedColor)
                    .labelsHidden()
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .clipShape(Circle())
            }
            .frame(maxWidth: .infinity)
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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Display Settings View
struct DisplayView: View {
    @AppStorage("username") private var username = "User"
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("loadAppIconsOnJIT") private var loadAppIconsOnJIT = true
    @State private var selectedAccentColor: Color = .white
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var justSaved = false
    
    private var accentColor: Color {
        if customAccentColorHex.isEmpty {
            return .white
        } else {
            return Color(hex: customAccentColorHex) ?? .white
        }
    }
    
    private var selectedTheme: AppTheme {
        get { AppTheme(rawValue: appThemeRaw) ?? .system }
        set { appThemeRaw = newValue.rawValue }
    }
    
    private var hardcodedGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(UIColor.systemBackground),
                Color(UIColor.secondarySystemBackground)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                hardcodedGradient.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        usernameCard
                        accentCard
                        jitOptionsCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 30)
                }
                
                if justSaved {
                    VStack {
                        Spacer()
                        Text("Saved")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 3)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 30)
                    }
                    .animation(.easeInOut(duration: 0.25), value: justSaved)
                }
            }
            .navigationTitle("Display")
            .onAppear {
                loadCustomAccentColor()
                applyTheme(selectedTheme)
            }
        }
        .tint(selectedAccentColor)
    }
    
    // MARK: - Cards
    
    private var usernameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Username")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            HStack {
                TextField("Username", text: $username)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.vertical, 8)
                
                if !username.isEmpty {
                    Button(action: {
                        username = ""
                        showSavedToast()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
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
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
    }
    
    private var accentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accent")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            AccentColorPicker(selectedColor: $selectedAccentColor)
            
            HStack(spacing: 12) {
                Button {
                    if let hex = selectedAccentColor.toHex() {
                        customAccentColorHex = hex
                    } else {
                        customAccentColorHex = ""
                    }
                    showSavedToast()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selectedAccentColor)
                    )
                    .foregroundColor(selectedAccentColor.contrastText())
                }
                
                Button {
                    customAccentColorHex = ""
                    selectedAccentColor = .white
                    showSavedToast()
                } label: {
                    HStack {
                        Image(systemName: "arrow.uturn.backward.circle")
                        Text("Reset")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(UIColor.tertiarySystemBackground))
                    )
                }
            }
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
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        .onChange(of: selectedAccentColor) { _, _ in
        }
    }
    
    private var jitOptionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App List")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Load App Icons", isOn: $loadAppIconsOnJIT)
                    .tint(accentColor)
                
                Text("Disabling this will hide app icons in the app list and may improve performance, while also giving it a more minimalistic look.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
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
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
    }
    
    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Theme")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Grid of theme previews
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    ThemePreviewCard(theme: theme, selected: selectedTheme == theme) {
                        // Write directly to AppStorage to avoid mutating through a computed property
                        appThemeRaw = theme.rawValue
                        applyTheme(theme)
                        showSavedToast()
                    }
                }
            }
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
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
    }
    
    // MARK: - Helpers
    
    private func loadCustomAccentColor() {
        if customAccentColorHex.isEmpty {
            selectedAccentColor = .white
        } else {
            selectedAccentColor = Color(hex: customAccentColorHex) ?? .white
        }
    }
    
    private func applyTheme(_ theme: AppTheme) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            switch theme {
            case .darkStatic, .neonAnimated, .blobs, .particles:
                window.overrideUserInterfaceStyle = .dark
            case .system:
                window.overrideUserInterfaceStyle = .unspecified
            }
        }
    }
    
    private func showSavedToast() {
        withAnimation { justSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { justSaved = false }
        }
    }
}

// MARK: - Theme Preview Card

private struct ThemePreviewCard: View {
    let theme: AppTheme
    let selected: Bool
    let action: () -> Void
    
    private var hardcodedGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(UIColor.systemBackground),
                Color(UIColor.secondarySystemBackground)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                hardcodedGradient
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .padding(8)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                VStack(spacing: 6) {
                    Text(theme.displayName)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(8)
            }
            .frame(height: 120)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.accentColor : Color.white.opacity(0.12), lineWidth: selected ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
