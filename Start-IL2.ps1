#Requires -Version 5.1
#Requires -Modules AudioDeviceCmdlets

#=============================================================================
# CONFIGURATION PHASE
#=============================================================================
# Get the base name of this script (e.g., "Startup" from "Startup.ps1")
$ScriptNameBase = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)

# Create a full path to the JSON file in the same folder as the script
$ConfigFile = Join-Path -Path $PSScriptRoot -ChildPath "$ScriptNameBase.json"

# Seconds to wait after Il-2 exits before cleaning up, in case the game restarts itself
# (e.g. after changing graphics/VR settings or applying an update)
$RestartGraceSeconds = 20

# Get the list of playback audio devices once (filter out mics / recording devices)
$AllAudioDevices = @(Get-AudioDevice -List | Where-Object { $_.Type -eq 'Playback' })
$DeviceCount = $AllAudioDevices.Count

if ($DeviceCount -eq 0) {
    Write-Host "ERROR: No playback audio devices found." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $ConfigFile)) {
    Write-Host "Configuration file not found. First-time setup required..." -ForegroundColor Yellow

    # Function to handle the numbered selection process
    function Get-UserDeviceSelection {
        param([string]$PromptMessage)

        while ($true) {
            Write-Host "`n--- $PromptMessage ---" -ForegroundColor Cyan
            for ($i = 0; $i -lt $DeviceCount; $i++) {
                Write-Host "$($i + 1). $($AllAudioDevices[$i].Name)"
            }

            $selection = Read-Host "`nEnter the number of your choice (1-$DeviceCount)"

            # Validate: Is it a number? Is it within the range?
            if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $DeviceCount) {
                return $AllAudioDevices[[int]$selection - 1]
            } else {
                Write-Host "Invalid selection. Please enter a valid number from the list." -ForegroundColor Red
            }
        }
    }

    # Get devices via the text menu
    $GameDevice    = Get-UserDeviceSelection -PromptMessage "STEP 1: Select audio device for IL-2"
    $DesktopDevice = Get-UserDeviceSelection -PromptMessage "STEP 2: Select audio device for Desktop"

    # Create and save the configuration object (ID + Name for each device)
    $ConfigData = [PSCustomObject]@{
        GameAudioID      = $GameDevice.ID
        GameAudioName    = $GameDevice.Name
        DesktopAudioID   = $DesktopDevice.ID
        DesktopAudioName = $DesktopDevice.Name
    }

    # Save to the same folder as the script with the matching name (UTF-8, not UTF-16)
    $ConfigData | ConvertTo-Json | Out-File -FilePath $ConfigFile -Encoding utf8
    Write-Host "`nConfiguration saved to: $ConfigFile" -ForegroundColor Green
}

#=============================================================================
# DEVICE ID VALIDATION
#=============================================================================

# Load and parse IDs from the dynamically named JSON file
$Config = Get-Content $ConfigFile | ConvertFrom-Json

# Resolves a saved playback device ID and name against the current device list.
# If the ID still exists it is used even if the device was renamed (the new name is returned).
# If the ID is gone (e.g. after a Windows update), searches for the device by name and returns the new ID.
function Resolve-AudioDevice {
    param(
        [string]$SavedID,
        [string]$SavedName,
        [string]$Label
    )

    if (-not $SavedName) {
        # Old config without names â€” cannot validate, just use the ID as-is
        Write-Host "Warning: No device name saved for $Label device. Delete $ConfigFile and re-run to enable ID validation." -ForegroundColor Yellow
        return [PSCustomObject]@{ ID = $SavedID; Name = $null }
    }

    $CurrentMatch = $AllAudioDevices | Where-Object { $_.ID -eq $SavedID } | Select-Object -First 1

    if ($CurrentMatch) {
        if ($CurrentMatch.Name -ne $SavedName) {
            Write-Host "$Label device was renamed from '$SavedName' to '$($CurrentMatch.Name)'. Configuration will be updated." -ForegroundColor Yellow
        }
        return [PSCustomObject]@{ ID = $SavedID; Name = $CurrentMatch.Name }
    }

    Write-Host "Warning: $Label audio device ID not found. Searching for '$SavedName'..." -ForegroundColor Yellow
    $Found = $AllAudioDevices | Where-Object { $_.Name -eq $SavedName } | Select-Object -First 1

    if ($Found) {
        Write-Host "$Label device found with new ID. Configuration will be updated." -ForegroundColor Green
        return [PSCustomObject]@{ ID = $Found.ID; Name = $Found.Name }
    }

    Write-Host "ERROR: $Label audio device '$SavedName' could not be found." -ForegroundColor Red
    Write-Host "       Delete '$ConfigFile' and re-run the script to reconfigure." -ForegroundColor Red
    exit 1
}

