# Megabyte

A native macOS menu bar app that controls a **Gigabyte M28U** monitor: everything Gigabyte's Windows-only
**OSD Sidekick** can change, without OSD Sidekick.

It talks to the monitor over the USB cable (the monitor's built-in KVM hub), the same way OSD Sidekick does,
and it can read the current value of every setting, not just write it.

## What it does

Click the monitor icon in the menu bar:

- **Live preview** of the monitor. The drawn screen follows the real brightness and color temperature, shows the
  current picture mode, and mirrors the crosshair, dashboard, timer/counter and picture-in-picture box when they are on.
- **Brightness, contrast and volume** as Control Center style sliders.
- **Picture modes** as swatches: Standard, FPS, RTS/RPG, Movie, Reader, sRGB, Custom 1–3.
- **Tiles** that open a page for each group of settings: Picture, Gaming, Game Assist, PiP / PbP, Input, Monitor.

All values are read from the monitor when it connects; the main ones are re-read each time the popover opens. Changes are sent,
read back and retried if the monitor dropped them.

## Install

1. Download `Megabyte-<version>-macos-arm64.zip` from [Releases](../../releases) and unzip it.
2. Move `Megabyte.app` to `/Applications`.
3. The app is not notarized. On first launch, right-click it and choose **Open**, or run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/Megabyte.app
   ```

Requirements: Apple silicon Mac, macOS 26 or later, and the monitor's USB upstream cable (USB-B or USB-C)
connected to the Mac. If the monitor's KVM has given its USB hub to another computer, the menu bar icon shows a
warning and the controls are disabled until it comes back.

## Feature parity with OSD Sidekick

| OSD Sidekick feature | Megabyte | Notes |
|---|---|---|
| Brightness, contrast, sharpness, volume | ✅ | |
| Picture mode (incl. Custom 1–3) | ✅ | |
| Reset current picture mode | ✅ | |
| Black eQualizer, color vibrance, low blue light | ✅ | |
| Gamma, color temperature, user R/G/B | ✅ | R/G/B only apply when color temperature is User |
| Overdrive, Aim Stabilizer, FreeSync | ✅ | Overdrive option names not checked against the monitor's menu |
| Super resolution | ✅ | |
| Refresh rate display | ✅ | |
| Crosshair on/off | ✅ | |
| Crosshair styles and custom crosshair editor | ❌ | Styles 1–3 all looked the same on the M28U; custom upload not decoded |
| Game timer (count up / down, pause, reset) | ✅ | |
| Game counter | ✅ | |
| Timer / counter / refresh rate position | ✅ | Write-only; the monitor does not report it |
| Dashboard on/off and position | ✅ | |
| Dashboard values | ⚠️ | Megabyte sends this Mac's CPU and GPU load. Temperatures, clocks, fans and mouse DPI are not sent |
| PIP / PBP mode, source, size, location, audio, swap | ✅ | |
| Input source | ✅ | Not tested yet (switching away from the Mac's input cuts the Mac off) |
| KVM switch and per-port input mapping | ✅ | KVM switch not tested yet, same reason |
| OSD transparency, OSD display time, LED indicator | ✅ | |
| Quick switch (joystick shortcuts) | ✅ | |
| Monitor joystick (drive the monitor's own menu) | ✅ | |
| Reading current values | ✅ | |
| Saved picture profiles, per-app profiles | ❌ | |
| Keyboard hotkeys | ❌ | |
| Firmware update, EDID flashing | ❌ | Left out on purpose: a bad write can brick the monitor |
| OSD Sidekick self-update, languages | ❌ | |
| Headset ANC, OLED care | — | Other Gigabyte models only |

## How it was made

1. **Unpacking OSD Sidekick.** The download (`OSD_Sidekick220418`) is a cabinet with an InstallShield
   `setup.exe` inside. Its payload is an obfuscated *InstallShield setup stream*: each file is XOR-encoded with a
   key derived from its own file name, then zlib-compressed. `re/tools/isx.py` decodes it, which yields an MSI,
   and the MSI's `Data1.cab` holds the actual app.
2. **Reading the app.** `OSDSidekick.exe` is a .NET (WPF) program, so it decompiles back to readable C# with
   ILSpy. That showed every setting it reads and writes, the byte values it sends, and which models get which
   options. The M28U identifies itself as `GBT2800` and gets the default feature set.
3. **Reading the USB library.** The C# code hands raw bytes to `RtHIDLib.dll`, a native Realtek library. Its
   `HID_i2cwrite` and `HID_i2cread` functions were disassembled to recover the exact USB report layout.
4. **Testing on the monitor.** A small Swift probe (`re/tools/probe.swift`) repeated those reports from macOS
   and read the monitor's brightness and model name. `re/tools/m28u.swift` then changed every setting, read it
   back and restored it, and the on-screen features were confirmed by looking at the monitor.
5. **The app.** SwiftUI menu bar app with no dependencies. IOKit HID for the USB link, a single serial queue
   for all monitor traffic, and an observable store that streams slider changes and verifies them.

### The protocol in short

The monitor contains a Realtek USB HID device (`0bda:1100`) that forwards I²C to the monitor's scaler. The
messages are standard **DDC/CI**, so brightness is the standard VESA code `0x10`, while Gigabyte's own features
live under codes `E0 xx`.

- **Write:** one 192-byte output report `40 c6 00 00 00 00 <len> 00 6e 00 80 …` with the DDC message at byte 64,
  for example `51 85 03 e0 2c 00 01 <checksum>` to select the FPS picture mode.
- **Read:** send a DDC "Get VCP" message, then an output report starting `40 d6 51`, wait about 100 ms, and fetch
  the answer with a HID GetInputReport.

The full command table, value ranges and test results are in [`re/PROTOCOL.md`](re/PROTOCOL.md).

## Build from source

Needs Swift 6.2 or later. The Xcode Command Line Tools are enough.

```sh
./scripts/build-app.sh      # builds build/Megabyte.app
open build/Megabyte.app
```

Command line probe for experimenting with codes:

```sh
swiftc -O -o m28u re/tools/m28u.swift
./m28u get e02c             # current picture mode
./m28u set 10 40            # brightness 40
```

## Other monitors

Only the M28U has been tested. OSD Sidekick uses the same Realtek protocol for other Gigabyte models
(M27Q, M27U, M32U, M32Q and others), so many settings will likely work there too, but value ranges and options
differ per model.

## Prior work

- [kelvie/gbmonctl](https://github.com/kelvie/gbmonctl): write-only CLI for the M32U over the same USB device.
- [ayufan-research/gigabyte-m32u-ddcctl](https://github.com/ayufan-research/gigabyte-m32u-ddcctl): Gigabyte
  `E0` code table for the M32U over DDC/CI.
- [WildFireFlum/gbmonitor](https://github.com/WildFireFlum/gbmonitor): Python port of gbmonctl.

Not affiliated with or endorsed by Gigabyte. No Gigabyte code or binaries are included in this repository.
