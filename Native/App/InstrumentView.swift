import SwiftUI

struct InstrumentView: View {
    @Bindable var model: InstrumentModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heading
                BellowsView(model: model)
                soundStyles
                PianoView(model: model)
                quickControls
                footer
            }
            .padding(24)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 740, minHeight: 640)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 7) {
                    Circle().fill(model.connecting ? Color.secondary : model.simulated ? Color.orange : Color.green).frame(width: 7, height: 7)
                    Text(model.status).font(.callout).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.reset() } label: { Label("恢复默认", systemImage: "arrow.counterclockwise") }
                    .help("恢复所有原始参数和音高（⌘R）")
                Button { model.helpVisible = true } label: { Label("使用帮助", systemImage: "questionmark.circle") }
                Button { model.inspectorVisible.toggle() } label: { Label("声音检查器", systemImage: "sidebar.right") }
                    .help("显示或收起声音检查器（⌘I）")
            }
        }
        .inspector(isPresented: $model.inspectorVisible) {
            InspectorView(model: model).inspectorColumnWidth(min: 285, ideal: 310, max: 360)
        }
        .sheet(isPresented: $model.helpVisible) { HelpView() }
        .onChange(of: model.helpVisible) { _, showing in if showing { model.releaseAll() } }
    }

    private var heading: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text("让开合，成为旋律。").font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(model.simulated ? "用 ↑ ↓ 模拟风箱，再按琴键上的字符开始演奏。" : "轻轻开合屏幕，按下琴键。把 MacBook 变成你的手风琴。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            Image(systemName: "pianokeys").font(.system(size: 25, weight: .light))
                .foregroundStyle(Color.accentColor).padding(14)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var soundStyles: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("声音风格").font(.headline)
                if model.preset == nil { Text("自定义").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Text("同一副琴键，四种心情").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ForEach(SoundPreset.allCases) { style in
                    Button { model.choose(style) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: style.symbol).font(.system(size: 20, weight: .regular)).frame(width: 25)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(style.rawValue).font(.system(size: 13, weight: .semibold))
                                Text(style.detail).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if model.preset == style { Image(systemName: "checkmark.circle.fill").font(.caption) }
                        }
                        .foregroundStyle(model.preset == style ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(model.preset == style ? Color.accentColor.opacity(scheme == .dark ? 0.16 : 0.07) : Color(nsColor: .controlBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(model.preset == style ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.07)))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(style.rawValue)音色")
                    .accessibilityAddTraits(model.preset == style ? .isSelected : [])
                }
            }
        }
    }

    private var quickControls: some View {
        HStack(alignment: .center, spacing: 32) {
            ParameterControl(model: model, spec: ParameterSpec.all[0])
            Divider().frame(height: 42)
            ParameterControl(model: model, spec: ParameterSpec.all[1])
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: model.audioError == nil ? "waveform" : "exclamationmark.triangle.fill")
                .foregroundStyle(model.audioError == nil ? Color.secondary : .orange)
            if let error = model.audioError {
                Text("声音输出不可用").foregroundStyle(.orange).help(error)
                Button("重试") { model.retryAudio() }.buttonStyle(.link)
            } else { Text("44.1 kHz · 实时合成").foregroundStyle(.secondary) }
            Spacer()
            Text("Shift 升八度  ·  Ctrl 降八度  ·  Tab 归位").foregroundStyle(.secondary)
        }.font(.caption)
    }
}

struct ParameterControl: View {
    var model: InstrumentModel
    let spec: ParameterSpec
    private var value: Binding<Double> {
        Binding(get: {
            let raw = model.parameters[spec.id]
            return spec.inverted ? spec.minimum + spec.maximum - raw : raw
        }, set: { newValue in
            model.set(spec, value: spec.inverted ? spec.minimum + spec.maximum - newValue : newValue)
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(spec.label).font(.callout)
                Spacer()
                Text(model.parameters[spec.id], format: .number.precision(.fractionLength(spec.decimals)))
                    .monospacedDigit().font(.callout).foregroundStyle(.secondary)
            }
            Slider(value: value, in: spec.minimum...spec.maximum, step: spec.step)
                .accessibilityLabel(spec.label)
                .accessibilityValue(String(format: "%.*f", spec.decimals, model.parameters[spec.id]))
                .help(spec.inverted ? "向右更灵敏；保留原参数 vel_max，数值越小越灵敏。" : "\(spec.minimum) – \(spec.maximum)，步长 \(spec.step)")
        }
    }
}

#Preview("演奏 · 浅色") { InstrumentView(model: InstrumentModel(preview: true)).frame(width: 1040, height: 790) }
#Preview("演奏 · 深色") { InstrumentView(model: InstrumentModel(preview: true)).frame(width: 1040, height: 790).preferredColorScheme(.dark) }
