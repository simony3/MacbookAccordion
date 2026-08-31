# MacbookAccordion

> **This branch includes a complete native Swift edition.** Open `MacbookAccordion.xcodeproj` in Xcode, select `MacbookAccordion` → `My Mac`, and run with `⌘R`. Requires macOS 14+; no Python or third-party runtime dependencies. See the [native development notes](Native/README.md). Existing v1.0.0 release downloads remain the Python edition.

<p align="center">
  <img src="assets/MacbookAccordion-AppIcon.png" width="160" alt="MacbookAccordion icon">
</p>

<p align="center">
  <strong>Use the MacBook lid as the bellows and the computer keyboard as the keys.</strong><br>
  A playful macOS app designed for people who simply want to try an accordion-like instrument.
</p>

<p align="center"><a href="README.md">中文</a></p>

> [!NOTE]
> This is a personal modification of [MacacaGames/MacbookAccordion](https://github.com/MacacaGames/MacbookAccordion), made for local learning and fun. The original project and this repository use the MIT License.

## Download

[**Download MacbookAccordion 1.0.0 (DMG)**](https://github.com/simony3/MacbookAccordion/releases/download/v1.0.0/MacbookAccordion-v1.0.0.dmg)

Alternatives: [universal ZIP](https://github.com/simony3/MacbookAccordion/releases/download/v1.0.0/MacbookAccordion-v1.0.0-macOS-universal.zip) · [SHA-256 checksums](https://github.com/simony3/MacbookAccordion/releases/download/v1.0.0/SHA256SUMS.txt)

1. Open the downloaded DMG.
2. Drag `MacbookAccordion.app` into `Applications`.
3. Launch MacbookAccordion from Applications.

This build supports both Apple Silicon and Intel Macs. It is not signed with an Apple Developer ID or notarized, so macOS may block the first launch. If you trust the file downloaded from this repository, try to open it once, then open System Settings → Privacy & Security and choose Open Anyway in the Security section. See [Apple's guidance](https://support.apple.com/en-ca/102445) for details.

## Interface

![MacbookAccordion native SwiftUI interface](Native/native-ui.png)

The screenshot shows this branch's native SwiftUI edition: live bellows feedback, interactive piano keys, four sound styles, and a collapsible sound inspector. Existing parameters and playing logic are preserved. The v1.0.0 downloads above are still the legacy Python app.

## Features

- Turns MacBook lid movement into playing intensity
- Shows an on-screen piano with the corresponding computer keys
- Includes Classic, Soft, Bright, and Fun sound styles
- Keeps volume, lid sensitivity, pitch, and reset controls immediately available
- Falls back to a keyboard demo mode when the lid-angle sensor is unavailable
- Keeps the original detailed bellows and sound controls in the sound inspector (“More settings” in the legacy edition)

## Get started

### Run the native edition in Xcode

Open `MacbookAccordion.xcodeproj`, select `MacbookAccordion` → `My Mac`, and press `⌘R`. Requires macOS 14+; Python is not needed.

Alternatively, build the universal app from the repository root:

```bash
./build_native_app.sh
open 'build/native/Build/Products/Release/MacbookAccordion Native.app'
```

The native build does not replace the installed legacy app. See the [native development notes](Native/README.md) for parameter parity, validation, and limitations.

### Build the legacy Python macOS app

```bash
chmod +x build_mac_app.sh
./build_mac_app.sh
```

The script creates a local virtual environment, installs the dependencies, builds the app, and installs it at:

```text
/Applications/MacbookAccordion.app
```

Launch it with:

```bash
open -a MacbookAccordion
```

> The build script replaces `/Applications/MacbookAccordion.app` and removes the temporary `build/` and `dist/` directories after installation.

### Run the legacy Python app

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install pygame-ce numpy sounddevice pybooklid
python lid_accordion.py
```

## Play

1. Open the app and wait for “Lid control connected.”
2. Move the MacBook lid gently and press the keys shown on the piano.
3. Use the `−` / `+` controls to change pitch, or select a sound style.
4. Choose Reset whenever you want to return to the initial setup.

In demo mode, use `↑` / `↓` to simulate lid movement.

### Keyboard map

| Range | White keys | Black keys |
| --- | --- | --- |
| Middle | `Q W E R T Y U I O P` | `1 2 4 5 6 8 9 0` |
| High | `Z X C V B N M , . /` | `A S D F G H J K L ;` |

`3` and `7` are intentionally unused to preserve piano-key spacing.

### Pitch shortcuts

| Action | Result |
| --- | --- |
| Release `Shift` | One octave up |
| Release `Ctrl` | One octave down |
| `Tab` | Reset pitch |

## Sound styles

| Style | Character |
| --- | --- |
| Classic | The default, balanced accordion-like sound |
| Soft | Slower attack and a longer release |
| Bright | Faster response and a clearer sound |
| Fun | More detune and air noise |

The detailed controls for air build-up, leakage, smoothing, attack, release, detune, and air noise remain available in the native sound inspector and in the legacy edition's More settings.

## Legacy Python requirements

| Item | Notes |
| --- | --- |
| OS | macOS |
| Hardware | A MacBook that exposes lid-angle data; other environments use demo mode |
| Python | Python 3 |
| Dependencies | `pygame-ce`, `numpy`, `sounddevice`, `pybooklid` |

## How it works

The native edition reads the lid angle through IOKit, preserves the original bellows model and synthesis formulas in Swift, outputs audio through AVAudioEngine, and renders the interface with SwiftUI.

The retained legacy edition uses `pybooklid`, `PolyAccordionSynth`, and a Retina `pygame-ce` interface. Native tests compare parameters, key mappings, and numerical output against the legacy implementation.

## Credits

- Original project: [MacacaGames/MacbookAccordion](https://github.com/MacacaGames/MacbookAccordion)
- Lid-angle reference: [samhenrigold/LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor)
- This personal version adds the Chinese Retina interface, on-screen keyboard, beginner mode, sound presets, app icon, and local packaging workflow.

Thanks to the original authors for making the project available.

## License

Licensed under the [MIT License](LICENSE). The original license and copyright notice are preserved.
