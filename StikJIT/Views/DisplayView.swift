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
        .blue,  // Default system blue
        .init(hex: "#7FFFD4")!, // Aqua
        .init(hex: "#50C878")!, // Green
        .red,   // Red
        .init(hex: "#6A5ACD")!, // Purple
        .init(hex: "#DA70D6")!, // Pink
        .white, // White
        .black  // Black
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
                
                // Direct Color Picker Circle
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
    @AppStorage("appTheme") private var appTheme: String = "system"
    @AppStorage("loadAppIconsOnJIT") private var loadAppIconsOnJIT = true
    @State private var selectedAccentColor: Color = .blue
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var justSaved = false
    
    private var accentColor: Color {
        if customAccentColorHex.isEmpty {
            return .blue
        } else {
            return Color(hex: customAccentColorHex) ?? .blue
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient (glassy style)
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
                        usernameCard
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
                applyTheme(appTheme)
            }
        }
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
            
            HStack(spacing: 12) {
                ThemeOptionButton(title: "System", imageName: "theme-system", isSelected: appTheme == "system", accentColor: accentColor) {
                    appTheme = "system"
                    applyTheme(appTheme)
                    showSavedToast()
                }
                ThemeOptionButton(title: "Light", imageName: "theme-light", isSelected: appTheme == "light", accentColor: accentColor) {
                    appTheme = "light"
                    applyTheme(appTheme)
                    showSavedToast()
                }
                ThemeOptionButton(title: "Dark", imageName: "theme-dark", isSelected: appTheme == "dark", accentColor: accentColor) {
                    appTheme = "dark"
                    applyTheme(appTheme)
                    showSavedToast()
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
            selectedAccentColor = .blue
        } else {
            selectedAccentColor = Color(hex: customAccentColorHex) ?? .blue
        }
    }
    
    private func applyTheme(_ theme: String) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            switch theme {
            case "dark": window.overrideUserInterfaceStyle = .dark
            case "light": window.overrideUserInterfaceStyle = .light
            default: window.overrideUserInterfaceStyle = .unspecified
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

// MARK: - Theme Option Button (Glassy style)
struct ThemeOptionButton: View {
    let title: String
    let imageName: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 120)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? accentColor : .clear, lineWidth: 2)
                    )
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(isSelected ? accentColor : .primary)
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        }
        .frame(maxWidth: .infinity)
    }
}
