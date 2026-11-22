# Deltarune Egg Room Boot Up

> *"(There is a tree here. Well, there is a man here, too.)"*

[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%2F%2011-0078D6?style=flat-square&logo=windows)](https://www.microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=flat-square&logo=powershell)](https://learn.microsoft.com/powershell/)
[![Wallpaper Engine](https://img.shields.io/badge/Requires-Wallpaper%20Engine-1B2838?style=flat-square&logo=steam)](https://store.steampowered.com/app/431960/Wallpaper_Engine/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

Bring **Deltarune's secret Egg Room** (*the Man Behind the Tree*) to your Windows startup.

Every time you sign into Windows, this lightweight script silently rolls a **1-in-100** chance (fully configurable). On 99% of logins, it exits invisibly in milliseconds without touching anything. On the rare boot when you roll `1`, your desktop transforms into the Egg Room:

1. **Mutes Wallpaper Engine first** so your previous wallpaper's audio never leaks.
2. **Sets Windows master volume** to `50%` (configurable) via Windows Core Audio.
3. **Hides all desktop icons** and **minimizes every open window**.
4. **Switches Wallpaper Engine** to the Man Behind the Tree wallpaper and sets its volume to `100%`.
5. **Enables Wallpaper Engine's global Audio Output** for your Windows user account if you normally keep wallpaper audio disabled (creating a backup first).
6. **Sweeps any newly opened startup windows away** and **unmutes Wallpaper Engine** as the final step — leaving you alone with the tree and its music.

---

## Features

- **True Zero-Flash Startup** — Launched via `wscript.exe` + [`Launch-EggRoom.vbs`](Launch-EggRoom.vbs), so no black PowerShell console ever flashes on boot.
- **Zero-Overhead Miss Path** — The random roll happens *before* any C# compilation or Steam discovery. Non-triggering logins finish in milliseconds.
- **Anti-Audio-Leak Sequence** — Wallpaper Engine is muted before Windows master volume is changed, and if a restart is needed to enable global audio output, the Egg Room wallpaper is selected *before* restarting so your old wallpaper never plays a single frame of audio.
- **Smart Steam Library Discovery** — Reads Steam's `libraryfolders.vdf` from the registry to locate Wallpaper Engine and Workshop content on any drive or custom library folder (with fixed-drive fallback).
- **Per-User Safe `config.json` Patching** — Only inspects and updates your current Windows account's `videoaudiooutput` setting in Wallpaper Engine's `config.json`, preserving all other settings and accounts.
- **Easy Configuration & Safe Testing** — Edit [`config.json`](config.json) without touching code, verify your setup safely with `-DryRun`, or experience the easter egg on demand with `-Force`.
- **Automatic Log Rotation** — Keeps `egg_log.txt` trimmed to the last 200 lines so it never grows unbounded.

---

## Requirements

- **Windows 10 or Windows 11** (uses built-in Windows PowerShell 5.1+, no extra modules required)
- **[Wallpaper Engine](https://store.steampowered.com/app/431960/Wallpaper_Engine/)** on Steam (set to start with Windows)
- A Deltarune Egg Room wallpaper subscribed from the Steam Workshop. Out of the box, [`config.json`](config.json) looks for either of these Workshop IDs:
  - [`3776981825`](https://steamcommunity.com/sharedfiles/filedetails/?id=3776981825) — *Forgotten Man [Egg Rooms] | DELTARUNE*
  - [`3772358586`](https://steamcommunity.com/sharedfiles/filedetails/?id=3772358586) — *Deltarune - secret egg rooms \ forgotten man tree*
  - *Want a different Egg Room (or any other) wallpaper?* Just paste its Steam Workshop ID into `workshopIds` in [`config.json`](config.json) — both Scene (`scene.pkg`) and Video/Web (`project.json`) wallpapers are supported!

---

## Quick Start

### 1. Download the repository

Clone with Git or download the latest ZIP from **[Releases](https://github.com/Slavanosik/deltarune-egg-room-boot-up/releases/latest)** (or **Code → Download ZIP**) and extract it to a permanent folder (for example, `C:\Tools\deltarune-egg-room-boot-up`):

```powershell
git clone https://github.com/Slavanosik/deltarune-egg-room-boot-up.git
cd deltarune-egg-room-boot-up
```

### 2. Verify your setup safely (Dry Run)

Run a dry run first — this checks Steam, Wallpaper Engine, your subscribed wallpaper, volume property detection, and audio settings **without changing anything**:

```powershell
powershell -ExecutionPolicy Bypass -File .\EggRoom.ps1 -DryRun
```

### 3. Test the Easter Egg live (optional)

Want to see it in action right away without waiting for a 1/100 roll?

```powershell
powershell -ExecutionPolicy Bypass -File .\EggRoom.ps1 -Force
```

> **Tip:** To bring back your desktop icons after testing, right-click the desktop → **View → Show desktop icons** (or toggle icons back on in Wallpaper Engine), then switch back to your usual wallpaper.

### 4. Register the Windows startup task

Run the installer from the extracted folder to register the silent Task Scheduler logon job (no administrator rights required for standard Steam installs):

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-EggTask.ps1
```

That's it! From now on, every time you sign into Windows, there's a 1-in-100 chance you'll find yourself behind the tree.

---

## Configuration

Edit [`config.json`](config.json) to customize behavior without modifying any script code:

```json
{
  "chance": 100,
  "systemVolumePercent": 50,
  "workshopIds": [
    "3776981825",
    "3772358586"
  ],
  "wallpaperPath": "",
  "wallpaperEnginePath": "",
  "hideDesktopIcons": true,
  "minimizeAllWindows": true,
  "enableGlobalWallpaperAudio": true,
  "maxLogLines": 200
}
```

| Option | Default | Description |
| --- | --- | --- |
| `chance` | `100` | Odds of triggering on logon (`1 / chance`). For example, `50` = 2% chance, `100` = 1% chance, `1000` = 0.1% chance. |
| `systemVolumePercent` | `50` | Windows master volume (`0`–`100`) set when triggered. Set to `null` to leave Windows volume untouched. |
| `workshopIds` | `["3776981825", "3772358586"]` | Ordered list of Steam Workshop IDs to search across your Steam libraries. |
| `wallpaperPath` | `""` | Optional direct path to a local `scene.pkg`, `project.json`, or media file (overrides `workshopIds`). |
| `wallpaperEnginePath` | `""` | Optional manual path to `wallpaper64.exe` / `wallpaper32.exe` (overrides auto-discovery). |
| `hideDesktopIcons` | `true` | Hide desktop icons via Wallpaper Engine when triggered. |
| `minimizeAllWindows` | `true` | Minimize all open windows via `Shell.Application.MinimizeAll()`. |
| `enableGlobalWallpaperAudio` | `true` | Temporarily restart Wallpaper Engine with global Audio Output enabled if it was turned off in Wallpaper Engine settings. |
| `maxLogLines` | `200` | Maximum lines retained in `egg_log.txt` (`0` disables rotation). |

### CLI Parameters

#### `EggRoom.ps1`
- `-Force` (alias `-Test`) — Bypass the RNG roll and run immediately.
- `-DryRun` — Inspect paths and configuration without modifying system state.
- `-Chance <int>` — Override `chance` for a single run.
- `-SystemVolumePercent <0..100>` — Override `systemVolumePercent` for a single run.
- `-WorkshopIds <string[]>` — Override `workshopIds` for a single run.
- `-ConfigPath <path>` — Use a custom configuration file.

#### `Install-EggTask.ps1`
- `-DelaySeconds <0..300>` — Startup delay after logon (default `10` seconds, giving Wallpaper Engine time to start).
- `-TaskName <string>` — Custom Task Scheduler name (default `Deltarune Egg Room Boot Up`).
- `-Elevated` — Register with `RunLevel Highest` (only needed if you run Wallpaper Engine as Administrator).
- `-Uninstall` — Remove the scheduled task.

---

## Repository Structure

```text
deltarune-egg-room-boot-up/
├── EggRoom.ps1          # Core script (RNG fast-path, Steam VDF discovery, audio & WE control)
├── Launch-EggRoom.vbs   # Zero-flash silent wrapper invoked by Task Scheduler
├── Install-EggTask.ps1  # Portable Task Scheduler installer & uninstaller
├── config.json          # User-editable settings
├── LICENSE              # MIT License
└── README.md
```

---

## Troubleshooting & Uninstall

- **Check the log:** Every launch records its roll and actions to `egg_log.txt` in the script folder.
- **Wallpaper Engine `config.json` backup:** If the script ever enables global Audio Output in Wallpaper Engine's `config.json`, it saves a one-time backup right next to it as `config.json.egg_backup`.
- **Wallpaper didn't switch on startup?** If your PC takes longer to launch Wallpaper Engine after sign-in, increase the startup delay:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\Install-EggTask.ps1 -DelaySeconds 20
  ```
- **Uninstall:** Remove the Task Scheduler entry cleanly with:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\Install-EggTask.ps1 -Uninstall
  ```
  Then delete the folder.

---

## Disclaimer

This is an unofficial, fan-made easter egg script inspired by **DELTARUNE** by Toby Fox. It is not affiliated with Toby Fox or Wallpaper Engine. All actions are local, transparent, and fully reversible.

## License

Licensed under the [MIT License](LICENSE).
