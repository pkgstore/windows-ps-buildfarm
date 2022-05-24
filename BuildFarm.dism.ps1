<#
.SYNOPSIS
  Windows WIM modification script.
.DESCRIPTION
  The script modifies WIM image of operating system.
  Parameters define how the script works.
#>

#Requires -Version 7.2
#Requires -RunAsAdministrator

Param(
  [Parameter(HelpMessage="Enter DISM path.")]
  [Alias("DP")]
  [string]$DismPath = "$($PSScriptRoot)\Apps\ADK\Assessment and Deployment Kit\Deployment Tools\amd64\DISM",

  [Parameter(HelpMessage="Enter WIM language.")]
  [Alias("WL")]
  [string]$WimLanguage = "en-us",

  [Parameter(HelpMessage="Disable hash value for a WIM file.")]
  [Alias("NoWH")]
  [switch]$NoWimHash = $false,

  [Parameter(HelpMessage="Adds a single .cab or .msu file to a Windows image.")]
  [Alias("AP")]
  [switch]$AddPackages = $false,

  [Parameter(HelpMessage="Adds a driver to an offline Windows image.")]
  [Alias("AD")]
  [switch]$AddDrivers = $false,

  [Parameter(HelpMessage="Resets the base of superseded components to further reduce the component store size.")]
  [Alias("RB")]
  [switch]$ResetBase = $false,

  [Parameter(HelpMessage="Scans the image for component store corruption. This operation will take several minutes.")]
  [Alias("SH")]
  [switch]$ScanHealth = $false,

  [Parameter(HelpMessage="Saves the changes to a Windows image.")]
  [Alias("SI")]
  [switch]$SaveImage = $false,

  [Parameter(HelpMessage="Export WIM to ESD format.")]
  [Alias("ESD")]
  [switch]$ExportToESD = $false
)

# -------------------------------------------------------------------------------------------------------------------- #
# INITIALIZATION.
# -------------------------------------------------------------------------------------------------------------------- #

function Start-BuildFarm() {
  # Directories.
  $d_app = "$($PSScriptRoot)\Apps"
  $d_drv = "$($PSScriptRoot)\Drivers"
  $d_log = "$($PSScriptRoot)\Logs"
  $d_mnt = "$($PSScriptRoot)\Mount"
  $d_tmp = "$($PSScriptRoot)\Temp"
  $d_upd = "$($PSScriptRoot)\Updates"
  $d_wim = "$($PSScriptRoot)\WIM"

  # Timestamp.
  $ts = Get-Date -Format "yyyy-MM-dd.HH-mm-ss"

  # WIM path.
  $f_wim_original = "$($WimLanguage)\install.wim"
  $f_wim_custom = "$($WimLanguage)\install.custom.$($ts).wim"

  # Sleep time.
  [int]$sleep = 10

  # Run.
  Start-BuildImage
}

# -------------------------------------------------------------------------------------------------------------------- #
# BUILD IMAGE.
# -------------------------------------------------------------------------------------------------------------------- #

