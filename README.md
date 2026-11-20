# FanShift

[English](README.md) | [中文](README.zh.md)

A macOS menu bar app that cycles through named fan profiles with one global hotkey. Each profile is a temperature → fan speed curve that you edit by dragging points on a chart. FanShift drives the fans directly through the SMC, so no other fan utility is needed.

It replaces my earlier project [tgpro-hotkey-mac](https://github.com/KrisWonka/tgpro-hotkey-mac), which did the same job by rewriting TG Pro's rules from a Hammerspoon hotkey.

> So far it has been tested on one machine: a MacBook Pro with M5 Pro (Mac17,9) on macOS 27. M1–M4 support is written but untested. See [Compatibility](#compatibility).

## Features

- **Global hotkey** (default `⌃⌥⌘8`, rebindable). Each press moves to the next profile and shows its name in the middle of the screen. No Accessibility permission is needed.
- **Menu bar readout** with the profile letter, temperature and fan speed. Left-click moves to the next profile; right-click opens a menu to pick a profile, open Settings or quit.
  - Two layouts: one line (`P 52° 5330`), or two small stacked lines in the style of TG Pro (fan speed above the temperature, or the other way round).
  - The profile letter can be split off into its own menu bar item: click the letter to switch profiles, click the readout for the menu.
  - Optional second temperature, and optional colour when it gets hot (orange from 85 °C, red from 95 °C).
- **Four profile types**
  - **Auto**: FanShift does not touch the fans. The system is in control, so the fans can stop when idle.
  - **Temperature**: follows a curve. Presets for Silence, Performance and Turbo are included.
  - **Full Blast**: full speed, with an optional timer (1–60 minutes) that hands the fans back to the system.
  - **Cooldown**: full speed until the average chip temperature drops below a target, then hands the fans back.
- **Curve editor**: drag points on a 5 °C / 5 % grid, right-click a point to delete it, and drag a point into the Stop zone to leave that temperature range to the system. A marker shows where the current temperature sits on the curve.
- **Sensors tab** that lists every temperature sensor, refreshed every 2 seconds.
- The last profile is restored after a restart, and FanShift can start at login.

## Install

FanShift is built from source. You need the Xcode Command Line Tools (Swift 5.9 or later).

```bash
git clone https://github.com/KrisWonka/FanShift.git
cd FanShift
bash scripts/build-app.sh --install
```

This builds the app, copies it to `/Applications` and starts it. On first launch FanShift asks to install its background helper, which needs your admin password once.

### Coming from tgpro-hotkey-mac

```bash
bash scripts/cutover-from-tgpro.sh
```

The script installs FanShift, quits TG Pro and sets its fan control back to the system default, and disables the old `tgpro-hotkey` script in Hammerspoon. Every change is backed up first, and `scripts/rollback-to-tgpro.sh <backup folder>` undoes it. On first launch FanShift picks up your existing profiles and curves.

## How it works

FanShift is two processes:

| Process | Runs as | Job |
|---|---|---|
| `FanShift.app` | you | Hotkey, menu bar and settings. Every 2 seconds it reads the temperatures and works out a target speed for the current profile. |
| `fanshiftd` | root, started by launchd | Writes the target speed to the fans. It exposes three operations over XPC: report its version and the fan range, set target speeds, and release the fans. |

Writing fan speeds to the SMC requires root, and that is the only reason the helper exists. All the curve logic stays in the unprivileged app.

**Lease.** Each command from the app carries a 10-second lease, renewed every 2 seconds. If the helper stops hearing from the app, it hands the fans back to the system.

**Curves.** By default a curve is a staircase: once the temperature passes a point, that point's percentage applies until the next point is passed. A change of level is spread over about 10 seconds. 0 % is the fan's minimum speed and 100 % is its maximum. A linear mode that interpolates between points is available in Settings.

**Reference temperature.** A Temperature profile follows the hottest CPU core by default, minus 2 °C and lightly smoothed. I chose these values by logging FanShift next to TG Pro on the same curve: across 216 samples where TG Pro had settled on a level, FanShift picked the same level every time. That comparison only covers temperatures up to about 60 °C. The offset can be changed in Settings, and each profile can follow a different sensor.

More detail is in [docs/design.md](docs/design.md) (in Chinese).

## Safety

| Situation | What happens |
|---|---|
| The app quits, crashes or hangs | The helper releases the fans when the connection drops, or after 10 seconds at the latest. |
| The helper crashes | launchd restarts it. On start it sees that it was holding the fans and releases them. |
| The Mac goes to sleep | The fans are released before sleep and taken over again after wake. |
| No temperature reading | A Temperature profile hands the fans back to the system. |
| The hottest core reaches 95 °C in a Temperature profile | Full speed, whatever the curve says. |
| A target speed outside the fan's range | The helper clamps it to the range the fan reports. |
| Another app is controlling the fans | FanShift only releases fans that it took over itself. |

Two things to know before installing:

- The app is ad-hoc signed and not notarized.
- The helper accepts connections from root and from the user logged in at the console. It cannot check that the caller really is FanShift, so any process running as you could ask it to speed the fans up or slow them down, within the fan's own range.

## Compatibility

- **M5 Pro MacBook Pro (Mac17,9), macOS 27**: tested. Two fans, 2317–7826 RPM.
- **M1–M4**: written, **not yet tested on real hardware**. These chips need an extra step before the fans can be taken over: when the system's thermal manager is holding a fan, FanShift sets the `Ftst` key to 1, retries for up to 10 seconds, and sets it back to 0 when it hands the fans back. The same sequence is used by [chill](https://github.com/adriangalilea/chill), [smctl](https://github.com/leaperone/smctl) and [MacFanControl](https://github.com/raminsharifi/MacFanControl) (all MIT). If you have one of these Macs, a [hardware report](https://github.com/KrisWonka/FanShift/issues/new?template=hardware-report.md) would help a lot, whether it works or not.
- **Intel Macs**: not supported.

The package targets macOS 14 or later.

## Uninstall

```bash
bash scripts/uninstall.sh
```

This quits the app, returns the fans to the system, and removes the helper and the app. Your configuration in `~/Library/Application Support/FanShift` is kept.

## Development

```bash
swift test                                        # unit tests
swift build && .build/debug/fanshiftctl status    # print fans and temperatures
bash scripts/dev-sandbox.sh                       # run an isolated copy that never touches the fans
```

| Target | What it is |
|---|---|
| `CSMC` | C wrapper around the AppleSMC user client |
| `FanShiftCore` | Curves, the profile state machine, configuration, sensors, and the takeover / release logic used by the helper |
| `fanshiftd` | The root helper |
| `FanShiftApp` | The menu bar app |
| `fanshiftctl` | Command-line diagnostics: `status`, `sensors`, `shadow` (compute targets without writing them, next to the real fan targets), `helper info` |

The unit tests cover the curve math, the profile state machine, the helper's takeover and release logic, configuration decoding and the menu bar layout. They run without touching hardware.

## License

MIT
