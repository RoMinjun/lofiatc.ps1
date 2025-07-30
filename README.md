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

## **Requirements**
Ensure you have the following installed before running the script:
- **PowerShell 5.1 or later**
- **A Multimedia Player** (choose one of the following):
  - **VLC Media Player**:  
    Install with: `winget install -e --id VideoLAN.VLC`
  - **Potplayer**:  
    Install with: `winget install potplayer --id Daum.PotPlayer -s winget`
  - **MPC-HC**:  
    Install with: `winget install MPC-HC --id clsid2.mpc-hc`
  - **MPV**:  
    Install with: `scoop install mpv` or via [mpv.io](https://mpv.io/installation/)
- **fzf** *(Optional, but recommended)*:  
  Install with: `winget install --id=junegunn.fzf -e`

The script can automatically detect `mpv` or `vlc` on macOS and Linux when no player is specified.

---

## **Clone the Repository**
Clone the repository locally to get started:
```powershell
git clone https://github.com/RoMinjun/lofiatc.ps1.git
```

## **Run the Script**
Execute the script using PowerShell:
```powershell
.\lofiatc.ps1
```

## Update Air Traffic Control sources locally
I've also added an option to get updated sources based on the base source file `atc_sources.csv`. If created, this file will be prioritized over the base csv file. Run the following script from the `<projectroot>/tools` to locally update sources:
```powershell
.\UpdateATCSources.ps1
```
> [!IMPORTANT]
> The base csv file `atc_sources.csv` may never be deleted when using `lofiatc.ps1` since the `UpdateATCSources.ps1` and the `lofiatc.ps1` scripts both make use of that base sources file.

> [!TIP]
> If you wish to keep using the base `atc_sources.csv` after you've updated your sources locally, use the `-UseBaseCSV` param with the `lofiatc.ps1` script

## **Explore Script Options**
Learn about all the features and parameters with the PowerShell `Get-Help` command:
```powershell
Get-Help .\lofiatc.ps1 -Full
```

### **Volume Options**
Two parameters control the audio level of each stream:

- `-ATCVolume` sets the ATC stream volume (default `65`).
- `-LofiVolume` sets the Lofi Girl volume (default `50`).

### **Favorites**
Each time you select a stream, its ICAO and channel are recorded in `favorites.json` beside the script. The file tracks how many times you've listened to each stream and keeps the ten most frequently used entries. Use the `-UseFavorite` switch to choose from this list (combine with `-UseFZF` to search within favorites).

### Open FlightAware Radar
Pass `-OpenRadar` to automatically launch the selected airport's radar page in your browser. The function works on Windows, macOS, and Linux by calling the appropriate system opener.

### Cross-Platform Player Detection
When no `-Player` is specified the script now tries to locate `mpv` or `vlc` on macOS/Linux before falling back to Windows defaults.

### Discord Rich Presence
Use the `-DiscordRPC` switch to show what you're listening to in Discord. This requires the `discordrpc` module which can be installed via `Install-Module discordrpc -Scope CurrentUser`. When enabled the script waits for the media players to close so your status clears automatically.

# Help liveatc.net's existence
This repo wouldn't be anything without [liveatc.net](https://www.liveatc.net). If you live near an airport and have a passion for air traffic control, and if it's legal in your country, consider [contacting LiveATC.net](https://www.liveatc.net/ct/contact.php). They can help you get set up with the necessary equipment.