function Start-BuildImage() {
  # Get new DISM.
  $env:Path = "$($DismPath)"
  Import-Module "$($DismPath)"

  # Check directories.
  if ( ! ( Test-Path "$($d_app)" ) ) { New-Item -Path "$($d_app)" -ItemType "Directory" }
  if ( ! ( Test-Path "$($d_drv)" ) ) { New-Item -Path "$($d_drv)" -ItemType "Directory" }
  if ( ! ( Test-Path "$($d_log)" ) ) { New-Item -Path "$($d_log)" -ItemType "Directory" }
  if ( ! ( Test-Path "$($d_mnt)" ) ) { New-Item -Path "$($d_mnt)" -ItemType "Directory" }
  if ( ! ( Test-Path "$($d_tmp)" ) ) { New-Item -Path "$($d_tmp)" -ItemType "Directory" }
  if ( ! ( Test-Path "$($d_upd)" ) ) { New-Item -Path "$($d_upd)" -ItemType "Directory" }
  if ( ! ( Test-Path "$($d_wim)" ) ) { New-Item -Path "$($d_wim)" -ItemType "Directory" }

  # Start build log.
  Start-Transcript -Path "$($d_log)\wim.build.$($ts).log"

  while ( $true ) {

    # Check WIM file exist.
    if ( ! ( Test-Path -Path "$($d_wim)\$($f_wim_original)" -PathType "Leaf" ) ) { break }

    # Get Windows image hash.
    if ( ! $NoWimHash ) {
      Write-BFMsg -Title -Message "--- Get Windows Image Hash..."
      Get-FileHash "$($d_wim)\$($f_wim_original)" -Algorithm "SHA256" | Format-List
      Start-Sleep -s $sleep
    }

    # Get Windows image info.
    Write-BFMsg -Title -Message "--- Get Windows Image Info..."
    Dism /Get-ImageInfo /ImageFile:"$($d_wim)\$($f_wim_original)" /ScratchDir:"$($d_tmp)"
    [int]$wim_index = Read-Host "Enter WIM index (Press [ENTER] to EXIT)"
    if ( ! $wim_index ) { break }

    # Mount Windows image.
    Write-BFMsg -Title -Message "--- Mount Windows Image..."
    Dism /Mount-Image /ImageFile:"$($d_wim)\$($f_wim_original)" /MountDir:"$($d_mnt)" /Index:$wim_index /CheckIntegrity /ScratchDir:"$($d_tmp)"
    Start-Sleep -s $sleep

    if ( ( $AddPackages ) -and ( ! ( Get-ChildItem "$($d_upd)" | Measure-Object ).Count -eq 0 ) ) {
      # Add packages.
      Write-BFMsg -Title -Message "--- Add Windows Packages..."
      Dism /Image:"$($d_mnt)" /Add-Package /PackagePath "$($d_upd)" /IgnoreCheck /ScratchDir:"$($d_tmp)"
      Start-Sleep -s $sleep

      # Get packages.
      Write-BFMsg -Title -Message "--- Get Windows Packages..."
      Dism /Image:"$($d_mnt)" /Get-Packages /ScratchDir:"$($d_tmp)"
      Start-Sleep -s $sleep
    }

    # Add drivers.
    if ( ( $AddDrivers ) -and ( ! ( Get-ChildItem "$($d_drv)" | Measure-Object ).Count -eq 0 ) ) {
      Write-BFMsg -Title -Message "--- Add Windows Drivers..."
      Dism /Image:"$($d_mnt)" /Add-Driver "$($d_drv)" /Recurse /ScratchDir:"$($d_tmp)"
      Start-Sleep -s $sleep
    }

    # Reset Windows image.
    if ( $ResetBase ) {
      Write-BFMsg -Title -Message "--- Reset Windows Image..."
      Dism /Image:"$($d_mnt)" /Cleanup-Image /StartComponentCleanup /ResetBase /ScratchDir:"$($d_tmp)"
      Start-Sleep -s $sleep
    }

    # Scan health Windows image.
    if ( $ScanHealth ) {
      Write-BFMsg -Title -Message "--- Scan Health Windows Image..."
      Dism /Image:"$($d_mnt)" /Cleanup-Image /ScanHealth /ScratchDir:"$($d_tmp)"
      Start-Sleep -s $sleep
    }

    # Dismount Windows image.
    if ( $SaveImage ) {
      Write-BFMsg -Title -Message "--- Save & Dismount Windows Image..."
      Dism /Unmount-Image /MountDir:"$($d_mnt)" /Commit /ScratchDir:"$($d_tmp)"
      Start-Sleep -s $sleep
    } else {
      Write-BFMsg -Title -Message "--- Discard & Dismount Windows Image..."
      Dism /Unmount-Image /MountDir:"$($d_mnt)" /Discard /ScratchDir:"$($d_tmp)"
      Start-Sleep -s $sleep
    }

    if ( $ExportToESD ) {
      # Export Windows image to custom ESD format.
      Write-BFMsg -Title -Message "--- Export Windows Image to Custom ESD Format..."
      Dism /Export-Image /SourceImageFile:"$($d_wim)\$($f_wim_original)" /SourceIndex:$wim_index /DestinationImageFile:"$($d_wim)\$($f_wim_custom).esd" /Compress:recovery /CheckIntegrity /ScratchDir:"$($d_tmp)"
      Start-Sleep -s $sleep
    } else {
      # Export Windows image to custom WIM format.
      Write-BFMsg -Title -Message "--- Export Windows Image to Custom WIM Format..."
      Dism /Export-Image /SourceImageFile:"$($d_wim)\$($f_wim_original)" /SourceIndex:$wim_index /DestinationImageFile:"$($d_wim)\$($f_wim_custom)" /Compress:max /CheckIntegrity /ScratchDir:"$($d_tmp)"
      Start-Sleep -s $sleep
    }

    # Create Windows image archive.
    Write-BFMsg -Title -Message "--- Create Windows Image Archive..."
    if ( Test-Path -Path "$($d_wim)\$($f_wim_custom).esd" -PathType "Leaf" ) {
      New-7z -App "$($d_app)\7z\7za.exe" -In "$($d_wim)\$($f_wim_custom).esd" -Out "$($d_wim)\$($f_wim_custom).esd.7z"
    } elseif ( Test-Path -Path "$($d_wim)\$($f_wim_custom)" -PathType "Leaf" ) {
      New-7z -App "$($d_app)\7z\7za.exe" -In "$($d_wim)\$($f_wim_custom)" -Out "$($d_wim)\$($f_wim_custom).7z"
    } else {
      Write-Host "Not Found: '$($f_wim_custom)' or '$($f_wim_custom).esd'."
    }
    Start-Sleep -s $sleep

  }

  # Stop build log.
  Stop-Transcript
}

# -------------------------------------------------------------------------------------------------------------------- #
# ------------------------------------------------< COMMON FUNCTIONS >------------------------------------------------ #
# -------------------------------------------------------------------------------------------------------------------- #

function Write-BFMsg() {
  param (
    [string]$Message,
    [switch]$Title = $false
  )
  if ( $Title ) {
    Write-Host "$($Message)" -ForegroundColor Blue
  } else {
    Write-Host "$($Message)"
  }
}

function New-7z() {
  param (
    [string]$App,
    [string]$In,
    [string]$Out
  )
  $7zParams = "a", "-t7z", "$($Out)", "$($In)"
  & "$($App)" @7zParams
}

# -------------------------------------------------------------------------------------------------------------------- #
# -------------------------------------------------< INIT FUNCTIONS >------------------------------------------------- #
# -------------------------------------------------------------------------------------------------------------------- #

Start-BuildFarm