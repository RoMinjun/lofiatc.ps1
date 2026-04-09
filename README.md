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

---

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
- **git** *(for installing repo)*:
    Install with:
    - Windows: `winget install --id Git.Git -e --source winget`
    - Debian based distros: `sudo apt install git`
- **fzf** *(Optional, but recommended)*:  
  Install with:
  - Windows: `winget install --id=junegunn.fzf -e`
  - Debian based distros: `sudo apt install fzf`

### Optional preflight check
After cloning the repo, you can verify required tools and optional integrations with:

```powershell
.\lofiatc.ps1 -CheckDependencies
```

This prints a dependency report and exits without starting playback.

Useful variations:
```powershell
.\lofiatc.ps1 -CheckDependencies -UseFZF
.\lofiatc.ps1 -CheckDependencies -ShowMap
.\lofiatc.ps1 -CheckDependencies -Player VLC
```

`-CheckDependencies` reports:
- supported media players found in `PATH`
- optional tools like `fzf`, `yt-dlp`, and `youtube-dl`
- local files such as `config.json`, `favorites.json`, and ATC source CSVs
- optional network/service checks for airport and weather endpoints

---

## Install
Clone the repository locally to get started:
```powershell
git clone https://github.com/RoMinjun/lofiatc.ps1.git
cd lofiatc.ps1
```
> [!IMPORTANT]
> Keep it updated with `git pull`.

> [!NOTE]
> If you prefer the older, lightweight `lofiatc.ps1` without the new features, switch to the `legacy` branch in this repository.

<br>

## Run
### Windows (PowerShell)
```powershell
.\lofiatc.ps1
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
pwsh ./lofiatc.ps1
```
> [!TIP]
> If `pwsh` isn’t in your PATH, install from https://aka.ms/pscore6

<br>

## Usage Recipes
```powershell
# Interactive (auto-detect player, show menus)
.\lofiatc.ps1

# Use fuzzy finder to pick an airport, open its radar, tweak volumes
.\lofiatc.ps1 -UseFZF -OpenRadar -ATCVolume 70 -LofiVolume 45

# Load your last-used settings, but override to open radar this time
.\lofiatc.ps1 -LoadConfig -OpenRadar

# Force a specific player
.\lofiatc.ps1 -Player mpv
.\lofiatc.ps1 -Player vlc

# Open the interactive ATC map in your browser
.\lofiatc.ps1 -ShowMap

# Open the map faster by skipping live weather fetch
.\lofiatc.ps1 -ShowMap -NoWeather

# Open the map in dark mode
.\lofiatc.ps1 -ShowMap -Dark

# Show the map centered around your current location, with nearby airport context
.\lofiatc.ps1 -ShowMap -Nearby

# Open the map and include webcam-enabled feeds where available
.\lofiatc.ps1 -ShowMap -IncludeWebcamIfAvailable

# Nearby airport selection without the map
.\lofiatc.ps1 -Nearby

# Nearby airport selection with a custom radius in kilometers
.\lofiatc.ps1 -Nearby -NearbyRadius 250

# Check required and optional dependencies without starting playback
.\lofiatc.ps1 -CheckDependencies

# Check dependencies for the fzf flow
.\lofiatc.ps1 -CheckDependencies -UseFZF

# Check dependencies for the map flow
.\lofiatc.ps1 -CheckDependencies -ShowMap

# Check whether a specific player is available
.\lofiatc.ps1 -CheckDependencies -Player VLC
```

> [!TIP]
> The interactive map feature works best when your terminal stays open while the browser tab is active.

