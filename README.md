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
![Fuzzy Finder](./assets/fzf.gif)

## OR Without Fuzzy Finder...
![Made with VHS](https://vhs.charm.sh/vhs-2sTPLAkHZ0nzVtAdCifMT3.gif)

## Airport Info at Your Fingertips! 
![Made with VHS](https://vhs.charm.sh/vhs-27zfUBvX3O7fPkWiFHe3T1.gif)

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
10. [Platform Notes](#platform-notes)
11. [Troubleshooting](#troubleshooting)
12. [Clean Up / Uninstall](#clean-up--uninstall)
13. [Contributing](#contributing)
14. [Support LiveATC](#support-liveatc)

<br>

## Requirements
Ensure you have the following installed before running the script:
- **PowerShell 5.1 or later**
- **A Multimedia Player** (choose one or multiple of the following):
  - **VLC Media Player**:  
    Install with:
    - Windows `winget install -e --id VideoLAN.VLC`
    - Debian based distros: `sudo apt install vlc`
  - **Potplayer**:  
    Install with: `winget install potplayer --id Daum.PotPlayer -s winget`
  - **MPC-HC**:  
    Install with: `winget install MPC-HC --id clsid2.mpc-hc`
  - **MPV**:  
    Install with:
    - Windows: `scoop install mpv` or via [mpv.io](https://mpv.io/installation/)
    - Debian based distros: `sudo apt install mpv`
- **yt-dlp** *(for loading lofi girl)*:
    Install with:
    - Windows: `winget install --id=yt-dlp.yt-dlp  -e`
    - Debian based distros: `sudo apt install yt-dlp`
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
Clone the repository locally to get started:
```powershell
git clone https://github.com/RoMinjun/lofiatc.ps1.git
cd lofiatc.ps1
```
> [!IMPORTANT]
> Keep it updated with `git pull`.

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
```

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

> [!TIP]
> Switches are boolean—just include them (no `true/false` needed). CLI overrides always win over loaded config.

<br>

### Configuration
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

### Favorites
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

### Airport Sources
The script reads ATC streams from `atc_sources.csv`.

- Run `tools/UpdateATCSources.ps1` to generate/refresh a **local** `atc_sources.csv`. It'll be called `liveatc_sources.csv`   
- If a locally updated CSV exists, it is **preferred** over the `liveatc_sources.csv`.  
- Use `-UseBaseCSV` to ignore `liveatc_sources.csv` and use the base CSV.

```powershell
# From <projectroot>/tools
.\UpdateATCSources.ps1
```

> [!IMPORTANT]
> The base `atc_sources.csv` must not be deleted; both scripts rely on it.

<br>

### Player Selection
When `-Player` is not specified, the script tries to find an installed player.

- **Windows:** checks for mpv, vlc, PotPlayer, and MPC-HC (if available).  
- **macOS/Linux:** prefers **mpv**, then **vlc**.

Force a specific player any time:
```powershell
.\lofiatc.ps1 -Player mpv
.\lofiatc.ps1 -Player vlc
```

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

<br>

## Clean Up / Uninstall
You can safely delete the repo folder. Optional user files created:
- `favorites.json`
- `config.json`
- locally updated `atc_sources.csv`

<br>

## Contributing
PRs welcome! Popular contributions:
- New/updated ATC sources. Please add to `atc_sources.csv`, let the update script the rest.
- Better player detection across platforms
- Additional examples / docs improvements

---

## Support LiveATC
This project depends on the existence of [liveatc.net](https://www.liveatc.net).  
If you live near an airport and have a passion for air traffic control, and if it's legal in your country, consider [contacting LiveATC.net](https://www.liveatc.net/ct/contact.php) about hosting a feed.
