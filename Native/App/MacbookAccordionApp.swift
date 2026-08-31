import SwiftUI

@main
struct MacbookAccordionApp: App {
    @State private var model = InstrumentModel()

    var body: some Scene {
        Window("MacbookAccordion", id: "instrument") {
            InstrumentView(model: model)
                .background(WindowIdentity())
                .task { model.start() }
                .onDisappear { model.stop() }
        }
        .defaultSize(width: 1040, height: 830)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("演奏") {
                Button("升高一个八度") { model.transpose(12) }
                Button("降低一个八度") { model.transpose(-12) }
                Button("恢复默认音高") { model.resetOctave() }
                Divider()
                Button("释放所有琴键") { model.releaseAll() }.keyboardShortcut(".", modifiers: .command)
                Button("恢复默认设置") { model.reset() }.keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button(model.inspectorVisible ? "收起声音检查器" : "显示声音检查器") { model.inspectorVisible.toggle() }
                    .keyboardShortcut("i", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("MacbookAccordion 使用帮助") { model.helpVisible = true }
            }
        }
    }
}

private struct WindowIdentity: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { IdentityView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class IdentityView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.identifier = NSUserInterfaceItemIdentifier("instrument")
            window?.title = "MacbookAccordion"
            window?.subtitle = "原生版"
            window?.setFrameAutosaveName("NativeInstrumentWindow")
        }
    }
}
