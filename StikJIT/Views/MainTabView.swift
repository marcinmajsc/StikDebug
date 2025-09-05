//
//  MainTabView.swift
//  StikJIT
//
//  Created by Stephen on 3/27/25.
//

import SwiftUI

struct MainTabView: View {
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    @State private var selection: Int = 0

    // You can still keep this for non-tint styling (borders, fills, etc.) if desired.
    private var accentColor: Color {
        customAccentColorHex.isEmpty ? .white : (Color(hex: customAccentColorHex) ?? .white)
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            ScriptListView()
                .tabItem { Label("Scripts", systemImage: "scroll") }
                .tag(1)
            
          //  IPAAppManagerView()
          //      .tabItem { Label("Testing", systemImage: "square.grid.2x2.fill") }
          //      .tag(2)

            // Replaced AP installer with Device Info
            DeviceInfoView()
                .tabItem { Label("Device Info", systemImage: "info.circle.fill") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(4)
        }
        // Remove per-view accent override so the app-wide .tint(Color.white) applies everywhere.
        // If you want the tab selection color to be white globally, rely on WindowGroup .tint(.white).
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