$GameAudio    = Resolve-AudioDevice -SavedID $Config.GameAudioID    -SavedName $Config.GameAudioName    -Label "Game"
$DesktopAudio = Resolve-AudioDevice -SavedID $Config.DesktopAudioID -SavedName $Config.DesktopAudioName -Label "Desktop"
$GameAudioID    = $GameAudio.ID
$DesktopAudioID = $DesktopAudio.ID

# If either ID or name changed, persist the updated values back to the config file
if ($GameAudioID -ne $Config.GameAudioID -or $DesktopAudioID -ne $Config.DesktopAudioID -or
    $GameAudio.Name -ne $Config.GameAudioName -or $DesktopAudio.Name -ne $Config.DesktopAudioName) {
    $Config.GameAudioID    = $GameAudioID
    $Config.DesktopAudioID = $DesktopAudioID
    # Add-Member -Force also works for old configs that have no name properties yet
    $Config | Add-Member -NotePropertyName GameAudioName    -NotePropertyValue $GameAudio.Name    -Force
    $Config | Add-Member -NotePropertyName DesktopAudioName -NotePropertyValue $DesktopAudio.Name -Force
    $Config | ConvertTo-Json | Out-File -FilePath $ConfigFile -Encoding utf8
    Write-Host "Configuration updated." -ForegroundColor Green
}

#=============================================================================
# INITIALIZATION + SESSION MONITORING (wrapped so Ctrl+C still cleans up)
#=============================================================================

