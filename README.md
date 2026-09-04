<div align="center">

# lofiatc.ps1
An alternative to [lofiatc](https://www.lofiatc.com) built with PowerShell and designed to be cross-platform (Linux, macOS, and Windows). This script integrates multimedia players like VLC, PotPlayer, MPC-HC, or mpv, enabling you to simultaneously enjoy Lofi Girl and live Air Traffic Control streams from around the world.

![](https://i.redd.it/8suf7s5ywqad1.jpeg)

</div>

<br>

<div align="center">

  
## Choose Your Player
![Made with VHS](https://vhs.charm.sh/vhs-6EK95qMAl6yhRH7quA7NEq.gif)

## Search Your Favorite Airport Using Fuzzy Finder!
![Fuzzy Finder](https://vhs.charm.sh/vhs-7lxh0VxsJv8tYkQhI6iEVl.gif)

## OR Without Fuzzy Finder...
![Made with VHS](https://vhs.charm.sh/vhs-2sTPLAkHZ0nzVtAdCifMT3.gif)

## Airport Info at Your Fingertips! 
![Made with VHS](https://vhs.charm.sh/vhs-27zfUBvX3O7fPkWiFHe3T1.gif)

## Select your favorite airport via the map!
![show sources map](https://raw.githubusercontent.com/RoMinjun/images/main/lofiatc.ps1/show-sources-map.gif)

## Current Map Experience

| Search, weather, and filters | Persistent playback and Lofi track OCR |
|:---:|:---:|
| ![Dark map centered on Switzerland with live weather markers and map filters](https://raw.githubusercontent.com/RoMinjun/images/main/lofiatc.ps1/map-search-switzerland.jpg) | ![Persistent map showing the active airport and detected Lofi Girl track](https://raw.githubusercontent.com/RoMinjun/images/main/lofiatc.ps1/persistent-playback-ocr.jpg) |
| Search by airport, ICAO, city, country, or channel while retaining live weather context. | Keep the map open while switching ATC channels and viewing the detected Lofi Girl track. |

---
<br>

![Made with VHS](https://vhs.charm.sh/vhs-1LOxW9YtwAj6V4n7FfNSAh.gif)



<br>

# **Getting Started**

</div>

<br>

## Contents
1. [Requirements](#requirements)
2. [Install](#install)
3. [Run](#run)
4. [Usage Recipes](#usage-recipes)
5. [Parameters (Quick Reference)](#parameters-quick-reference)
6. [Configuration](#configuration)
7. [Favorites](#favorites)
8. [Airport Sources](#airport-sources)
9. [Player Selection](#player-selection)
10. [Interactive Map](#interactive-map)
11. [Dependency Check](#dependency-check)
12. [Platform Notes](#platform-notes)
13. [Troubleshooting](#troubleshooting)
14. [Clean Up / Uninstall](#clean-up--uninstall)
15. [Contributing](#contributing)
16. [Support LiveATC](#support-liveatc)

<br>

## Requirements
Ensure you have the following installed before running the script:
- **PowerShell 5.1 or later**
- **A Multimedia Player** (choose one or multiple of the following):
  - **VLC Media Player**:  
    Install with:
    - Windows `winget install --id VideoLAN.VLC -e`
    - Debian based distros: `sudo apt install vlc`
  - **Potplayer**:  
    Install with: `winget install potplayer --id Daum.PotPlayer -s winget`
  - **MPC-HC**:  
    Install with: `winget install MPC-HC --id clsid2.mpc-hc`
  - **MPV**:  
    Install with:
    - Windows: `scoop install mpv` or via [mpv.io](https://mpv.io/installation/)
    - Debian based distros: `sudo apt install mpv`
- **yt-dlp** *(recommended for resolving YouTube-backed sources more reliably)*:
    Install with:
    - Windows: `winget install --id=yt-dlp.yt-dlp -e`
    - Debian based distros: `sudo apt install yt-dlp`
- **ffmpeg and Tesseract OCR** *(optional, required for `-ShowLofiTrack`)*:
    - Windows: install Tesseract with `winget install --id tesseract-ocr.tesseract`. Install ffmpeg with your preferred package manager and ensure it is in `PATH`. Tesseract is detected from `PATH`, its installer registration, common standalone/Scoop locations, or its WinGet package directory.
    - macOS: `brew install ffmpeg tesseract`
    - Debian based distros: `sudo apt install ffmpeg tesseract-ocr`
- **git** *(for installing repo)*:
    Install with:
    - Windows: `winget install --id Git.Git -e --source winget`
    - Debian based distros: `sudo apt install git`
- **fzf** *(Optional, but recommended)*:  
  Install with:
  - Windows: `winget install --id=junegunn.fzf -e`
  - Debian based distros: `sudo apt install fzf`
---

## Install
Install the `lofiatc` PowerShell command:
```powershell
irm https://raw.githubusercontent.com/RoMinjun/lofiatc.ps1/main/install.ps1 | iex
```

> [!NOTE]
> If you wish to install a branch other than `main`, you can do that by passing `-Ref` followed by the branch name, see following example for `test` branch:
> ```powershell
> & ([scriptblock]::Create((irm https://raw.githubusercontent.com/RoMinjun/lofiatc.ps1/feature/install-module-command/install.ps1))) -Ref test
> ```

Open a new PowerShell session after installation, then run:
```powershell
lofiatc
```

### Optional preflight check
After installing, you can verify required tools and optional integrations with:

```powershell
lofiatc -CheckDependencies
```

This prints a dependency report and exits without starting playback.

Useful variations:
```powershell
lofiatc -CheckDependencies -UseFZF
lofiatc -CheckDependencies -ShowMap
lofiatc -CheckDependencies -Player VLC
```

`-CheckDependencies` reports:
- supported media players found in `PATH`
- optional tools like `fzf`, `yt-dlp`, and `youtube-dl`
- local files such as `config.json`, `favorites.json`, and ATC source CSVs
- the airport metadata cache and optional network/service checks for airport and weather endpoints

The installer copies the app files to a per-user install directory and installs a small PowerShell module command named `lofiatc`. That command preserves PowerShell help and tab completion on Windows, macOS, and Linux:
```powershell
Get-Help lofiatc -Full
lofiatc -Player <Tab>
lofiatc -LofiGenre <Tab>
```

Install locations:
- Windows app files: `$env:LOCALAPPDATA\lofiatc`
- macOS/Linux app files: `~/.local/share/lofiatc`
- macOS/Linux shell launcher: `~/.local/bin/lofiatc`

On macOS/Linux, the shell launcher lets you run `lofiatc` from bash/zsh/fish. PowerShell-native help and rich tab completion are available inside `pwsh`.

The installer also adds a marked `Import-Module LofiATC` line to your PowerShell profile so `lofiatc` resolves to the module function in new `pwsh` sessions. Use `-SkipPowerShellProfile` if you prefer to manage profile imports yourself.

Refresh the weekly LiveATC source list:
```powershell
lofiatc -UpdateSources
```

The update prints the exact source commit hash as a clickable GitHub link in supported terminals, then lists added and removed entries compared to the previously installed `liveatc_sources.csv`. Terminals without hyperlink support show the GitHub URL next to the hash. The hash is still shown when there are no source changes. By default it shows up to 50 added and 50 removed entries:
```powershell
lofiatc -UpdateSources -SourceDiffLimit 100
lofiatc -UpdateSources -SourceDiffLimit 0   # show all changes
```

Source updates use the repository ref recorded during install. You can override it explicitly:
```powershell
lofiatc -UpdateSources -Ref feature/install-module-command
```

Update the installed app files:
```powershell
Update-LofiATC
```

The updater prints the commit hash as a clickable GitHub link in supported terminals after the update. Installer-based updates use the
repository and ref recorded during installation unless `-Repository` or `-Ref` is supplied.

Show the installed commit, ref, repository, and installation paths:
```powershell
lofiatc -Version
# or
Get-LofiATCVersion
```

Installs and updates are staged and validated before the active app and module directories are replaced. If committing the new installation fails, the previous directories are restored. Replacing the directories also removes files that no longer exist in the current package.

You can still clone the repository locally for development:
```powershell
git clone https://github.com/RoMinjun/lofiatc.ps1.git
cd lofiatc.ps1
```

> [!NOTE]
> If you prefer the older, lightweight `lofiatc.ps1` without the new features, switch to the `legacy` branch in this repository. But keep in mind that this branch is considered deprecated.

<br>

## Run
### Windows (PowerShell)
```powershell
lofiatc
```

If PowerShell blocks the script, use one of these:
```powershell
# One-time relaxed policy for the current user
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# OR run once with a bypass
powershell -ExecutionPolicy Bypass -File .\lofiatc.ps1
```

### macOS / Linux (PowerShell Core)
```bash
lofiatc
```
> [!TIP]
> If `pwsh` isn’t in your PATH, install from https://aka.ms/pscore6

<br>

## Usage Recipes
```powershell
# Interactive (auto-detect player, show menus)
lofiatc

# Use fuzzy finder to pick an airport, open its radar, tweak volumes
lofiatc -UseFZF -OpenRadar -ATCVolume 70 -LofiVolume 45

# Load your last-used settings, but override to open radar this time
lofiatc -LoadConfig -OpenRadar

# Save and reuse a named setup; explicit values still override the profile
lofiatc -SaveProfile Work -ATCVolume 70
lofiatc -Profile Work -ATCVolume 80

# List or remove named profiles without starting playback
lofiatc -ListProfiles
lofiatc -RemoveProfile Work

# Force a specific player
lofiatc -Player mpv
lofiatc -Player vlc

# Open the interactive ATC map in your browser
lofiatc -ShowMap

# Open the map faster by skipping live weather fetch
lofiatc -ShowMap -NoWeather

# Open the map in dark mode
lofiatc -ShowMap -Dark

# Show the map centered around your current location, with nearby airport context
lofiatc -ShowMap -Nearby

# Open the map and include webcam-enabled feeds where available
lofiatc -ShowMap -IncludeWebcamIfAvailable

# Monitor ATC playback and retry an interrupted or expired stream
lofiatc -ICAO EHAM -AutoRecover -RetryCount 3

# Let later retries try another channel at the same airport
lofiatc -ICAO EHAM -AutoRecover -RecoverAlternateChannel

# Show the current Lofi Girl track using OCR in persistent map mode
lofiatc -ShowMap -KeepOpen -ShowLofiTrack

# Nearby airport selection without the map
lofiatc -Nearby

# Nearby airport selection with a custom radius in kilometers
lofiatc -Nearby -NearbyRadius 250

# Check required and optional dependencies without starting playback
lofiatc -CheckDependencies

# Check dependencies for the fzf flow
lofiatc -CheckDependencies -UseFZF

# Check dependencies for the map flow
lofiatc -CheckDependencies -ShowMap

# Check whether a specific player is available
lofiatc -CheckDependencies -Player VLC
```

> [!TIP]
> The interactive map feature works best when your terminal stays open while the browser tab is active.

To explore all features:
```powershell
Get-Help .\lofiatc.ps1 -Full
Get-Help lofiatc -Full
```

<br>

## Parameters (Quick Reference)
| Parameter       | Type      | Default | What it does |
|-----------------|-----------|---------|--------------|
| `-Player`       | string    | auto    | Choose `vlc`, `mpv`, `potplayer`, or `mpc-hc`. Auto-detects cross-platform. |
| `-UseFZF`       | switch    | false   | Use **fzf** for fuzzy airport search. |
| `-UseFavorite`  | switch    | false   | Pick from your top 10 most-played favorites. (Works with `-UseFZF`.) |
| `-RandomATC`    | switch    | false   | Start a random ATC stream (not added to favorites). |
| `-OpenRadar`    | switch    | false   | Opens the selected airport’s FlightAware radar in your browser. |
| `-ATCVolume`    | int 0–100 | `65`    | ATC stream volume. |
| `-LofiVolume`   | int 0–100 | `50`    | Lofi Girl volume. |
| `-LofiSource`   | string    | Lofi Girl YouTube stream | Custom URL or file path for the lofi audio/video source. |
| `-LofiGenre`    | string    | none    | Choose a built-in lofi genre preset. Ignored when `-LofiSource` is supplied. |
| `-PlayLofiGirlVideo` | switch | false | Plays the Lofi Girl video instead of audio-only lofi playback. |
| `-ShowLofiTrack` | switch | false | Uses OCR to show the current Lofi Girl track in persistent map mode. Requires `-ShowMap -KeepOpen`, yt-dlp or youtube-dl, ffmpeg, and Tesseract OCR. |
| `-SaveConfig`   | switch    | false   | Saves the current flags/values to your user `config.json`. |
| `-LoadConfig`   | switch    | false   | Loads options from your user `config.json`. CLI flags override loaded values. |
| `-ConfigPath`   | string    | user data path | Custom path for saving/loading. |
| `-Profile`      | string    | none    | Loads a named profile from the user data directory. CLI flags override profile values. |
| `-SaveProfile`  | string    | none    | Saves the current flags/values and selected ATC channel as a named profile. |
| `-ListProfiles` | switch    | false   | Lists saved profiles and exits without starting playback. |
| `-RemoveProfile` | string   | none    | Removes a named profile and exits without starting playback. |
| `-UseBaseCSV`   | switch    | false   | Force using the base `atc_sources.csv` even if a local updated file exists. |
| `-ICAO`         | string    | none    | Select a specific airport by ICAO code. If multiple channels exist, you’ll be prompted unless `-RandomATC` is used. |
| `-Nearby`       | switch    | false   | Uses your current location to show or select nearby airports. |
| `-NearbyRadius` | int       | `500`   | Radius in kilometers used with `-Nearby`. |
| `-ShowMap`      | switch    | false   | Opens an interactive browser map of available ATC sources. |
| `-NoWeather`    | switch    | false   | Skips live weather/METAR fetching for the map to improve load speed. |
| `-Dark`         | switch    | false   | Starts the interactive map in dark mode. |
| `-KeepOpen` / `-Persistent` | switch | false | Keeps the interactive map open after selecting a channel so you can make repeated selections. |
| `-AutoRecover` | switch | false | Monitors the managed ATC player and retries failed starts or unexpected exits. Keeps a non-map terminal session open until cancelled. |
| `-RetryCount` | int 1–10 | `3` | Maximum recovery attempts when `-AutoRecover` is enabled. |
| `-RecoverAlternateChannel` | switch | false | Allows later recovery attempts to try another channel at the same airport. Requires `-AutoRecover`. |
| `-NoLofiMusic`  | switch    | false   | Disables the lofi stream and only plays ATC audio. |
| `-IncludeWebcamIfAvailable` | switch | false | Includes webcam-enabled feeds when available. |
| `-CheckDependencies` | switch | false | Prints a dependency report and exits without starting playback. Useful for validating players, optional tools, files, and service reachability. |
| `-UpdateSources` | switch | false | Refreshes the installed `liveatc_sources.csv` and exits. Available from the installed `lofiatc` command. |
| `-Version` | switch | false | Shows the installed repository, ref, commit, timestamp, and installation paths, then exits. |
| `-SourceDiffLimit` | int | `50` | Limits added/removed source rows printed by `-UpdateSources`. Use `0` to show all. |
| `-Ref` | string | installed ref | Repository ref used by `-UpdateSources`. Available from the installed `lofiatc` command. |
| `-Repository` | string | installed repository | GitHub `owner/repo` used by `-UpdateSources`. Available from the installed `lofiatc` command. |

CLI parity tests intentionally exclude the installed-command-only parameters `-UpdateSources`, `-Version`, `-SourceDiffLimit`, `-Ref`, and `-Repository`; every other declared parameter is required to match `lofiatc.ps1`.

> [!TIP]
> Switches are boolean, just include them (no `true/false` needed). CLI overrides always win over loaded config.

<br>

## Configuration
Easily persist your favorite command-line options and reuse them across sessions by saving to or loading from a JSON file.

**Save your settings**
```powershell
lofiatc -UseFZF -OpenRadar -ATCVolume 70 -LofiVolume 45 -SaveConfig
```

**Load saved settings**
```powershell
lofiatc -LoadConfig
```

**Custom file path**
```powershell
lofiatc -LoadConfig -ConfigPath "C:\work\lofiatc.json"
```

**Command-line overrides**
Even if your config has `OpenRadar: false`, you can re-enable it with:
```powershell
lofiatc -LoadConfig -OpenRadar
```

Configuration and profile files are written through a validated temporary file before replacement. When an existing file is valid, its previous contents are retained in a neighboring `.bak` file. If the active JSON becomes malformed, LofiATC warns and attempts to load the last-known-good backup without modifying the damaged file. A later save preserves malformed JSON in a uniquely named `.corrupt-*.bak` file before replacing it.

### Offline airport data

Airport metadata used by the map, nearby-airport selection, local time, and sunrise/sunset features is cached as `airport-data-cache.json` in the user data folder. A cache is considered fresh for seven days. After that, LofiATC attempts a bounded refresh and uses the stale last-known-good cache if the service is unavailable. If the active cache is malformed, a valid neighboring `.bak` cache can be used instead.

The first airport-data request still needs network access when no cache exists. Optional IP location, METAR, and sunrise/sunset failures return unavailable data without stopping unrelated ATC or lofi playback. Run `lofiatc -Verbose` to see whether airport data came from the live service, active cache, backup fallback, or was unavailable; `lofiatc -CheckDependencies` reports the current cache path, source, and age.

### Automatic ATC recovery

Use `-AutoRecover` to keep the selected ATC process under supervision. Failed starts and unexpected player exits are retried with delays of 1, 2, 4, and then up to 30 seconds, bounded by `-RetryCount`. Each retry resolves the configured stream URL again before launching the player. `-RecoverAlternateChannel` lets successive attempts rotate through other configured channels for the same ICAO.

Outside persistent map mode, recovery monitoring keeps the terminal command active; press Ctrl+C to stop it. Deliberate **Stop ATC** and **Stop All** map actions disable recovery until you restart or select a channel. Persistent map mode displays recovering, recovered, and exhausted states in Now Playing. Lofi and webcam processes are not treated as ATC recovery attempts.

### Named profiles

Named profiles let you keep several reusable setups while preserving the existing `config.json` behavior. Profile names are 1–64 letters, numbers, underscores, or hyphens and must start with a letter or number.

```powershell
# Create or replace a profile, then choose the channel to remember
lofiatc -SaveProfile Work -ATCVolume 70 -LofiVolume 45

# Load it; the explicit volume wins over the saved value
lofiatc -Profile Work -ATCVolume 80

# Manage profiles without launching players or a browser
lofiatc -ListProfiles
lofiatc -RemoveProfile Work
```

The selected ATC channel is saved with the profile, so `-Profile Work` can start that feed without asking for a channel again. If the saved feed is no longer available, LofiATC warns and falls back to the normal selection flow. Explicit selection modes such as `-RandomATC`, `-Nearby`, `-ShowMap`, and `-UseFavorite` take precedence over the saved channel.

The installed PowerShell command completes saved names for `-Profile`, `-SaveProfile`, and `-RemoveProfile`. Named profiles are written through a validated temporary file before replacement and are stored in the `profiles` subdirectory of the user data folder.

By default, installed runs store `config.json`, `favorites.json`, and named profiles in your user data folder:
- Windows: `$env:APPDATA\lofiatc`
- macOS/Linux: `$XDG_CONFIG_HOME/lofiatc` or `~/.config/lofiatc`

**Example `config.json`**
```json
{
  "Player": "mpv",
  "UseFZF": true,
  "OpenRadar": true,
  "ATCVolume": 70,
  "LofiVolume": 45
}
```

<br>

## Favorites
Each time you select a stream, its ICAO and channel are recorded in your user `favorites.json`. The file tracks how many times you've listened to each stream and keeps the ten most frequently used entries.

- Use `-UseFavorite` to pick from this list (combine with `-UseFZF` to search within favorites).
- Streams chosen with `-RandomATC` aren't saved to the favorites list.
- Favorites writes use the same validated replacement and backup behavior as configuration files. If `favorites.json` is malformed, LofiATC warns and uses `favorites.json.bak` when it is valid; damaged JSON is preserved before any later write.

**Example `favorites.json`**
```json
[
  {
    "ICAO": "RJAA",
    "Channel": "RJAA Tower (Both)",
    "Count": 1,
    "LastUsed": "2025-08-11T22:24:38.3289048+02:00"
  },
  {
    "ICAO": "EHAM",
    "Channel": "EHAM Tower (Rwy 18R/36L)",
    "Count": 1,
    "LastUsed": "2025-08-11T22:24:26.5105686+02:00"
  }
]
```

<br>

## Airport Sources
The script reads ATC streams from `atc_sources.csv`.

> [!IMPORTANT]
> ~~Don't try manually update the sources. LiveATC has added a challenge page, so for now the update script doesn't work. Working on a fix.~~ A workaround is to use [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr), but to keep it stealthy each request would take around 8 seconds (So it can take up hours to fully update the sources). So I wouldn't recommend trying to update yourself anymore. Instead I'll publish a more recent version every now and then. But if you really wish to update yourself, check the steps below.

- Run `lofiatc -UpdateSources` to refresh the installed weekly `liveatc_sources.csv`. The command prints added and removed sources compared to the currently installed CSV.
- For development, run `tools/UpdateATCSources.ps1` to generate/refresh a local `liveatc_sources.csv` by default. Use `-OutputCsvPath` for a custom output path or `-InPlace` with `-SortOnly` to rewrite the input CSV.
- If a locally updated CSV exists, it is **preferred** over the `liveatc_sources.csv`.  
- Use `-UseBaseCSV` to ignore `liveatc_sources.csv` and use the base CSV.

#### Updating sources
Download the [FlareSolverr binary from GitHub](https://github.com/FlareSolverr/FlareSolverr/releases). Run the binary and accept any pop ups. Then run the `UpdateATCSources.ps1` script as per usual.

```powershell
# From <projectroot>/tools
.\UpdateATCSources.ps1
```

> [!IMPORTANT]
> The base `atc_sources.csv` must not be deleted; both scripts rely on it.

<br>

## Player Selection
If `-Player` is not specified, the script auto-detects a supported player.
- On **Windows**, it first checks the default app for `.mp4` and uses it if it is supported and available in `PATH`.
- If no supported default app is available, it falls back to the first supported installed player.
- On **non-Windows systems**, it prefers **MPV** first, then **VLC**.

Force a specific player any time:
```powershell
lofiatc -Player mpv
lofiatc -Player vlc
```

<br>

## Interactive Map

Use `-ShowMap` to open an interactive browser map of all available ATC sources.

### What it does
- Opens a local HTML map in your browser
- Uses keyless [OpenFreeMap](https://openfreemap.org/) light and dark vector basemaps, with a standard OpenStreetMap fallback when WebGL is unavailable
- Lets you search by ICAO, city, or country
- Shows active ATC sources as clickable markers
- Optionally overlays live weather categories and wind arrows
- Can highlight webcam-enabled feeds when available
- Can center the map around your current location when used with `-Nearby`

### Useful combinations
```powershell
lofiatc -ShowMap
lofiatc -ShowMap -NoWeather
lofiatc -ShowMap -Dark
lofiatc -ShowMap -Nearby -NearbyRadius 300
lofiatc -ShowMap -IncludeWebcamIfAvailable
```

<br>

## Dependency Check
Use `-CheckDependencies` to verify the current environment before running the full script.

```powershell
lofiatc -CheckDependencies
```

### What it checks
- supported media players available in `PATH`
- optional tools such as `fzf`, `yt-dlp`, `youtube-dl`, `ffmpeg`, and Tesseract OCR
- ATC source CSV availability
- `config.json` / `favorites.json` presence and JSON validity
- airport metadata cache availability, source, path, and age
- optional browser/map helpers such as `xdg-open` on Linux or `open` on macOS
- optional network/service checks for airport and weather data sources

### Exit behavior
- exits with code `0` when all required items are available
- exits with code `1` when required items are missing

### Notes
- network/service checks are informational and may fail temporarily even when local dependencies are installed
- `fzf` is only required when you use `-UseFZF`
- browser opener checks only matter when you use `-ShowMap`

<br>

## Platform Notes
- **macOS/Linux:** The installer creates a `~/.local/bin/lofiatc` launcher for normal shells and installs the `LofiATC` PowerShell module for `pwsh`. On these platforms the script auto-detects **mpv** or **vlc** when `-Player` is omitted.
- **macOS/Linux PATH:** If `~/.local/bin` is not in `PATH`, add it to your shell profile to run `lofiatc` from bash/zsh/fish.
- **PowerShell profile:** The installer adds `Import-Module LofiATC` to your PowerShell profile so tab completion works even when a shell launcher named `lofiatc` is also on `PATH`.
- **Windows Execution Policy:** If execution is blocked, use:
  ```powershell
  Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
  # or
  powershell -ExecutionPolicy Bypass -File .\lofiatc.ps1
  ```

<br>

## Troubleshooting
- **“Command not found: pwsh” (macOS/Linux):** install PowerShell Core; reopen your terminal.  
- **Player not found:** ensure your chosen player is in `PATH`. Try the explicit `-Player` flag.  
- **No audio / very low audio:** check OS mixer; ensure per-stream volumes aren’t set to `0`.  
- **fzf not working:** confirm `fzf` is installed and in `PATH`. Run `fzf --version`.  
- **yt-dlp errors:** update it to the latest version and retry.
- **YouTube or webcam streams not loading in player:** make sure `yt-dlp` is up to date; recent upstream changes may require extra packages depending on your platform.
- **Map opens slowly:** use `-ShowMap -NoWeather` to skip live weather fetch and load faster.
- **Airport data is unavailable:** the first map or nearby-airport request needs network access. After a successful request, LofiATC keeps a seven-day user cache and can use stale data during an outage. Run `lofiatc -CheckDependencies` for its status.
- **Map opens but clicking a channel does nothing:** make sure the PowerShell window is still running in the background; the browser talks back to a temporary local listener started by the script.
- **Map selection feels stuck:** return to the terminal and press `Q` to cancel the map selection flow.
- **Nearby airport lookup fails:** location access may be unavailable on your device; the script falls back to IP-based lookup, which is approximate.
- **No nearby airports found:** try increasing `-NearbyRadius`, for example `-NearbyRadius 1000`.
- **Not sure what is missing on your system?** Run `lofiatc -CheckDependencies` to print a dependency report without starting playback.
- **Tab completion does not show `lofiatc` parameters:** run `Get-Command lofiatc -All`. If an older `lofiatc.cmd`, `.exe`, or `.ps1` appears before the `LofiATC` function, remove the older command or add `Import-Module LofiATC` to your PowerShell profile.

<br>

## Clean Up / Uninstall
Run the uninstaller to remove the installed app files, PowerShell module, profile import, and macOS/Linux shell launcher:
```powershell
& "$env:LOCALAPPDATA\lofiatc\uninstall.ps1"
```

User data is left intact by default:
- `$env:APPDATA\lofiatc\favorites.json`
- `$env:APPDATA\lofiatc\config.json`

To remove user data too:
```powershell
& "$env:LOCALAPPDATA\lofiatc\uninstall.ps1" -RemoveUserData
```

On macOS/Linux, use the installed path:
```powershell
& "$HOME/.local/share/lofiatc/uninstall.ps1"
```

<br>

## License
The source code in this repository is licensed under the MIT License. See
[LICENSE](./LICENSE).

## Third-Party Notice
This project may reference third-party services and content, including
LiveATC.net. Such third-party content is not covered by this repository's
license. See [ACKNOWLEDGMENTS](./ACKNOWLEDGMENTS.md).

## Contributing
PRs welcome! Popular contributions:
- New/updated ATC sources. Please add to `atc_sources.csv`, let the script update the rest.
- Better player detection across platforms
- Additional examples / docs improvements

---

## Support LiveATC
This project depends on the existence of [liveatc.net](https://www.liveatc.net).  
If you live near an airport and have a passion for air traffic control, and if it's legal in your country, consider [contacting LiveATC.net](https://www.liveatc.net/ct/contact.php) about hosting a feed.
