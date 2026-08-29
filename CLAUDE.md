# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MacbookAccordion — a Python app that turns a MacBook into a virtual accordion by reading the lid angle sensor as bellows input. Keys are played via keyboard; audio is synthesized in real time. Falls back to simulation mode (arrow keys) when the sensor is unavailable.

Bundle ID: `games.macaca.macbookaccordion`, version `0.0.2`.

## Commands

### Run directly (development)
```bash
pip install pygame-ce numpy sounddevice pybooklid
python lid_accordion.py
```

### Build macOS .app bundle
```bash
chmod +x build_mac_app.sh
./build_mac_app.sh
# Output: /Applications/MacbookAccordion.app
```

The build script creates a venv, installs deps (including py2app), runs `setup.py py2app`, then dittos the bundle into /Applications and removes `build` / `dist` (a bundle left under `dist` gets registered with Launch Services, producing a duplicate app in Launchpad/Spotlight). It also drops a placeholder `pygame_icon.icns` into the pygame package, because py2app's pygame recipe hardcodes that filename and pygame-ce does not ship it.

## Architecture

The entire application lives in a single file: `lid_accordion.py`.

### Key components (all in `lid_accordion.py`):

- **`PolyAccordionSynth`** — Thread-safe polyphonic synth engine. Generates audio via dual detuned sawtooth waves with tanh soft-clipping. Manages per-voice state (phase, envelope) and bellows-driven volume. Called from `sounddevice` audio callback at 44100 Hz / 256-sample blocks.

- **Bellows pipeline** (in `main()` loop) — Reads lid angle via `pybooklid.read_lid_angle()`, computes angular velocity, maps it through dead zone / fill / leak / smoothing params to produce a 0–1 bellows value fed to the synth.

- **Key mapping** — Four lookup tables (`WHITE_Q`, `BLACK_1`, `WHITE_Z`, `BLACK_A`) map pygame key constants to MIDI note numbers across two octave groups. Octave transposition via Shift/Ctrl/Tab key-up events.

- **GUI** — Pygame-based, styled after macOS System Settings: toolbar (status pill + 恢复默认 button), a fixed performance area (bellows meter, stat row with octave −/+ buttons, on-screen piano), and scrollable grouped cards of `Slider` rows. The `Param` dataclass holds per-parameter metadata (range, step, format, group); groups render in list order.

- **`Display`** — Wraps `pygame.Window(allow_high_dpi=True)` so the canvas is the full Retina drawable (1880x1600 for a 940x800pt window); falls back to `set_mode` at 1x on upstream pygame. Layout and hit-testing stay in logical points, and only the drawing primitives (`text`, `rr`, `capsule`, `knob`, `box`, `hairline`) multiply by the global `S`.

- **`Type`** — Text renderer that splits a string into latin/CJK runs and renders them with SF Pro (variable-font weight instances) and PingFang SC respectively, aligned on a shared baseline and cached by (text, size, weight, color).

- **`_ensure_sounddevice_portaudio_filesystem()`** — Workaround at top of file that extracts PortAudio binaries from py2app's zipped Python stdlib so `sounddevice` can find them at runtime.

### External dependencies
`pygame-ce`, `numpy`, `sounddevice`, `pybooklid` (lid angle sensor via IOKit). `py2app` is build-only.
