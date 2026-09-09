import SwiftUI

/// A local, permission-free introduction. Completion is owned by the caller so
/// the same experience can be replayed from Settings without changing app state.
struct OnboardingScreen: View {
    let onComplete: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize = 43
    private let accent = Color.appColors.primaryColor

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                TabView(selection: $page) {
                    ForEach(0..<3) { index in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                OnboardingArtwork(chapter: index, isActive: page == index)
                                    .frame(height: max(220, min(geometry.size.height * 0.40, 420)))
                                    .accessibilityHidden(true)
                                introduction(index)
                            }
                            .padding(.horizontal, 28)
                            .padding(.bottom, 16)
                            .frame(maxWidth: 620)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollIndicators(.hidden)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                footer
            }
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "waveform").foregroundStyle(accent)
                Text("mixtape").tracking(-1)
            }
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .accessibilityElement(children: .ignore).accessibilityLabel("Mixtape")
            Spacer()
            Button("Skip", action: onComplete)
                .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.6))
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 28).padding(.top, 6)
        .frame(maxWidth: 676).frame(maxWidth: .infinity)
    }

    private func introduction(_ index: Int) -> some View {
        let chapters = ["THE MOMENT", "THE EDIT", "YOUR SIGNATURE"]
        let titles = ["Life happens.", "Find your", "Make it once."]
        let highlights = ["Make it a film.", "own rhythm.", "Make it yours."]
        let descriptions = [
            "Turn the moments on your camera roll into stories worth watching again.",
            "Cut to the feeling. Layer your sound, shape your colors, and let every frame say more.",
            "Save your favorite edits as templates. Keep the style, change the story, and create again."
        ]
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Rectangle().fill(accent).frame(width: 22, height: 2)
                Text("0\(index + 1) / \(chapters[index])")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(titles[index]).foregroundStyle(.white)
                Text(highlights[index]).foregroundStyle(accent)
            }
            .font(.system(size: headlineSize, weight: .bold))
            .tracking(-1.8)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            Text(descriptions[index])
                .font(.body).foregroundStyle(.white.opacity(0.56))
                .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        Capsule().fill(index == page ? accent : .white.opacity(0.2))
                            .frame(width: index == page ? 26 : 6, height: 5)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Page \(page + 1) of 3")
                Spacer()
                if page > 0 {
                    Button { move(to: page - 1) } label: {
                        Label("Back", systemImage: "arrow.left").font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.white.opacity(0.55)).frame(minHeight: 44)
                } else {
                    Text("A LITTLE MOMENT. A BIG STORY.")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .tracking(1).foregroundStyle(.white.opacity(0.35)).frame(minHeight: 44)
                }
            }
            Button {
                if page == 2 { onComplete() } else { move(to: page + 1) }
            } label: {
                HStack {
                    Spacer()
                    Text(page == 2 ? "Enter your studio" : "Continue")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.headline).foregroundStyle(.black)
                .padding(.horizontal, 22).frame(minHeight: 56)
                .background(accent, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(OnboardingPressStyle())
            Text("Your next story starts with you.")
                .font(.caption2).foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 28).padding(.bottom, 14)
        .frame(maxWidth: 620).frame(maxWidth: .infinity)
    }

    private func move(to value: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { page = value }
    }
}

private struct OnboardingPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
    }
}

