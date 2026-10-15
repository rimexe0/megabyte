# Gigabyte M28U control protocol (from OSD Sidekick 220418)

Source: decompiled `osdsidekick.exe` (.NET, `re/src/osdsidekick`) and disassembled `rthidlib.dll`.
Read path confirmed on the real M28U from macOS (`re/tools/probe.swift`).

## Transport

- USB HID device `0bda:1100` (Realtek bridge inside the monitor), usage page `0xFFDA`, usage `0xDA`.
  Only visible to the computer that currently owns the monitor's KVM USB upstream.
- Each HID report is 192 bytes, report ID 0. The bridge forwards an I2C transfer to the scaler at
  address `0x6E`, so the payload is plain DDC/CI.
- The same DDC/CI messages also work over the video cable (DDC), e.g. with `m1ddc` / BetterDisplay.

### I2C write (`HID_i2cwrite`) — SetOutputReport
```
off 0x00: 40 c6 00 00 00 00 <len> 00
off 0x08: 6e 00 80
off 0x40: <len bytes of DDC payload>
```

### I2C read (`HID_i2cread`) — SetOutputReport, sleep ~100 ms, GetInputReport
```
off 0x00: 40 d6 51 00 00 00 <len> 00     (51 = DDC sub-address, little-endian u32)
off 0x08: 6e 01 80
```
The input report contains the raw DDC reply starting at byte 0.

## DDC payloads

Checksum as Sidekick computes it: XOR of all preceding payload bytes (no `0x6E` seed).

| Op | Payload |
|----|---------|
| Get standard VCP | `51 82 01 <code> <chk>` |
| Get Gigabyte VCP | `51 83 01 e0 <code> <chk>` |
| Set standard VCP | `51 84 03 <code> <hi> <lo> <chk>` |
| Set Gigabyte VCP (1-byte value) | `51 85 03 e0 <code> 00 <val> <chk>` |
| Set Gigabyte VCP (2-byte value) | `51 86 03 e0 <code> <hi> <lo>` |

Get reply: `6e 88 02 00 <code...> <type> <maxH> <maxL> <curH> <curL> <chk>`; Sidekick reads the value from bytes 8–9.
Confirmed on the M28U: brightness → `6e 88 02 00 10 00 00 64 00 1e` (max 100, current 30).
`e0 5e` returns the model string: `M28U`.

Sidekick checks the model through EDID ID `GBT2800` and has no M28U-specific code, so the M28U gets the default feature set.

## Command table (codes Sidekick reads/writes)

Standard VCP: `10` brightness, `12` contrast, `62` volume, `87` sharpness.

Gigabyte `E0 xx`:

| xx | Feature | Values seen in Sidekick |
|----|---------|------------------------|
| 02 | Black Equalizer | 0–20 |
| 03 | Color temperature | 0 cool, 1 normal, 2 warm, 3 user |
| 04/05/06 | User R / G / B | 0–100, only writable when color temp = 3 |
| 07 | Gamma | 0 off, 1–5 |
| 08 | Color vibrance | 0–20 |
| 09 | Overdrive | 0–4 (model dependent) |
| 0A | Aim Stabilizer (DyAc) | 0/1 (Sidekick turns FreeSync off first) |
| 0B | Low blue light | 0–10 |
| 0C | FreeSync | 0/1 |
| 0D | Super resolution | slider |
| 0E | PIP/PBP | 0 off, 1 PIP, 2 PBP |
| 0F | PIP/PBP source | 0 HDMI1, 1 HDMI2, 2 DP, 3 Type-C |
| 10 | PIP/PBP display swap | write 1 |
| 13 | PIP/PBP audio swap | 0/1 |
| 14 | PIP size | 0–2 |
| 15 | PIP location | 0–3 |
| 18 | Dashboard | 0/1 |
| 19 | Dashboard location | 0/1 |
| 1A–21 | Dashboard values (CPU temp/freq/fan/usage, GPU temp/freq/fan/usage) | 2-byte value |
| 23 | Game timer mode | 0 off, 1 up, 2 down |
| 25 | Game timer current (read) | |
| 26 | Game timer set | minutes, seconds |
| 27 | Game timer pause/resume | 0/1 |
| 28 | Game counter | 0/1 |
| 29 | Game counter current (read) | |
| 2A | Game counter set | 0–99 |
| 2B | Timer/counter/FPS location | x (0/1), y (0–2) |
| 2C | Picture mode | 0–6, 9, 10 (reads max 9 on M28U) |
| 2D | Input source | 0 HDMI1, 1 HDMI2, 2 DP, 3 Type-C |
| 2E | Audio input | 0 main, 1 PIP/PBP, 2 auto |
| 2F | OSD transparency | 0–4 |
| 30 | OSD display time | write 0–5 (5 s steps), reads back in seconds |
| 31 | LED indicator | 0 on, 1 off, 2 standby |
| 32–35 | Quick switch up/down/right/left | function index (right only accepted 7 on the M28U) |
| 37 | Crosshair | 0 off, 1–4 |
| 38 | Firmware version (read) | |
| 40–48 | Dashboard item visibility | 0/1 |
| 49, 52 | Sent at startup (`52=1`, `49=0`) | meaning not confirmed |
| 4A | Mouse DPI (dashboard) | 2-byte value |
| 4C | Reset current picture mode | write 1 |
| 53 | HDR state (read) | |
| 5E | Model string (read) | |
| 5F/60/61/62/63 | OSD joystick press: center / up / down / right / left | write 1 (center then down = power off) |
| 69 | KVM switch | 0 USB-B, 1 Type-C |
| 6B/6C | KVM USB-B / Type-C video input | 0–3 |

Custom crosshair upload uses a longer write: `51 a2 03 e0 …` (not decoded yet).
Firmware/EDID flashing (`RFlash.dll`, `E0 D0 …`) is deliberately not covered.

## Tested on the M28U (2026-10-15, USB HID from macOS)

Changed, read back and restored: brightness, contrast, volume, sharpness, Black Equalizer, color temperature,
gamma, vibrance, overdrive, low blue light, FreeSync, Aim Stabilizer, super resolution, PIP size/location,
OSD transparency, OSD display time, LED, quick switch, KVM input mapping (6B/6C), user RGB, picture mode.

Confirmed on screen: crosshair on/off, refresh-rate display, dashboard on/off/location, dashboard values
(`setraw e0 1a 00 00 37 00` = CPU 55), game timer, game counter + value, counter location, PIP on/off,
picture mode, joystick emulation.

Notes:
- Writes sent back-to-back are sometimes dropped and reads sometimes time out; wait ~0.5 s and verify/retry.
- Dashboard values: `E0 <1A..21> <n/10000> <n%10000/100> <n%100> <neg flag>`.
- Crosshair 1–3 read back correctly but all looked the same on screen.
- Not tested yet: input switch (2D), KVM switch (69), audio input (2E, only changes with PIP/PBP on),
  firmware read (38 returned 0x460B), HDR read (53), custom crosshair upload.
- Not restored to a known original: timer/counter location (2B, now 01 00) and dashboard item flags (40–48, now all 1).
