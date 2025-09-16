//
//  AppTheme.swift
//  StikJIT
//
//  Created by Assistant on 9/12/25.
//

import SwiftUI

// MARK: - AppTheme model

enum AppTheme: String, CaseIterable, Identifiable {
    case system            // follows system appearance; static gradient
    case darkStatic        // dark + static gradient
    case neonAnimated      // animated gradient
    case blobs             // morphing blobs
    case particles         // subtle particle field
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system:       return "System"
        case .darkStatic:   return "Dark"
        case .neonAnimated: return "Neon"
        case .blobs:        return "Blobs"
        case .particles:    return "Particles"
        }
    }
    
    // If you want the theme to force a color scheme, set it here.
    // Your app currently forces dark globally; we keep nil so nothing fights it.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:       return nil
        case .darkStatic:   return .dark
        case .neonAnimated: return .dark
        case .blobs:        return .dark
        case .particles:    return .dark
        }
    }
    
    var backgroundStyle: BackgroundStyle {
        switch self {
        case .system:       return .staticGradient
        case .darkStatic:   return .staticGradient
        case .neonAnimated: return .animatedGradient
        case .blobs:        return .blobs
        case .particles:    return .particles
        }
    }
}

// MARK: - Background styles and factory

enum BackgroundStyle {
    case staticGradient
    case animatedGradient
    case blobs
    case particles
}

// Slightly brighter, clearly-not-black static background that still respects dark mode
private func staticBackgroundGradient() -> LinearGradient {
    LinearGradient(
        gradient: Gradient(colors: [
            Color(UIColor.systemBackground),
            Color(UIColor.secondarySystemBackground)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct ThemedBackground: View {
    let style: BackgroundStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        Group {
            switch style {
            case .staticGradient:
                staticBackgroundGradient()
                    .ignoresSafeArea()
            case .animatedGradient:
                if reduceMotion {
                    staticBackgroundGradient()
                        .ignoresSafeArea()
                } else {
                    AnimatedGradientBackground()
                }
            case .blobs:
                if reduceMotion {
                    staticBackgroundGradient()
                        .ignoresSafeArea()
                } else {
                    BlobBackground()
                }
            case .particles:
                if reduceMotion {
                    staticBackgroundGradient()
                        .ignoresSafeArea()
                } else {
                    ParticleFieldBackground()
                }
            }
        }
    }
}

// MARK: - Background container to use at app root

struct BackgroundContainer<Content: View>: View {
    @AppStorage("appTheme") private var rawTheme: String = AppTheme.system.rawValue
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    private var theme: AppTheme {
        AppTheme(rawValue: rawTheme) ?? .system
    }
    
    var body: some View {
        ZStack {
            ThemedBackground(style: theme.backgroundStyle)
                .ignoresSafeArea()
            content
        }
        .preferredColorScheme(theme.preferredColorScheme) // nil means no override
    }
}

// MARK: - Animated backgrounds

private struct AnimatedGradientBackground: View {
    @State private var t: Double = 0
    
    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let speed = 0.15
            let phase = now * speed
            
            let c1 = Color(hue: (sin(phase) * 0.5 + 0.5), saturation: 0.55, brightness: 0.45)
            let c2 = Color(hue: (sin(phase + .pi * 0.66) * 0.5 + 0.5), saturation: 0.75, brightness: 0.35)
            let c3 = Color(hue: (sin(phase + .pi * 1.33) * 0.5 + 0.5), saturation: 0.65, brightness: 0.30)
            
            let angle = Angle(degrees: (sin(phase * 0.7) * 45) + 45)
            
            AngularGradient(colors: [c1, c2, c3, c1], center: .center, angle: angle)
                .saturation(1.0)
                .brightness(0.0)
                .opacity(0.9)
                .ignoresSafeArea()
                .overlay(
                    LinearGradient(colors: [.black.opacity(0.25), .clear],
                                   startPoint: .top,
                                   endPoint: .bottom)
                        .ignoresSafeArea()
                )
        }
    }
}

private struct BlobBackground: View {
    @State private var t: CGFloat = 0
    
    var body: some View {
        Canvas { ctx, size in
            let baseColors: [Color] = [
                .blue.opacity(0.35),
                .purple.opacity(0.35),
                .pink.opacity(0.35),
                .cyan.opacity(0.35)
            ]
            
            let blobs = 6
            let radius = min(size.width, size.height) * 0.45
            
            for i in 0..<blobs {
                let p = CGFloat(i) / CGFloat(blobs)
                let angle = t * (0.5 + 0.1 * CGFloat(i)) + p * .pi * 2
                let r = radius * (0.4 + 0.2 * sin(t + CGFloat(i)))
                
                let x = size.width  * 0.5 + cos(angle) * r
                let y = size.height * 0.5 + sin(angle * 0.9) * r * 0.7
                
                var path = Path()
                path.addEllipse(in: CGRect(x: x - 140, y: y - 140, width: 280, height: 280))
                
                ctx.addFilter(.blur(radius: 40))
                ctx.fill(path, with: .color(baseColors[i % baseColors.count]))
            }
        }
        .background(staticBackgroundGradient())
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                t = .pi * 2
            }
        }
    }
}

private struct ParticleFieldBackground: View {
    struct Particle: Identifiable {
        let id = UUID()
        var position: CGPoint
        var velocity: CGVector
        var size: CGFloat
        var opacity: Double
    }
    
    @State private var particles: [Particle] = []
    private let count = 120
    
    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { _ in
                ZStack {
                    staticBackgroundGradient()
                        .ignoresSafeArea()
                    
                    Canvas { ctx, size in
                        for p in particles {
                            var circle = Path(ellipseIn: CGRect(x: p.position.x,
                                                                y: p.position.y,
                                                                width: p.size,
                                                                height: p.size))
                            ctx.addFilter(.blur(radius: 1.2))
                            ctx.opacity = p.opacity
                            ctx.fill(circle, with: .color(.white.opacity(0.85)))
                        }
                    }
                }
                .onAppear {
                    if particles.isEmpty {
                        particles = (0..<count).map { _ in
                            Particle(
                                position: CGPoint(x: .random(in: 0...geo.size.width),
                                                  y: .random(in: 0...geo.size.height)),
                                velocity: CGVector(dx: .random(in: -0.3...0.3),
                                                   dy: .random(in: -0.3...0.3)),
                                size: .random(in: 1.5...3.5),
                                opacity: .random(in: 0.15...0.45)
                            )
                        }
                    }
                }
                .onChange(of: geo.size) { _, newSize in
                    particles = particles.map { p in
                        var np = p
                        np.position.x = min(max(0, np.position.x), newSize.width)
                        np.position.y = min(max(0, np.position.y), newSize.height)
                        return np
                    }
                }
                .task {
                    while true {
                        try? await Task.sleep(nanoseconds: 16_000_000)
                        var next = particles
                        for i in next.indices {
                            var p = next[i]
                            p.position.x += p.velocity.dx
                            p.position.y += p.velocity.dy
                            
                            if p.position.x < 0 { p.position.x = geo.size.width }
                            if p.position.x > geo.size.width { p.position.x = 0 }
                            if p.position.y < 0 { p.position.y = geo.size.height }
                            if p.position.y > geo.size.height { p.position.y = 0 }
                            
                            next[i] = p
                        }
                        particles = next
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}