private struct OnboardingArtwork: View {
    let chapter: Int
    let isActive: Bool
    @State private var drift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let accent = Color.appColors.primaryColor

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, 420)
            let height = geometry.size.height
            ZStack {
                Circle().fill(accent.opacity(0.12)).frame(width: width * 0.85)
                    .blur(radius: 55)
                Circle().stroke(.white.opacity(0.055), lineWidth: 1)
                    .frame(width: width * 0.95, height: width * 0.95)
                Circle().stroke(.white.opacity(0.035), lineWidth: 1)
                    .frame(width: width * 1.2, height: width * 1.2)
                if chapter == 0 {
                    moment(width: width, height: height)
                } else if chapter == 1 {
                    edit(width: width, height: height)
                } else {
                    signature(width: width, height: height)
                }
            }
            .frame(width: geometry.size.width, height: height)
        }
        .onChange(of: isActive, initial: true) { _, active in animate(active: active) }
        .onChange(of: reduceMotion) { _, _ in animate(active: isActive) }
    }

    private func animate(active: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { drift = false }
        if active && !reduceMotion {
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { drift = true }
        }
    }

    private func photo(width: CGFloat, height: CGFloat, saturation: Double = 1) -> some View {
        Image("OnboardingCinema").resizable().scaledToFill()
            .frame(width: width, height: height).clipped().saturation(saturation)
    }

    private func moment(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22).fill(Color(white: 0.09))
                .frame(width: width * 0.68, height: height * 0.83)
                .overlay { RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.1)) }
                .rotationEffect(.degrees(-11)).offset(x: -16, y: -2)
            photo(width: width * 0.68, height: height * 0.86)
                .overlay(alignment: .topLeading) {
                    Label("REC", systemImage: "circle.fill")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(12)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GOLDEN HOUR").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                        Text("a moment worth keeping.").font(.system(size: 11, design: .serif)).italic()
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay { RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.22)) }
                .rotationEffect(.degrees(drift ? 5 : 2))
                .offset(y: drift ? -5 : 3)
                .shadow(color: .black.opacity(0.5), radius: 16, y: 12)
            badge("MADE OF MOMENTS", icon: "sparkle")
                .rotationEffect(.degrees(-7)).offset(x: -width * 0.12, y: height * 0.34)
            Image(systemName: "play.fill").font(.system(size: 19))
                .foregroundStyle(.black).frame(width: 52, height: 52)
                .background(accent, in: Circle())
                .overlay { Circle().stroke(.black, lineWidth: 5) }
                .offset(x: width * 0.33, y: -height * 0.23)
        }
    }

    private func edit(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            photo(width: width * 0.9, height: height * 0.56)
                .overlay {
                    HStack {
                        Rectangle().fill(.white.opacity(0.15)).frame(width: 1)
                        Spacer()
                        Rectangle().fill(.white.opacity(0.15)).frame(width: 1)
                    }.padding(.horizontal, width * 0.27)
                }
                .overlay(alignment: .bottomLeading) {
                    Text("THE LAST LIGHT").font(.system(size: 19, weight: .black)).tracking(-0.5).padding(16)
                }
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "waveform.path").foregroundStyle(accent)
                    Text("YOUR STORY, IN MOTION").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1)
                    Spacer()
                    Text("00:12").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                }
                ZStack(alignment: .leading) {
                    VStack(spacing: 5) {
                        HStack(spacing: 3) {
                            ForEach(0..<5) { _ in
                                photo(width: width * 0.145, height: 32).clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding(3).background(accent.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                        waveform.frame(height: 24)
                            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    }
                    Rectangle().fill(.white).frame(width: 2, height: 76)
                        .overlay(alignment: .top) { Circle().fill(.white).frame(width: 6, height: 6) }
                        .offset(x: width * (drift ? 0.64 : 0.25))
                }
            }.padding(14).background(Color(white: 0.055))
        }
        .frame(width: width * 0.9)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.15)) }
        .rotationEffect(.degrees(-3))
        .overlay(alignment: .topTrailing) {
            badge("CUT. COLOR. FEEL.", icon: "slider.horizontal.3")
                .rotationEffect(.degrees(7)).offset(x: 6, y: -15)
        }
    }

    private var waveform: some View {
        Canvas { context, size in
            for index in 0..<54 {
                let value = 0.2 + abs(sin(Double(index) * 1.7) * cos(Double(index) * 0.43)) * 0.8
                let height: CGFloat = size.height * CGFloat(value) * 0.8
                let rect = CGRect(x: CGFloat(index) * size.width / 54, y: (size.height - height) / 2, width: 2, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(accent))
            }
        }
    }

    private func signature(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            templateCard("MONO", width: width * 0.53, height: height * 0.72, saturation: 0)
                .rotationEffect(.degrees(drift ? -16 : -13)).offset(x: -width * 0.2, y: 6)
            templateCard("AFTERGLOW", width: width * 0.53, height: height * 0.72, saturation: 0.6)
                .rotationEffect(.degrees(drift ? 16 : 13)).offset(x: width * 0.2, y: 6)
            templateCard("GOLDEN", width: width * 0.57, height: height * 0.8, saturation: 1.2)
                .offset(y: drift ? -10 : -4)
                .shadow(color: .black.opacity(0.6), radius: 16, y: 10)
            badge("YOUR STYLE. ON REPEAT.", icon: "arrow.trianglehead.2.clockwise.rotate.90")
                .offset(y: height * 0.37)
        }
    }

    private func templateCard(_ title: String, width: CGFloat, height: CGFloat, saturation: Double) -> some View {
        photo(width: width, height: height, saturation: saturation)
            .overlay(alignment: .bottom) {
                VStack(spacing: 4) {
                    Text(title).font(.system(size: 20, weight: .black)).tracking(-0.7)
                    Text("YOUR SAVED STYLE").font(.system(size: 6, weight: .bold, design: .monospaced)).tracking(1.4)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.2)) }
    }

    private func badge(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(0.8)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(Color(white: 0.09), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.16)) }
    }
}

#Preview { OnboardingScreen {} }
