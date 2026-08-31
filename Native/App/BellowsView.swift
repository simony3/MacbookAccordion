import SwiftUI

struct BellowsView: View {
    var model: InstrumentModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Label("风箱力度", systemImage: "wind").font(.callout).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(model.bellows.intensity, format: .number.precision(.fractionLength(2)))
                        .font(.system(size: 44, weight: .light, design: .rounded)).monospacedDigit()
                    Text("/ 1.00").font(.callout).foregroundStyle(.tertiary)
                }
                ProgressView(value: model.bellows.intensity).tint(.accentColor)
                    .accessibilityLabel("风箱力度")
                HStack(spacing: 20) {
                    metric("开合角度", String(format: "%.0f°", model.angle))
                    metric("开合速度", String(format: "%.0f°/s", model.bellows.velocity))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            BellowsIllustration(intensity: model.bellows.intensity)
                .frame(width: 210, height: 145).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text(model.held.isEmpty ? "准备好，就开始。" : "旋律正在发生。").font(.headline)
                Text(model.held.isEmpty ? "按住琴键，轻轻推动风箱。\n声音会随着你的动作起伏。" : model.playing)
                    .font(.callout).foregroundStyle(.secondary).lineSpacing(5)
                    .frame(height: 48, alignment: .topLeading)
                if model.simulated {
                    HStack(spacing: 8) {
                        Button { model.simulate(-1) } label: { Label("合上", systemImage: "arrow.down") }
                        Button { model.simulate(1) } label: { Label("打开", systemImage: "arrow.up") }
                    }.controlSize(.small)
                } else {
                    Label("跟随屏幕开合", systemImage: "laptopcomputer").font(.caption).foregroundStyle(Color.accentColor)
                }
            }.frame(width: 200, alignment: .leading)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [Color.accentColor.opacity(scheme == .dark ? 0.15 : 0.07), Color(nsColor: .controlBackgroundColor)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.accentColor.opacity(0.13)))
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
        }
    }
}

private struct BellowsIllustration: View {
    let intensity: Double
    var body: some View {
        GeometryReader { proxy in
            let width = 130 + intensity * 36
            let origin = (proxy.size.width - width) / 2
            ZStack {
                Ellipse().fill(Color.accentColor.opacity(0.06)).frame(width: 190, height: 25).offset(y: 66)
                HStack(spacing: 0) {
                    endCap(keyboard: false)
                    HStack(spacing: 0) {
                        ForEach(0..<10) { index in
                            UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 2)
                                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.45), Color.accentColor.opacity(0.12), Color.accentColor.opacity(0.32)], startPoint: .leading, endPoint: .trailing))
                                .overlay(alignment: .leading) { Rectangle().fill(Color.accentColor.opacity(0.22)).frame(width: 1) }
                                .padding(.vertical, index % 2 == 0 ? 0 : 3)
                        }
                    }.frame(width: width - 54, height: 104)
                    endCap(keyboard: true)
                }
                .frame(width: width, height: 126)
                .position(x: origin + width / 2, y: proxy.size.height / 2)
                .rotationEffect(.degrees(-8))
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func endCap(keyboard: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(0.8).gradient)
            .frame(width: 27, height: 122)
            .overlay {
                if keyboard {
                    VStack(spacing: 2) {
                        ForEach(0..<10) { _ in RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.94)).frame(width: 16, height: 7) }
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(0..<6) { _ in HStack(spacing: 5) {
                            Circle().fill(.white.opacity(0.65)).frame(width: 3)
                            Circle().fill(.white.opacity(0.65)).frame(width: 3)
                        }.frame(height: 3) }
                    }
                }
            }
    }
}
