import SwiftUI

struct InspectorView: View {
    @Bindable var model: InstrumentModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("声音检查器").font(.headline)
                Spacer()
                Button { model.inspectorVisible = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("收起声音检查器")
            }.padding(20)
            Divider()
            Form {
                ForEach(["开合细节", "声音细节"], id: \.self) { group in
                    Section(group) {
                        ForEach(ParameterSpec.all.filter { $0.group == group }) { spec in
                            ParameterControl(model: model, spec: spec).padding(.vertical, 3)
                        }
                    }
                }
                Section("输入与输出") {
                    Toggle("使用键盘试玩", isOn: $model.forceSimulation)
                        .help("打开后使用 ↑ ↓ 模拟开合，每次 3°；关闭后优先使用屏幕传感器。")
                    LabeledContent("屏幕控制", value: model.sensorAvailable ? "已连接" : "不可用")
                    LabeledContent("声音输出", value: model.audioError == nil ? "正常" : "不可用")
                    Button("重新连接屏幕控制") { model.reconnect() }
                    if model.audioError != nil { Button("重试声音输出") { model.retryAudio() } }
                }
                Section {
                    Text("所有数值、范围和步长均沿用原版。手动调整声音细节后，音色会显示为「自定义」。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("恢复默认设置") { model.reset() }
                }
            }.formStyle(.grouped)
        }
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Image(systemName: "pianokeys").font(.largeTitle).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("开始你的第一段旋律").font(.title2.bold())
                    Text("MacbookAccordion · 原生 macOS 版").foregroundStyle(.secondary)
                }
            }
            Text("按住琴键，同时轻轻开合 MacBook 屏幕。开合动作给风箱充气，琴键决定音高。没有开合力度时，按键不会直接发声。")
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow { Text("中音区白键").foregroundStyle(.secondary); Text("Q W E R T Y U I O P").monospaced() }
                GridRow { Text("中音区黑键").foregroundStyle(.secondary); Text("1 2 4 5 6 8 9 0").monospaced() }
                GridRow { Text("高音区白键").foregroundStyle(.secondary); Text("Z X C V B N M , . /").monospaced() }
                GridRow { Text("高音区黑键").foregroundStyle(.secondary); Text("A S D F G H J K L ;").monospaced() }
            }
            Divider()
            Text("松开 Shift 升高一个八度，松开 Ctrl 降低一个八度；Tab 恢复默认音高，范围 ±3 个八度。Escape 退出应用，⌘. 释放所有琴键。")
            Text("无法连接屏幕传感器时会自动进入键盘试玩。每按一次 ↑ / ↓，模拟角度改变 3°。也可以在声音检查器中主动开启试玩。")
            Text("基于 MacacaGames/MacbookAccordion；传感器接口参考 PyBookLid。保留 MIT 许可证及原作者声明。")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("开始演奏") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 510)
    }
}