# Starts a companion app unless it is already running.
# Returns $true only if this script launched it, so cleanup leaves the user's own instances alone.
function Start-CompanionApp {
    param(
        [string]$DisplayName,
        [string]$ProcessName,
        [string]$Path,
        [string]$WorkingDirectory
    )

    if (Get-Process $ProcessName -ErrorAction SilentlyContinue) {
        Write-Host "$DisplayName is already running, skipping..." -ForegroundColor Yellow
        return $false
    }

    if (-not (Test-Path $Path)) {
        Write-Host "Warning: $DisplayName not found at '$Path', skipping..." -ForegroundColor Yellow
        return $false
    }

    try {
        if ($WorkingDirectory) {
            Start-Process $Path -WorkingDirectory $WorkingDirectory -ErrorAction Stop
        } else {
            Start-Process $Path -ErrorAction Stop
        }
        return $true
    } catch {
        Write-Host "Warning: Failed to start ${DisplayName}: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

# Asks each instance of an app to close via its main window, then force-closes it after a timeout.
function Stop-ApplicationGracefully {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName,

        [int]$TimeoutSeconds = 5
    )

    $Processes = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
    foreach ($Process in $Processes) {
        Write-Host "Closing $DisplayName..." -ForegroundColor Gray
        $CloseRequested = $false

        try {
            if ($Process.MainWindowHandle -ne 0) {
                $CloseRequested = $Process.CloseMainWindow()
            }
        } catch {
            $CloseRequested = $false
        }

        if ($CloseRequested) {
            try {
                [void]$Process.WaitForExit($TimeoutSeconds * 1000)
            } catch {
                # The process may have exited between the checks.
            }
        }

        if (Get-Process -Id $Process.Id -ErrorAction SilentlyContinue) {
            Write-Host "$DisplayName did not close within $TimeoutSeconds seconds; forcing shutdown..." -ForegroundColor Yellow
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

# Game process names this script waits for, with their display names
$SupportedGames = @{
    'Il-2'      = 'IL-2 Great Battles'
    'IL2Series' = 'IL-2 Korea'
}

# Returns the first running supported game process, or $null
function Get-GameProcess {
    Get-Process -Name @($SupportedGames.Keys) -ErrorAction SilentlyContinue | Select-Object -First 1
}

# Set before the try so cleanup can read them even if the session aborts early
$StartedXRNeckSafer   = $false
# $StartedVectorXR      = $false
$StartedSRS           = $false
$StartedOpenKneeboard = $false

try {
    Write-Host "Setting audio to Game Device..." -ForegroundColor Gray
    try {
        Set-AudioDevice -ID $GameAudioID -ErrorAction Stop
    } catch {
        Write-Host "Warning: Could not switch to the Game audio device (is it connected?): $($_.Exception.Message)" -ForegroundColor Yellow
    }

    $StartedXRNeckSafer = Start-CompanionApp -DisplayName "XRNeckSafer" -ProcessName "XRNeckSaferApp" `
        -Path "C:\Program Files\XRNeckSafer\XRNeckSaferApp.exe"

    # $StartedVectorXR = Start-CompanionApp -DisplayName "VectorXR" -ProcessName "vectorxr-app" `
    #     -Path "C:\Program Files\VectorXR\vectorxr-app.exe"

    $StartedSRS = Start-CompanionApp -DisplayName "IL2 SimpleRadio" -ProcessName "IL2-SR-ClientRadio" `
        -Path "C:\Program Files\IL2-SimpleRadio-Standalone\IL2-SR-ClientRadio.exe" `
        -WorkingDirectory "C:\Program Files\IL2-SimpleRadio-Standalone"

    $StartedOpenKneeboard = Start-CompanionApp -DisplayName "OpenKneeboard" -ProcessName "OpenKneeboardApp" `
        -Path "C:\Program Files\OpenKneeboard\bin\OpenKneeboardApp.exe" `
        -WorkingDirectory "C:\Program Files\OpenKneeboard\bin"

    Write-Host "Waiting for IL-2 Great Battles or IL-2 Korea to start..." -ForegroundColor Cyan
    $GameProcess = $null
    while (-not $GameProcess) {
        $GameProcess = Get-GameProcess
        if (-not $GameProcess) {
            Start-Sleep -Seconds 2
        }
    }

    $GameName = $SupportedGames[$GameProcess.ProcessName]
    Write-Host "$GameName detected. Script will now wait for the game to exit before cleaning up..." -ForegroundColor Green
    while ($true) {
        # Wait on the process object (not the name) so a game that already exited doesn't raise an error
        $GameProcess | Wait-Process -ErrorAction SilentlyContinue

        Write-Host "$GameName exited. Waiting $RestartGraceSeconds seconds in case it restarts..." -ForegroundColor Gray
        $Deadline    = (Get-Date).AddSeconds($RestartGraceSeconds)
        $GameProcess = $null
        while ((Get-Date) -lt $Deadline) {
            Start-Sleep -Seconds 2
            $GameProcess = Get-GameProcess
            if ($GameProcess) { break }
        }

        if (-not $GameProcess) { break }
        $GameName = $SupportedGames[$GameProcess.ProcessName]
        Write-Host "$GameName restarted. Continuing to wait..." -ForegroundColor Green
    }
}
finally {
    # Only close companion apps this script launched
    if ($StartedXRNeckSafer) {
        Stop-ApplicationGracefully -ProcessName "XRNeckSaferApp" -DisplayName "XRNeckSafer"
    }
    # if ($StartedVectorXR) {
    #     Stop-ApplicationGracefully -ProcessName "vectorxr-app" -DisplayName "VectorXR"
    # }
    if ($StartedSRS) {
        Stop-ApplicationGracefully -ProcessName "IL2-SR-ClientRadio" -DisplayName "IL2 SimpleRadio"
    }
    if ($StartedOpenKneeboard) {
        Stop-ApplicationGracefully -ProcessName "OpenKneeboardApp" -DisplayName "OpenKneeboard"
    }

    Write-Host "Restoring audio to Desktop Device..." -ForegroundColor Gray
    try {
        Set-AudioDevice -ID $DesktopAudioID -ErrorAction Stop
    } catch {
        Write-Host "Warning: Could not restore the Desktop audio device: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Write-Host "Cleanup complete." -ForegroundColor Green
}
