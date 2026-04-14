# Start-IL2

A PowerShell script that automates the IL-2 Sturmovik session setup and teardown:

- Switches the default audio device to your headset when the game starts
- Launches [XRNeckSafer](https://store.steampowered.com/app/1069750/XRNeckSafer/) and [IL2 SimpleRadio Standalone](https://github.com/ciribob/IL2-SimpleRadioStandalone) if they are not already running
- Waits for IL-2 to exit, then closes the companion apps and restores the desktop audio device

## Requirements

- Windows PowerShell
- [AudioDeviceCmdlets](https://github.com/frgnca/AudioDeviceCmdlets) module (`Install-Module -Name AudioDeviceCmdlets`)
- XRNeckSafer installed at `C:\Program Files\XRNeckSafer\`
- IL2 SimpleRadio Standalone installed at `C:\Program Files\IL2-SimpleRadio-Standalone\`

## First-run setup

On the first run the script detects that no configuration exists and prompts you to pick your audio devices from a numbered list. The choices are saved to `Start-IL2.json` next to the script and reused on every subsequent run.

If Windows reassigns a device ID (common after updates), the script automatically searches for the saved device name and updates the config file.

## Usage

Run the script from PowerShell:

```powershell
.\Start-IL2.ps1
```

Or create a shortcut / Steam launch option that calls it before starting the game.

## License

MIT
