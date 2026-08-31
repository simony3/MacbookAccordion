# MacbookAccordion 原生版

SwiftUI + AppKit 界面、AVAudioEngine 音频输出、IOKit 屏幕角度读取。应用不包含 Python、Pygame、网页或第三方运行库。

原生版在 `codex/native-macos-app` 分支开发，未替换已发布的 1.0.0。旧版源码和打包脚本保留原样。最低系统为 macOS 14；本机使用 Xcode 26.6 验证。

![原生版实际运行截图](native-ui.png)

## 在 Xcode 里运行

1. 打开仓库根目录的 `MacbookAccordion.xcodeproj`，不要把用于核心测试的 `Package.swift` 当成 App 入口。
2. Scheme 选择 `MacbookAccordion`，运行目标选择 `My Mac`。
3. 按 `⌘R`。默认使用本机临时签名，不需要配置付费开发者账号。

应用显示名为 `MacbookAccordion Native`，Bundle ID 为 `games.macaca.macbookaccordion.native`，与旧版隔离。Xcode 构建只写入构建目录，不安装或覆盖 `/Applications/MacbookAccordion.app`。

命令行构建 Apple Silicon / Intel 通用版本：

```bash
./build_native_app.sh
open 'build/native/Build/Products/Release/MacbookAccordion Native.app'
```

原生版尚未进行 Developer ID 签名、公证或公开发布。通用构建包含 `arm64` 与 `x86_64`；Intel 和最低系统版本尚未实机验证。传感器依赖具体 MacBook 硬件。不要开启 App Sandbox：当前 HID 访问方式未在沙盒环境验证，不应直接视为可提交 Mac App Store 的版本。

## 演奏和设置

演奏前先轻轻开合屏幕，再按住界面提示的字母或数字键。没有风箱力度时，琴键不会直接出声。传感器不可用时自动切换到试玩，每次按 `↑` / `↓` 模拟角度变化 `3°`，范围 `0–110°`，初始 `45°`。也可在检查器中主动开启试玩。

点击右上角检查器按钮或按 `⌘I`，调整高级参数。四种预设只影响起音、释音、失谐和噪声；手动修改这四项会显示为“自定义”。不增加参数持久化，重新启动仍使用旧版默认值。

| 操作 | 效果 |
| --- | --- |
| 松开 Shift / Ctrl | 升高 / 降低一个八度，范围 ±3 八度 |
| 松开 Tab | 恢复默认音高 |
| 按住屏幕琴键 | 鼠标演奏，与实体键盘可以叠加 |
| `⌘.` | 释放全部琴键，清除待播音符 |
| `⌘R`（应用中） | 恢复原有参数、预设、音高和模拟角度，收起检查器 |
| Escape | 退出应用；帮助窗口中沿用系统行为 |

键盘按物理 QWERTY 位置映射，中文输入法下也可以演奏。非 QWERTY 布局按物理位置而非字符映射。两处映射到相同 MIDI 音高的键仍是独立声部。窗口失焦会释放琴键，系统 Command/Option 快捷键不会被当成演奏输入。

## 保留的参数

| 参数 | 默认 | 最小 | 最大 | 步长 |
| --- | ---: | ---: | ---: | ---: |
| master | 0.30 | 0.05 | 1.20 | 0.01 |
| vel_max | 160 | 30 | 400 | 1 |
| fill_rate | 2.2 | 0.1 | 8.0 | 0.1 |
| leak_rate | 0.12 | 0 | 2.0 | 0.01 |
| deadzone | 0.010 | 0 | 0.080 | 0.001 |
| rise_a | 0.70 | 0 | 0.99 | 0.01 |
| fall_a | 0.960 | 0 | 0.999 | 0.001 |
| attack_s | 0.020 | 0.001 | 0.200 | 0.001 |
| release_s | 0.120 | 0.010 | 1.000 | 0.005 |
| detune | 0.005 | 0 | 0.050 | 0.001 |
| noise | 0.008 | 0 | 0.080 | 0.001 |

