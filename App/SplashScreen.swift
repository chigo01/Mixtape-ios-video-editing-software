import SwiftUI

/// A brief brand reveal on cold launch. The destination loads underneath it.
struct SplashScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    private let accent = Color.appColors.primaryColor

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 500
            ZStack {
                Color.black

                RadialGradient(
                    colors: [accent.opacity(0.13), accent.opacity(0.025), .clear],
                    center: UnitPoint(x: 0.5, y: 0.43),
                    startRadius: 0,
                    endRadius: min(geometry.size.width * 0.85, 420)
                )

                // Fine concentric grooves echo tape reels and a camera lens.
                ZStack {
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(.white.opacity(0.045 - Double(index) * 0.01), lineWidth: 0.5)
                            .frame(width: CGFloat(260 + index * 100), height: CGFloat(260 + index * 100))
                    }
                }
                .offset(y: -28)
                .accessibilityHidden(true)

                VStack(spacing: compact ? 20 : 30) {
                    mark
                        .frame(width: compact ? 86 : 112, height: compact ? 86 : 112)
                        .scaleEffect(revealed || reduceMotion ? 1 : 0.88)

                    VStack(spacing: 12) {
                        Text("mixtape")
                            .font(.system(size: compact ? 48 : 58, weight: .bold, design: .rounded))
                            .tracking(-3)
                            .foregroundStyle(.white)
                        Text("MAKE EVERY MOMENT MOVE.")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(2.6)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed || reduceMotion ? 0 : 8)
                }
                .offset(y: compact ? -12 : -28)
                .padding(.horizontal, 24)

                VStack {
                    Spacer()
                    VStack(spacing: 18) {
                        HStack(spacing: 4) {
                            ForEach(0..<23) { index in
                                Capsule()
                                    .fill(accent.opacity(index == 11 ? 0.95 : 0.18))
                                    .frame(width: 2, height: index == 11 ? 15 : (index % 3 == 0 ? 8 : 4))
                            }
                        }
                        Text("A LITTLE MOMENT. A BIG STORY.")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .tracking(1.7)
                            .foregroundStyle(.white.opacity(0.28))
                    }
                    .padding(.bottom, compact ? 18 : 36)
                }
                .accessibilityHidden(true)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .background(.black)
        .ignoresSafeArea()
        .statusBarHidden()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mixtape. Make every moment move.")
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7)) {
                revealed = true
            }
        }
    }

    private var mark: some View {
        Image("SplashAppIcon")
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: accent.opacity(revealed ? 0.24 : 0.08), radius: 35, y: 8)
        .accessibilityHidden(true)
    }
}

#Preview { SplashScreen() }
