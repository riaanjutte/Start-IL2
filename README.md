# Start-IL2

A PowerShell script that automates the IL-2 Sturmovik session setup and teardown:

- Switches the default audio device to your headset when the game starts
- Launches [XRNeckSafer](https://store.steampowered.com/app/1069750/XRNeckSafer/), [IL2 SimpleRadio Standalone](https://github.com/ciribob/IL2-SimpleRadioStandalone) and [OpenKneeboard](https://openkneeboard.com/) if they are not already running
- Waits for IL-2 Great Battles (`Il-2.exe`) or IL-2 Korea (`IL2Series.exe`) to exit, then closes the companion apps it launched and restores the desktop audio device

## Requirements

- Windows PowerShell 5.1
- [AudioDeviceCmdlets](https://github.com/frgnca/AudioDeviceCmdlets) module (`Install-Module -Name AudioDeviceCmdlets`)
- XRNeckSafer installed at `C:\Program Files\XRNeckSafer\`
- IL2 SimpleRadio Standalone installed at `C:\Program Files\IL2-SimpleRadio-Standalone\`
- OpenKneeboard installed at `C:\Program Files\OpenKneeboard\`

If a companion app isn't found at its path, the script prints a warning, skips it, and carries on with the rest of the session.

VectorXR support (`C:\Program Files\VectorXR\vectorxr-app.exe`) is still in the script but commented out. To switch to it, uncomment the `VectorXR` lines in `Start-IL2.ps1` and comment out the `XRNeckSafer` ones.

## First-run setup

On the first run the script detects that no configuration exists and prompts you to pick your playback devices from a numbered list. The choices are saved to `Start-IL2.json` next to the script and reused on every subsequent run.

If Windows reassigns a device ID (common after updates), the script automatically searches for the saved device name and updates the config file. If you rename a device, the saved ID still works and the new name is saved.

## Session behavior

- Apps that were already running before the script started are left open at cleanup.
- Apps the script launched are asked to close through their window first, and force-closed if they're still running after 5 seconds.
- After IL-2 exits, the script waits 20 seconds before cleaning up, in case the game restarts itself (for example after changing graphics or VR settings). Change `$RestartGraceSeconds` at the top of the script to adjust this.
- If the headset can't be selected (for example it's switched off), the script prints a warning and continues.
- Pressing Ctrl+C still runs cleanup.

## Usage

Run the script from PowerShell:

```powershell
.\Start-IL2.ps1
```

Or create a shortcut / Steam launch option that calls it before starting the game.

## License

MIT