灵敏度滑块仍反向映射 `vel_max`：向右更灵敏，底层数值更小。数值量化沿用 Python 的最近偶数舍入。风箱更新目标为 60 Hz，按实际经过时间计算速度、进气和漏气；上升、下降平滑系数保留原算法。

合成保持 44,100 Hz、单声道、256 样本分块、两路锯齿波 0.6/0.4 混合、`tanh(1.6 * signal)`、线性起释音、标准正态气流噪声及最终 `[-1, 1]` 限幅。Core Audio 的设备采样率不一定是 44.1 kHz，由系统转换；内部合成采样率不变。噪声采用相同分布的新随机序列，不保证与 NumPy 随机样本逐点相同。

## 验证

```bash
swift test
```

8 项测试包含完整参数和 38 个键位、4 种预设、188 帧风箱轨迹、10,240 个音频样本、重复音高独立声部、按住时转调、释音、紧急释放、极限和弦限幅，以及 HID 报文解码。对照数据来自旧版实际代码，不是根据 Swift 实现手写的期望值。

如有意变更旧版兼容目标，用现有 Python 环境重新提取基准：

```bash
.venv/bin/python Native/Scripts/capture_legacy_contract.py
swift test
```

提取脚本只执行选定的旧版合成器与风箱公式，不初始化 Pygame、传感器或音频设备。常规原生构建和测试不需要 Python。

本次本机验证：Debug 与通用 Release 编译成功；8 项测试通过；关闭随机噪声后，与旧版 Float32 波形的最大绝对误差为 `5.140900611877441e-7`，容差为 `2e-5`。原生 App 实际连接到当前 MacBook 的屏幕传感器并读出角度，AVAudioEngine 启动成功。没有把这些结果等同于完整的人工听感、休眠唤醒或音频设备热切换测试。

实际界面回读还覆盖：柔和预设的四项数值、修改失谐后进入自定义音色、失谐由 `0.005` 按单步递增到 `0.006`、试玩角度由 `45°` 变为 `48°`、八度按钮同步更新音名、Tab 归位、恢复默认以及窗口缩放。自动化工具不能单独发送修饰键释放，Shift/Ctrl 的独立按放仍需人工演奏确认。

## 从哪里修改

| 文件 / 目录 | 用途 |
| --- | --- |
| `App/MacbookAccordionApp.swift` | App 入口、窗口和原生菜单 |
| `App/InstrumentView.swift` | 演奏布局、音色按钮和轻松设置 |
| `App/BellowsView.swift`、`App/PianoView.swift` | 风箱反馈、手风琴插画与交互琴键 |
| `App/InspectorView.swift` | 高级参数和帮助 |
| `App/InstrumentModel.swift` | 演奏状态、生命周期、输入切换 |
| `App/KeyboardInput.swift` | 限于当前窗口的 AppKit 键盘事件 |
| `App/LidSensor.swift` | 独立串行队列上的 HID 读取 |
| `App/AudioEngine.swift` | Core Audio 输出、实时线程数据交接 |
| `Core/` | 可独立测试的原始参数、风箱公式、音符与合成器 |
| `Tests/` | Python 基准数据与 Swift XCTest 对照 |

音频渲染使用预分配声部和块缓冲区；仅尝试获取短锁，竞争时继续使用上一份完整输入，不阻塞等待主线程。传感器同步读取放在独立队列，避免阻塞 SwiftUI。画面状态由 Observation 驱动，浅色和深色均跟随系统。

接口参考：[Apple AVAudioSourceNode](https://developer.apple.com/documentation/avfaudio/avaudiosourcenode)、[Apple IOHIDDeviceGetReport](https://developer.apple.com/documentation/iokit/1588659-iohiddevicegetreport)。源项目署名仍见主 README 与 LICENSE；PyBookLid 接口来源的 MIT 声明保存在 `Resources/ThirdPartyNotices.txt` 并随 App 打包。
