import SwiftUI

/// Animated splash screen shown on app launch.
/// Auto-dismisses after ~2.5 seconds with a fade-out.
struct SplashScreenView: View {
    /// When provided, tapping the splash dismisses it.
    var onDismiss: (() -> Void)? = nil

    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var poweredByOpacity: Double = 0
    @State private var footerOpacity: Double = 0
    @State private var glowAmount: CGFloat = 0

    var body: some View {
        ZStack {
            // Background — warm cream matching the logo
            Color(red: 0.96, green: 0.93, blue: 0.87)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // "Powered by" label
                Text("Powered by")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
                    .opacity(poweredByOpacity)
                    .padding(.bottom, 8)

                // Logo image
                Image("SplashLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .shadow(color: .green.opacity(glowAmount), radius: 30, x: 0, y: 0)

                Spacer()

                // Footer
                Text("© 2026 Cirilo Wortel. All rights reserved.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .opacity(footerOpacity)
                    .padding(.bottom, 40)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss?()
        }
        .onAppear {
            // Stage 1: Logo fades in and scales up with spring
            withAnimation(.easeOut(duration: 0.8)) {
                logoOpacity = 1
                logoScale = 1.0
            }

            // Stage 2: Green glow pulse
            withAnimation(.easeInOut(duration: 1.2).delay(0.4)) {
                glowAmount = 0.6
            }

            // Stage 3: "Powered by" fades in
            withAnimation(.easeIn(duration: 0.5).delay(0.5)) {
                poweredByOpacity = 1
            }

            // Stage 4: Footer fades in
            withAnimation(.easeIn(duration: 0.5).delay(0.8)) {
                footerOpacity = 1
            }
        }
    }
}