To explore all features:
```powershell
Get-Help .\lofiatc.ps1 -Full
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
| `-SaveConfig`   | switch    | false   | Saves the current flags/values to `config.json`. |
| `-LoadConfig`   | switch    | false   | Loads options from `config.json`. CLI flags override loaded values. |
| `-ConfigPath`   | string    | `./config.json` | Custom path for saving/loading. |
| `-UseBaseCSV`   | switch    | false   | Force using the base `atc_sources.csv` even if a local updated file exists. |
| `-ICAO`         | string    | none    | Select a specific airport by ICAO code. If multiple channels exist, you’ll be prompted unless `-RandomATC` is used. |
| `-Nearby`       | switch    | false   | Uses your current location to show or select nearby airports. |
| `-NearbyRadius` | int       | `500`   | Radius in kilometers used with `-Nearby`. |
| `-ShowMap`      | switch    | false   | Opens an interactive browser map of available ATC sources. |
| `-NoWeather`    | switch    | false   | Skips live weather/METAR fetching for the map to improve load speed. |
| `-Dark`         | switch    | false   | Starts the interactive map in dark mode. |
| `-NoLofiMusic`  | switch    | false   | Disables the lofi stream and only plays ATC audio. |
| `-IncludeWebcamIfAvailable` | switch | false | Includes webcam-enabled feeds when available. |
| `-CheckDependencies` | switch | false | Prints a dependency report and exits without starting playback. Useful for validating players, optional tools, files, and service reachability. |

> [!TIP]
> Switches are boolean, just include them (no `true/false` needed). CLI overrides always win over loaded config.

<br>

## Configuration
Easily persist your favorite command-line options and reuse them across sessions by saving to or loading from a JSON file.

**Save your settings**
```powershell
.\lofiatc.ps1 -UseFZF -OpenRadar -ATCVolume 70 -LofiVolume 45 -SaveConfig
```

**Load saved settings**
```powershell
.\lofiatc.ps1 -LoadConfig
```

**Custom file path**
```powershell
.\lofiatc.ps1 -LoadConfig -ConfigPath "C:\work\lofiatc.json"
```

**Command-line overrides**
Even if your config has `OpenRadar: false`, you can re-enable it with:
```powershell
.\lofiatc.ps1 -LoadConfig -OpenRadar
```

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
Each time you select a stream, its ICAO and channel are recorded in `favorites.json` beside the script. The file tracks how many times you've listened to each stream and keeps the ten most frequently used entries.

- Use `-UseFavorite` to pick from this list (combine with `-UseFZF` to search within favorites).
- Streams chosen with `-RandomATC` aren't saved to the favorites list.

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

- Run `tools/UpdateATCSources.ps1` to generate/refresh a **local** `atc_sources.csv`. By default it'll be called `liveatc_sources.csv`. This overrides the current `liveatc_sources.csv` file.
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
.\lofiatc.ps1 -Player mpv
.\lofiatc.ps1 -Player vlc
```

<br>

## Interactive Map

Use `-ShowMap` to open an interactive browser map of all available ATC sources.

### What it does
- Opens a local HTML map in your browser
- Lets you search by ICAO, city, or country
- Shows active ATC sources as clickable markers
- Optionally overlays live weather categories and wind arrows
- Can highlight webcam-enabled feeds when available
- Can center the map around your current location when used with `-Nearby`

### Useful combinations
```powershell
.\lofiatc.ps1 -ShowMap
.\lofiatc.ps1 -ShowMap -NoWeather
.\lofiatc.ps1 -ShowMap -Dark
.\lofiatc.ps1 -ShowMap -Nearby -NearbyRadius 300
.\lofiatc.ps1 -ShowMap -IncludeWebcamIfAvailable
```

<br>

## Dependency Check
Use `-CheckDependencies` to verify the current environment before running the full script.

```powershell
.\lofiatc.ps1 -CheckDependencies
```

### What it checks
- supported media players available in `PATH`
- optional tools such as `fzf`, `yt-dlp`, and `youtube-dl`
- ATC source CSV availability
- `config.json` / `favorites.json` presence and JSON validity
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
- **macOS/Linux:** Run with `pwsh`. On these platforms the script auto-detects **mpv** or **vlc** when `-Player` is omitted.
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
- **Map opens but clicking a channel does nothing:** make sure the PowerShell window is still running in the background; the browser talks back to a temporary local listener started by the script.
- **Map selection feels stuck:** return to the terminal and press `Q` to cancel the map selection flow.
- **Nearby airport lookup fails:** location access may be unavailable on your device; the script falls back to IP-based lookup, which is approximate.
- **No nearby airports found:** try increasing `-NearbyRadius`, for example `-NearbyRadius 1000`.
- **Not sure what is missing on your system?** Run `.\lofiatc.ps1 -CheckDependencies` to print a dependency report without starting playback.

<br>

## Clean Up / Uninstall
You can safely delete the repo folder. Optional user files created:
- `favorites.json`
- `config.json`
- locally updated `liveatc_sources.csv`

<br>

## License
The source code in this repository is licensed under the MIT License. See
[LICENSE](./LICENSE).

## Third-Party Notice
This project may reference third-party services and content, including
LiveATC.net. Such third-party content is not covered by this repository's
license. See [NOTICE](./NOTICE).

## Contributing
PRs welcome! Popular contributions:
- New/updated ATC sources. Please add to `atc_sources.csv`, let the script update the rest.
- Better player detection across platforms
- Additional examples / docs improvements

---

## Support LiveATC
This project depends on the existence of [liveatc.net](https://www.liveatc.net).  
If you live near an airport and have a passion for air traffic control, and if it's legal in your country, consider [contacting LiveATC.net](https://www.liveatc.net/ct/contact.php) about hosting a feed.
