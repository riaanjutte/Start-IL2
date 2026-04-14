#=============================================================================
# CONFIGURATION PHASE
#=============================================================================
# Get the base name of this script (e.g., "Startup" from "Startup.ps1")
$ScriptNameBase = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)

# Create a full path to the JSON file in the same folder as the script
$ConfigFile = Join-Path -Path $PSScriptRoot -ChildPath "$ScriptNameBase.json"

if (-not (Test-Path $ConfigFile)) {
    Write-Host "Configuration file not found. First-time setup required..." -ForegroundColor Yellow

    # Get the full list of audio devices
    $AllAudioDevices = Get-AudioDevice -List
    $DeviceCount = $AllAudioDevices.Count

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

    # Save to the same folder as the script with the matching name
    $ConfigData | ConvertTo-Json | Out-File $ConfigFile
    Write-Host "`nConfiguration saved to: $ConfigFile" -ForegroundColor Green
}

#=============================================================================
# DEVICE ID VALIDATION
#=============================================================================

# Load and parse IDs from the dynamically named JSON file
$Config = Get-Content $ConfigFile | ConvertFrom-Json

# Resolves a saved device ID against its saved name.
# If the ID no longer matches the name (e.g. after a Windows update),
# searches for the device by name and returns the new ID.
function Resolve-AudioDeviceID {
    param(
        [string]$SavedID,
        [string]$SavedName,
        [string]$Label
    )

    if (-not $SavedName) {
        # Old config without names — cannot validate, just use the ID as-is
        Write-Host "Warning: No device name saved for $Label device. Delete $ConfigFile and re-run to enable ID validation." -ForegroundColor Yellow
        return $SavedID
    }

    $AllDevices   = Get-AudioDevice -List
    $CurrentMatch = $AllDevices | Where-Object { $_.ID -eq $SavedID }

    if ($CurrentMatch -and $CurrentMatch.Name -eq $SavedName) {
        # ID and name match — all good
        return $SavedID
    }

    Write-Host "Warning: $Label audio device ID mismatch. Searching for '$SavedName'..." -ForegroundColor Yellow
    $Found = $AllDevices | Where-Object { $_.Name -eq $SavedName } | Select-Object -First 1

    if ($Found) {
        Write-Host "$Label device found with new ID. Configuration will be updated." -ForegroundColor Green
        return $Found.ID
    }

    Write-Host "ERROR: $Label audio device '$SavedName' could not be found." -ForegroundColor Red
    Write-Host "       Delete '$ConfigFile' and re-run the script to reconfigure." -ForegroundColor Red
    exit 1
}

$GameAudioID    = Resolve-AudioDeviceID -SavedID $Config.GameAudioID    -SavedName $Config.GameAudioName    -Label "Game"
$DesktopAudioID = Resolve-AudioDeviceID -SavedID $Config.DesktopAudioID -SavedName $Config.DesktopAudioName -Label "Desktop"

# If either ID changed, persist the updated IDs back to the config file
if ($GameAudioID -ne $Config.GameAudioID -or $DesktopAudioID -ne $Config.DesktopAudioID) {
    $Config.GameAudioID    = $GameAudioID
    $Config.DesktopAudioID = $DesktopAudioID
    $Config | ConvertTo-Json | Out-File $ConfigFile
    Write-Host "Configuration updated with new device IDs." -ForegroundColor Green
}

#=============================================================================
# INITIALIZATION
#=============================================================================

Write-Host "Setting audio to Game Device..." -ForegroundColor Gray
Set-AudioDevice -ID $GameAudioID

if (Get-Process "XRNeckSaferApp" -ErrorAction SilentlyContinue) {
    Write-Host "XRNeckSafer is already running, skipping..." -ForegroundColor Yellow
} else {
    Start-Process "C:\Program Files\XRNeckSafer\XRNeckSaferApp.exe"
}

if (Get-Process "IL2-SR-ClientRadio" -ErrorAction SilentlyContinue) {
    Write-Host "IL2 SimpleRadio is already running, skipping..." -ForegroundColor Yellow
} else {
    Start-Process "C:\Program Files\IL2-SimpleRadio-Standalone\IL2-SR-ClientRadio.exe" -WorkingDirectory "C:\Program Files\IL2-SimpleRadio-Standalone"
}

#=============================================================================
# SESSION MONITORING
#=============================================================================
Write-Host "Waiting for Il-2 to start..." -ForegroundColor Cyan

while (!(Get-Process "Il-2" -ErrorAction SilentlyContinue)) {
    Start-Sleep -Seconds 2
}

Write-Host "Il-2 detected. Script will now wait for the game to exit before cleaning up..." -ForegroundColor Green

Wait-Process -Name "Il-2"

Stop-Process -Name "XRNeckSaferApp" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "IL2-SR-ClientRadio"

Write-Host "Restoring audio to Desktop Device..." -ForegroundColor Gray
Set-AudioDevice -ID $DesktopAudioID
Write-Host "Cleanup complete." -ForegroundColor Green
