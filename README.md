<div align="center">

# lofiatc.ps1
An alternative to [lofiatc](https://www.lofiatc.com) built with PowerShell. This script integrates multimedia players like VLC, Potplayer, MPC-HC, or mpv, enabling you to simultaneously enjoy Lofi Girl and live Air Traffic Control streams from around the world.

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

</div>

<br>

# **Getting Started**

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

## **Explore Script Options**
Learn about all the features and parameters with the PowerShell `Get-Help` command:
```powershell
Get-Help .\lofiatc.ps1 -Full
```
