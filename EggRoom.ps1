<#
.SYNOPSIS
    Deltarune Egg Room Boot Up — probabilistic Wallpaper Engine easter egg for Windows.

.DESCRIPTION
    Rolls a configurable random chance (default 1/100) on Windows logon. When triggered,
    recreates Deltarune's secret Egg Room ("Man Behind the Tree") experience:
      1. Mutes Wallpaper Engine so the previous wallpaper's audio never leaks.
      2. Sets Windows master volume to the configured level (default 50%).
      3. Hides desktop icons and minimizes all open windows.
      4. Switches Wallpaper Engine to the Egg Room wallpaper and sets its volume to 100%.
      5. Enables Wallpaper Engine's global Audio Output for the current Windows user if disabled.
      6. Minimizes windows once more and unmutes Wallpaper Engine as the final step.

    On non-triggering boots (~99% of launches), the script exits immediately after the
    probability roll without compiling C# or scanning disks.

.PARAMETER Force
    Alias: -Test. Bypasses the probability roll and triggers the Egg Room sequence immediately.

.PARAMETER DryRun
    Resolves Steam libraries, Wallpaper Engine, target wallpaper, volume property, and
    audio config without modifying system state, volume, icons, or windows.

.PARAMETER Chance
    Overrides the 1-in-N probability from config.json (e.g., 100 = 1% chance).

.PARAMETER SystemVolumePercent
    Overrides the target Windows master volume percentage (0-100) from config.json.

.PARAMETER WorkshopIds
    Overrides the Steam Workshop IDs from config.json.

.PARAMETER ConfigPath
    Path to a custom JSON configuration file. Defaults to config.json next to this script.

.EXAMPLE
    .\EggRoom.ps1 -Force
    Triggers the Egg Room sequence immediately for testing.

.EXAMPLE
    .\EggRoom.ps1 -DryRun
    Verifies paths and settings without making any changes.
#>
[CmdletBinding()]
param(
    [Alias('Test')]
    [switch]$Force,

    [switch]$DryRun,

    [ValidateRange(1, 1000000)]
    [int]$Chance,

    [ValidateRange(0, 100)]
    [int]$SystemVolumePercent,

    [string[]]$WorkshopIds,

    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

# ==============================================================================
# 1. Paths & Configuration (Lightweight — runs on every logon)
# ==============================================================================
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (-not (Test-Path -LiteralPath $scriptDir)) {
    New-Item -Path $scriptDir -ItemType Directory -Force | Out-Null
}

$script:logPath = Join-Path -Path $scriptDir -ChildPath 'egg_log.txt'
$script:dryRunMode = [bool]$DryRun

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path -Path $scriptDir -ChildPath 'config.json'
}

# Defaults
$cfg = [ordered]@{
    chance                     = 100
    systemVolumePercent        = 50
    workshopIds                = @('3776981825', '3772358586')
    wallpaperPath              = ''
    wallpaperEnginePath        = ''
    hideDesktopIcons           = $true
    minimizeAllWindows         = $true
    enableGlobalWallpaperAudio = $true
    maxLogLines                = 200
}

$configWarning = $null
if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
    try {
        $rawCfg = [System.IO.File]::ReadAllText($ConfigPath, [System.Text.Encoding]::UTF8)
        $parsedCfg = $rawCfg | ConvertFrom-Json -ErrorAction Stop
        foreach ($prop in $parsedCfg.PSObject.Properties) {
            if ($cfg.Contains($prop.Name)) {
                $cfg[$prop.Name] = $prop.Value
            }
        }
    } catch {
        $configWarning = "WARNING: Failed to parse '$ConfigPath' ($_). Using built-in defaults."
    }
}

# CLI overrides take precedence over config.json
if ($PSBoundParameters.ContainsKey('Chance')) {
    $cfg['chance'] = $Chance
}
if ($PSBoundParameters.ContainsKey('SystemVolumePercent')) {
    $cfg['systemVolumePercent'] = $SystemVolumePercent
}
if ($PSBoundParameters.ContainsKey('WorkshopIds') -and $WorkshopIds.Count -gt 0) {
    $cfg['workshopIds'] = $WorkshopIds
}

$effectiveChance = [int]$cfg['chance']
if ($effectiveChance -lt 1) { $effectiveChance = 1 }

$effectiveWorkshopIds = @($cfg['workshopIds'] | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { ([string]$_).Trim() })
$effectiveMaxLogLines = [int]$cfg['maxLogLines']

$effectiveVolumePercent = $null
if ($null -ne $cfg['systemVolumePercent'] -and -not [string]::IsNullOrWhiteSpace([string]$cfg['systemVolumePercent'])) {
    $vol = [int]$cfg['systemVolumePercent']
    if ($vol -lt 0) { $vol = 0 }
    if ($vol -gt 100) { $vol = 100 }
    $effectiveVolumePercent = $vol
}

function Write-EggLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    $entry = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
    if ($script:dryRunMode) {
        Write-Host "[DRY-RUN] $entry"
        return
    }
    try {
        Add-Content -LiteralPath $script:logPath -Value $entry -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Logging should never break the easter egg execution.
    }
}

function Invoke-LogRotation {
    if ($script:dryRunMode -or $effectiveMaxLogLines -le 0) { return }
    if (-not (Test-Path -LiteralPath $script:logPath -PathType Leaf)) { return }
    try {
        $lines = [System.IO.File]::ReadAllLines($script:logPath, [System.Text.Encoding]::UTF8)
        if ($lines.Length -gt $effectiveMaxLogLines) {
            $trimmed = $lines[($lines.Length - $effectiveMaxLogLines)..($lines.Length - 1)]
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllLines($script:logPath, $trimmed, $utf8NoBom)
        }
    } catch {
        # Best-effort rotation only.
    }
}

Write-EggLog '=== SCRIPT LAUNCHED ==='
if ($configWarning) {
    Write-EggLog $configWarning
}

# ==============================================================================
# 2. Probability Check FIRST (Fast-path exit before C# compilation or disk I/O)
# ==============================================================================
if (-not $Force -and -not $DryRun) {
    $roll = Get-Random -Minimum 1 -Maximum ($effectiveChance + 1)
    if ($roll -ne 1) {
        Write-EggLog "Skipped. Rolled: $roll / $effectiveChance"
        Write-EggLog '=== SCRIPT FINISHED (NO EVENT) ==='
        Invoke-LogRotation
        exit 0
    }
    Write-EggLog "TRIGGERED! Rolled 1 / $effectiveChance. Executing Egg Room sequence..."
} elseif ($DryRun) {
    Write-EggLog "DRY-RUN mode active (configured chance: 1/$effectiveChance). No system changes will be applied."
} else {
    Write-EggLog "FORCED run (-Force/-Test). Bypassing 1/$effectiveChance probability roll..."
}

# ==============================================================================
# 3. Helper Functions (Only loaded when the event actually triggers or DryRun)
# ==============================================================================
function Initialize-MasterAudio {
    if ([System.Management.Automation.PSTypeName]'EggRoomAudio.MasterAudio'.Type) {
        return $true
    }

    $audioSource = @'
using System;
using System.Runtime.InteropServices;

namespace EggRoomAudio {
    [Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioEndpointVolume {
        int RegisterControlChangeNotify(IntPtr pNotify);
        int UnregisterControlChangeNotify(IntPtr pNotify);
        int GetChannelCount(out uint pnChannelCount);
        int SetMasterVolumeLevel(float fLevelDB, Guid pguidEventContext);
        int SetMasterVolumeLevelScalar(float fLevel, Guid pguidEventContext);
        int GetMasterVolumeLevel(out float pfLevelDB);
        int GetMasterVolumeLevelScalar(out float pfLevel);
        int SetChannelVolumeLevel(uint nChannel, float fLevelDB, Guid pguidEventContext);
        int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, Guid pguidEventContext);
        int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
        int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
        int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, Guid pguidEventContext);
        int GetMute([MarshalAs(UnmanagedType.Bool)] out bool pbMute);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice {
        int Activate(ref Guid id, int clsCtx, IntPtr activationParams, out IAudioEndpointVolume aev);
    }

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(int dataFlow, int dwStateMask, out IntPtr ppDevices);
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorComObject { }

    public static class MasterAudio {
        public static void SetVolume(float level) {
            if (level < 0.0f) level = 0.0f;
            if (level > 1.0f) level = 1.0f;

            IMMDeviceEnumerator enumerator = null;
            IMMDevice device = null;
            IAudioEndpointVolume endpointVolume = null;
            try {
                enumerator = new MMDeviceEnumeratorComObject() as IMMDeviceEnumerator;
                if (enumerator == null) {
                    throw new InvalidOperationException("Failed to create IMMDeviceEnumerator COM object.");
                }

                // dataFlow 0 = eRender, role 1 = eMultimedia
                Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0, 1, out device));
                if (device == null) {
                    throw new InvalidOperationException("No default audio playback device found.");
                }

                Guid epvid = typeof(IAudioEndpointVolume).GUID;
                Marshal.ThrowExceptionForHR(device.Activate(ref epvid, 23, IntPtr.Zero, out endpointVolume));
                if (endpointVolume == null) {
                    throw new InvalidOperationException("Failed to activate IAudioEndpointVolume interface.");
                }

                Marshal.ThrowExceptionForHR(endpointVolume.SetMute(false, Guid.Empty));
                Marshal.ThrowExceptionForHR(endpointVolume.SetMasterVolumeLevelScalar(level, Guid.Empty));
            } finally {
                if (endpointVolume != null) Marshal.ReleaseComObject(endpointVolume);
                if (device != null) Marshal.ReleaseComObject(device);
                if (enumerator != null) Marshal.ReleaseComObject(enumerator);
            }
        }
    }
}
'@

    Add-Type -TypeDefinition $audioSource -ErrorAction Stop
    return $true
}

function Get-SteamLibraryPaths {
    $candidates = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $addUnique = {
        param([string]$PathValue)
        if ([string]::IsNullOrWhiteSpace($PathValue)) { return }
        $normalized = $PathValue.Replace('/', '\').Trim().TrimEnd('\')
        if ([string]::IsNullOrWhiteSpace($normalized)) { return }
        if ((Test-Path -LiteralPath $normalized -PathType Container) -and $seen.Add($normalized)) {
            $candidates.Add($normalized)
        }
    }

    # 1. Primary source: Steam registry keys + libraryfolders.vdf
    $steamRoots = @()
    $hkcuSteam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name 'SteamPath' -ErrorAction SilentlyContinue).SteamPath
    if ($hkcuSteam) { $steamRoots += $hkcuSteam }
    $hklmSteam = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -Name 'InstallPath' -ErrorAction SilentlyContinue).InstallPath
    if ($hklmSteam) { $steamRoots += $hklmSteam }

    foreach ($root in $steamRoots) {
        & $addUnique $root
        $vdfPath = Join-Path -Path ($root.Replace('/', '\')) -ChildPath 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdfPath -PathType Leaf) {
            try {
                $vdfText = [System.IO.File]::ReadAllText($vdfPath, [System.Text.Encoding]::UTF8)
                $pathMatches = [regex]::Matches($vdfText, '(?i)"path"\s+"([^"]+)"')
                foreach ($m in $pathMatches) {
                    $libPath = $m.Groups[1].Value -replace '\\\\', '\'
                    & $addUnique $libPath
                }
            } catch {
                Write-EggLog "WARNING: Could not parse libraryfolders.vdf at '$vdfPath': $_"
            }
        }
    }

    return ,$candidates.ToArray()
}

function Get-FixedDriveFallbackLibraries {
    $fallbacks = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq [System.IO.DriveType]::Fixed -and $_.IsReady }
    foreach ($drive in $drives) {
        foreach ($rel in @('Program Files (x86)\Steam', 'Program Files\Steam', 'SteamLibrary', 'Steam')) {
            $dir = Join-Path -Path $drive.RootDirectory.FullName -ChildPath $rel
            if ((Test-Path -LiteralPath $dir -PathType Container) -and $seen.Add($dir)) {
                $fallbacks.Add($dir)
            }
        }
    }

    return ,$fallbacks.ToArray()
}

function Find-WallpaperEngine {
    param(
        [string]$ConfiguredPath,
        [string[]]$LibraryPaths
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        if (Test-Path -LiteralPath $ConfiguredPath -PathType Leaf) {
            return $ConfiguredPath
        }
        Write-EggLog "WARNING: Configured wallpaperEnginePath '$ConfiguredPath' was not found. Falling back to auto-discovery."
    }

    $searchSets = @($LibraryPaths, (Get-FixedDriveFallbackLibraries))
    foreach ($libSet in $searchSets) {
        foreach ($lib in $libSet) {
            foreach ($exeName in @('wallpaper64.exe', 'wallpaper32.exe')) {
                $candidate = Join-Path -Path $lib -ChildPath "steamapps\common\wallpaper_engine\$exeName"
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    return $candidate
                }
            }
        }
    }

    return $null
}

function Find-EggWallpaper {
    param(
        [string]$ConfiguredPath,
        [string[]]$TargetWorkshopIds,
        [string[]]$LibraryPaths
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        if (Test-Path -LiteralPath $ConfiguredPath -PathType Leaf) {
            return $ConfiguredPath
        }
        Write-EggLog "WARNING: Configured wallpaperPath '$ConfiguredPath' was not found. Falling back to Workshop discovery."
    }

    if (-not $TargetWorkshopIds -or $TargetWorkshopIds.Count -eq 0) {
        return $null
    }

    $searchSets = @($LibraryPaths, (Get-FixedDriveFallbackLibraries))
    foreach ($libSet in $searchSets) {
        foreach ($id in $TargetWorkshopIds) {
            foreach ($lib in $libSet) {
                $itemDir = Join-Path -Path $lib -ChildPath "steamapps\workshop\content\431960\$id"
                if (-not (Test-Path -LiteralPath $itemDir -PathType Container)) { continue }

                # Prefer scene.pkg (scene wallpapers), fall back to project.json (video/web wallpapers)
                $scenePkg = Join-Path -Path $itemDir -ChildPath 'scene.pkg'
                if (Test-Path -LiteralPath $scenePkg -PathType Leaf) {
                    return $scenePkg
                }

                $projectJson = Join-Path -Path $itemDir -ChildPath 'project.json'
                if (Test-Path -LiteralPath $projectJson -PathType Leaf) {
                    return $projectJson
                }
            }
        }
    }

    return $null
}

function Get-WallpaperVolumePropertyKey {
    param([Parameter(Mandatory = $true)][string]$WallpaperFilePath)

    $defaultKey = 'volume'
    $projectJsonPath = Join-Path -Path (Split-Path -Path $WallpaperFilePath -Parent) -ChildPath 'project.json'
    if (-not (Test-Path -LiteralPath $projectJsonPath -PathType Leaf)) {
        Write-EggLog "INFO: project.json not found next to wallpaper; using default property key '$defaultKey'."
        return $defaultKey
    }

    try {
        $rawProject = [System.IO.File]::ReadAllText($projectJsonPath, [System.Text.Encoding]::UTF8)
        $projectDef = $rawProject | ConvertFrom-Json -ErrorAction Stop
        $definedProperties = $projectDef.general.properties
        if ($definedProperties) {
            $propDefs = @($definedProperties.PSObject.Properties)
            $exact = $propDefs | Where-Object { $_.Name -ieq 'volume' } | Select-Object -First 1
            if ($exact) {
                return [string]$exact.Name
            }

            $candidate = $propDefs | Where-Object {
                $pName = [string]$_.Name
                $pText = [string]$_.Value.text
                ($pName -match '(?i)volume|loudness|audiovolume|soundvolume') -or
                ($pText -match '(?i)volume|loudness')
            } | Select-Object -First 1

            if ($candidate) {
                return [string]$candidate.Name
            }
        }
    } catch {
        Write-EggLog "WARNING: Could not read project.json to detect volume property ($_). Falling back to '$defaultKey'."
    }

    return $defaultKey
}

function Send-WallpaperVolume100 {
    param(
        [Parameter(Mandatory = $true)][string]$EnginePath,
        [Parameter(Mandatory = $true)][string]$ArgumentList,
        [int]$Attempts = 2
    )

    $allSucceeded = $true
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $proc = Start-Process -FilePath $EnginePath -ArgumentList $ArgumentList -WindowStyle Hidden -PassThru -ErrorAction Stop
            if ($proc.WaitForExit(6000)) {
                if ($proc.ExitCode -ne 0) {
                    $allSucceeded = $false
                    Write-EggLog "WARNING: applyProperties attempt $attempt exited with code $($proc.ExitCode)."
                }
            } else {
                $allSucceeded = $false
                Write-EggLog "WARNING: applyProperties attempt $attempt (PID $($proc.Id)) exceeded 6 seconds; continuing."
            }
        } catch {
            $allSucceeded = $false
            Write-EggLog "WARNING: Could not send applyProperties attempt $($attempt): $_"
        }

        if ($attempt -lt $Attempts) {
            Start-Sleep -Milliseconds 900
        }
    }
    return $allSucceeded
}

function Find-TopLevelJsonObjectSpan {
    param(
        [Parameter(Mandatory = $true)][string]$JsonText,
        [Parameter(Mandatory = $true)][string]$KeyName
    )

    $tokens = [regex]::Matches($JsonText, '"(?:\\.|[^"\\])*"|\{|\}|\[|\]|:')
    $depth = 0
    $targetStart = -1

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $val = $tokens[$i].Value
        if ($val -eq '{' -or $val -eq '[') {
            $depth++
        } elseif ($val -eq '}' -or $val -eq ']') {
            $depth--
            if ($targetStart -ge 0 -and $depth -eq 1) {
                return @{
                    Start  = $targetStart
                    Length = ($tokens[$i].Index - $targetStart) + 1
                }
            }
        } elseif ($depth -eq 1 -and $val.StartsWith('"')) {
            if (($i + 2) -lt $tokens.Count -and $tokens[$i + 1].Value -eq ':' -and $tokens[$i + 2].Value -eq '{') {
                try {
                    $decodedKey = $val | ConvertFrom-Json
                } catch {
                    $decodedKey = $val.Trim('"')
                }
                if ($decodedKey -ieq $KeyName) {
                    $targetStart = $tokens[$i + 2].Index
                }
            }
        }
    }

    return $null
}

$script:audioOffPattern = '(?i)("(?:audiooutput|audio_output|videoaudiooutput|video_audio_output)"\s*:\s*)(false|0)(?=\s*[,}])'
$script:audioOnPattern  = '(?i)"(?:audiooutput|audio_output|videoaudiooutput|video_audio_output)"\s*:\s*(true|1)(?=\s*[,}])'

function Get-WallpaperEngineAudioState {
    param([Parameter(Mandatory = $true)][string]$ConfigJsonPath)

    $result = [pscustomobject]@{
        State   = 'Unknown'
        Scope   = 'Unknown'
        KeyName = $null
        Summary = ''
    }

    if (-not (Test-Path -LiteralPath $ConfigJsonPath -PathType Leaf)) {
        $result.Summary = "config.json not found at '$ConfigJsonPath'"
        return $result
    }

    $rawJson = [System.IO.File]::ReadAllText($ConfigJsonPath, [System.Text.Encoding]::UTF8)

    # Prefer inspecting the current Windows user's section via UTF-8 JSON parsing
    try {
        $parsed = $rawJson | ConvertFrom-Json -ErrorAction Stop
        $userProp = $parsed.PSObject.Properties | Where-Object { $_.Name -ieq $env:USERNAME } | Select-Object -First 1
        if ($userProp -and $userProp.Value.general -and $userProp.Value.general.user) {
            $userGeneral = $userProp.Value.general.user
            $audioProp = $userGeneral.PSObject.Properties | Where-Object {
                $_.Name -match '(?i)^(videoaudiooutput|video_audio_output|audiooutput|audio_output)$'
            } | Select-Object -First 1

            if ($audioProp) {
                $result.Scope = "User:$($userProp.Name)"
                $result.KeyName = $audioProp.Name
                $isEnabled = ($audioProp.Value -eq $true) -or ($audioProp.Value -eq 1)
                $result.State = if ($isEnabled) { 'On' } else { 'Off' }
                $result.Summary = "$($userProp.Name).general.user.$($audioProp.Name) = $($audioProp.Value)"
                return $result
            }
        }
    } catch {
        Write-EggLog "INFO: Structured JSON inspection of config.json fell back to regex ($_)."
    }

    # Fallback: whole-file regex check (covers non-standard or legacy config.json layouts)
    if ([regex]::IsMatch($rawJson, $script:audioOffPattern)) {
        $result.Scope = 'GlobalFallback'
        $result.State = 'Off'
        $result.Summary = 'Matched disabled audio output key in config.json (fallback scan)'
    } elseif ([regex]::IsMatch($rawJson, $script:audioOnPattern)) {
        $result.Scope = 'GlobalFallback'
        $result.State = 'On'
        $result.Summary = 'Matched enabled audio output key in config.json (fallback scan)'
    } else {
        $audioKeys = [regex]::Matches($rawJson, '(?i)"[^"\r\n]*(?:audio|sound)[^"\r\n]*"\s*:') | ForEach-Object { $_.Value } | Select-Object -Unique
        $result.Summary = if ($audioKeys) { $audioKeys -join '; ' } else { 'no audio-related JSON keys found' }
    }

    return $result
}

function Enable-WallpaperEngineGlobalAudio {
    param([Parameter(Mandatory = $true)][string]$ConfigJsonPath)

    $rawJson = [System.IO.File]::ReadAllText($ConfigJsonPath, [System.Text.Encoding]::UTF8)
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param([System.Text.RegularExpressions.Match]$m)
        if ($m.Groups[2].Value -eq '0') { return ($m.Groups[1].Value + '1') }
        return ($m.Groups[1].Value + 'true')
    }

    $patchedJson = $null
    $patchScope = 'GlobalFallback'
    $userSpan = Find-TopLevelJsonObjectSpan -JsonText $rawJson -KeyName $env:USERNAME
    if ($userSpan) {
        $userBlock = $rawJson.Substring($userSpan.Start, $userSpan.Length)
        if ([regex]::IsMatch($userBlock, $script:audioOffPattern)) {
            $patchedBlock = [regex]::Replace($userBlock, $script:audioOffPattern, $evaluator)
            $patchedJson = $rawJson.Substring(0, $userSpan.Start) + $patchedBlock + $rawJson.Substring($userSpan.Start + $userSpan.Length)
            $patchScope = "User:$env:USERNAME"
        }
    }

    if ($null -eq $patchedJson -and [regex]::IsMatch($rawJson, $script:audioOffPattern)) {
        $patchedJson = [regex]::Replace($rawJson, $script:audioOffPattern, $evaluator)
    }

    if ($null -eq $patchedJson) {
        return [pscustomobject]@{ Updated = $false; Scope = 'None'; BackupPath = $null }
    }

    # Keep a single clean backup of the original config.json rather than accumulating files.
    $backupPath = "$ConfigJsonPath.egg_backup"
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        Copy-Item -LiteralPath $ConfigJsonPath -Destination $backupPath -ErrorAction Stop
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($ConfigJsonPath, $patchedJson, $utf8NoBom)

    $verified = Get-WallpaperEngineAudioState -ConfigJsonPath $ConfigJsonPath
    if ($verified.State -ne 'On') {
        throw "config.json was written ($patchScope), but Audio Output could not be verified as enabled (state: $($verified.State))."
    }

    return [pscustomobject]@{
        Updated    = $true
        Scope      = $patchScope
        BackupPath = $backupPath
    }
}

function Invoke-MinimizeAllWindows {
    param([string]$ContextLabel)
    try {
        $shellApp = New-Object -ComObject Shell.Application -ErrorAction Stop
        $shellApp.MinimizeAll()
        Write-EggLog "All windows minimized ($ContextLabel)."
    } catch {
        Write-EggLog "WARNING: Could not minimize windows ($ContextLabel): $_"
    }
}

# ==============================================================================
# 4. Discover Steam, Wallpaper Engine & Target Egg Room Wallpaper
# ==============================================================================
$audioControllerReady = $false
$systemVolumeSet = $false

try {
    $steamLibraries = Get-SteamLibraryPaths
    Write-EggLog "Discovered $($steamLibraries.Count) Steam library path(s) via registry/VDF."

    $wpEngineExec = Find-WallpaperEngine -ConfiguredPath ([string]$cfg['wallpaperEnginePath']) -LibraryPaths $steamLibraries
    $eggWallpaperFile = Find-EggWallpaper -ConfiguredPath ([string]$cfg['wallpaperPath']) -TargetWorkshopIds $effectiveWorkshopIds -LibraryPaths $steamLibraries

    if (-not $wpEngineExec) {
        Write-EggLog 'ERROR: Wallpaper Engine executable (wallpaper64.exe / wallpaper32.exe) was not found.'
        Write-EggLog '=== SCRIPT FINISHED WITH ERROR ==='
        Invoke-LogRotation
        exit 1
    }
    Write-EggLog "Wallpaper Engine found: $wpEngineExec"

    if (-not $eggWallpaperFile) {
        Write-EggLog "ERROR: Egg Room wallpaper was not found for Workshop IDs [$($effectiveWorkshopIds -join ', ')]."
        Write-EggLog '=== SCRIPT FINISHED WITH ERROR ==='
        Invoke-LogRotation
        exit 1
    }
    Write-EggLog "Target wallpaper found: $eggWallpaperFile"

    $wpDir = Split-Path -Path $wpEngineExec -Parent
    $configJsonPath = Join-Path -Path $wpDir -ChildPath 'config.json'
    $audioState = Get-WallpaperEngineAudioState -ConfigJsonPath $configJsonPath
    $volumePropertyKey = Get-WallpaperVolumePropertyKey -WallpaperFilePath $eggWallpaperFile

    Write-EggLog "Wallpaper Engine global audio state: $($audioState.State) [$($audioState.Scope)] ($($audioState.Summary))."
    Write-EggLog "Detected wallpaper volume property key: '$volumePropertyKey'."

    if ($DryRun) {
        $volDesc = if ($null -ne $effectiveVolumePercent) { "$effectiveVolumePercent%" } else { 'unchanged' }
        Write-EggLog "Dry-run summary: Chance=1/$effectiveChance, SystemVolume=$volDesc, HideIcons=$($cfg['hideDesktopIcons']), MinimizeWindows=$($cfg['minimizeAllWindows']), EnableGlobalAudio=$($cfg['enableGlobalWallpaperAudio'])."
        Write-EggLog '=== DRY-RUN COMPLETED SUCCESSFULLY ==='
        exit 0
    }

    # Compile Core Audio helper only now that we know we are executing the live sequence
    if ($null -ne $effectiveVolumePercent) {
        try {
            $audioControllerReady = Initialize-MasterAudio
            Write-EggLog 'Core Audio controller initialized; system volume will be applied after Wallpaper Engine is muted.'
        } catch {
            Write-EggLog "WARNING: Audio controller initialization failed: $_"
        }
    }

    # ==========================================================================
    # 5. Execute Anti-Audio-Leak Egg Room Sequence
    # ==========================================================================
    # Step A: Mute Wallpaper Engine BEFORE changing Windows master volume or wallpaper
    try {
        Start-Process -FilePath $wpEngineExec -ArgumentList '-control mute' -WindowStyle Hidden -ErrorAction Stop | Out-Null
        Start-Sleep -Milliseconds 500
        Write-EggLog 'Wallpaper Engine muted prior to wallpaper switch.'
    } catch {
        Write-EggLog "WARNING: Initial Wallpaper Engine mute command failed: $_"
    }

    # Step B: Set Windows master volume (also clears Windows mute while WE is safely muted)
    if ($audioControllerReady -and $null -ne $effectiveVolumePercent) {
        try {
            $scalarVolume = [float]($effectiveVolumePercent / 100.0)
            [EggRoomAudio.MasterAudio]::SetVolume($scalarVolume)
            $systemVolumeSet = $true
            Write-EggLog "System master volume set to $effectiveVolumePercent%."
        } catch {
            Write-EggLog "WARNING: Failed to set system master volume: $_"
        }
    }

    # Step C: Hide desktop icons & minimize all open windows
    if ([bool]$cfg['hideDesktopIcons']) {
        try {
            Start-Process -FilePath $wpEngineExec -ArgumentList '-control hideIcons' -WindowStyle Hidden -ErrorAction Stop | Out-Null
            Write-EggLog 'Desktop icons hidden via Wallpaper Engine.'
        } catch {
            Write-EggLog "WARNING: Could not hide desktop icons: $_"
        }
    }

    if ([bool]$cfg['minimizeAllWindows']) {
        Invoke-MinimizeAllWindows -ContextLabel 'initial sweep'
    }

    # Step D: Open target Egg Room wallpaper while muted, then set its volume property to 100%
    Start-Process -FilePath $wpEngineExec -ArgumentList "-control openWallpaper -file `"$eggWallpaperFile`"" -WindowStyle Hidden -ErrorAction Stop | Out-Null
    Start-Sleep -Seconds 3

    $volumeProperties = @{}
    $volumeProperties[$volumePropertyKey] = 100
    $volumeJson = $volumeProperties | ConvertTo-Json -Compress
    $applyArguments = "-control applyProperties -properties RAW~($volumeJson)~END"

    Start-Sleep -Milliseconds 1200
    $initialVolumeOk = Send-WallpaperVolume100 -EnginePath $wpEngineExec -ArgumentList $applyArguments -Attempts 2
    Write-EggLog "Initial applyProperties sent ('$volumePropertyKey'=100, all succeeded: $initialVolumeOk)."

    # Step E: If Wallpaper Engine's global Audio Output is disabled, enable it ONLY AFTER
    # the Egg Room wallpaper is active so the restarted instance starts directly on Egg Room.
    $globalAudioEnabled = ($audioState.State -eq 'On')
    $shouldEnableGlobalAudio = [bool]$cfg['enableGlobalWallpaperAudio'] -and ($audioState.State -eq 'Off')

    if ($shouldEnableGlobalAudio) {
        $needsRestart = $true
        try {
            Write-EggLog 'Target wallpaper active; enabling global Wallpaper Engine Audio Output...'
            Start-Process -FilePath $wpEngineExec -ArgumentList '-control mute' -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Milliseconds 400

            $runningWp = @(Get-Process -Name wallpaper64, wallpaper32, ui64, ui32 -ErrorAction SilentlyContinue)
            if ($runningWp.Count -gt 0) {
                $runningWp | Stop-Process -Force -ErrorAction Stop
                # Wait cleanly until Wallpaper Engine processes have actually exited (up to 5s)
                $deadline = (Get-Date).AddSeconds(5)
                while ((Get-Date) -lt $deadline) {
                    if (-not (Get-Process -Name wallpaper64, wallpaper32, ui64, ui32 -ErrorAction SilentlyContinue)) {
                        break
                    }
                    Start-Sleep -Milliseconds 150
                }
            }

            # Re-check config.json AFTER process stop so Wallpaper Engine cannot overwrite our edit
            $postStopState = Get-WallpaperEngineAudioState -ConfigJsonPath $configJsonPath
            if ($postStopState.State -eq 'Off') {
                $patchResult = Enable-WallpaperEngineGlobalAudio -ConfigJsonPath $configJsonPath
                if ($patchResult.Updated) {
                    $globalAudioEnabled = $true
                    Write-EggLog "Global Audio Output enabled ($($patchResult.Scope)). Backup: $($patchResult.BackupPath)"
                }
            } elseif ($postStopState.State -eq 'On') {
                $globalAudioEnabled = $true
                Write-EggLog 'Global Audio Output was already enabled when re-checked after process stop.'
            } else {
                Write-EggLog "WARNING: Could not identify Audio Output key after process stop ($($postStopState.Summary))."
            }
        } catch {
            Write-EggLog "WARNING: Global audio config update failed: $_"
        } finally {
            if ($needsRestart) {
                try {
                    Start-Process -FilePath $wpEngineExec -ArgumentList '-silent' -WindowStyle Hidden -ErrorAction Stop | Out-Null
                    $startDeadline = (Get-Date).AddSeconds(5)
                    while ((Get-Date) -lt $startDeadline) {
                        if (Get-Process -Name wallpaper64, wallpaper32 -ErrorAction SilentlyContinue) {
                            break
                        }
                        Start-Sleep -Milliseconds 200
                    }
                    Start-Sleep -Milliseconds 1500

                    # Keep restarted instance muted while re-applying wallpaper & volume=100
                    Start-Process -FilePath $wpEngineExec -ArgumentList '-control mute' -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
                    Start-Sleep -Milliseconds 400
                    Start-Process -FilePath $wpEngineExec -ArgumentList "-control openWallpaper -file `"$eggWallpaperFile`"" -WindowStyle Hidden -ErrorAction Stop | Out-Null
                    Start-Sleep -Seconds 3
                    $postRestartVolumeOk = Send-WallpaperVolume100 -EnginePath $wpEngineExec -ArgumentList $applyArguments -Attempts 2
                    Write-EggLog "Post-restart wallpaper reselected; '$volumePropertyKey'=100 reapplied (all succeeded: $postRestartVolumeOk)."
                } catch {
                    Write-EggLog "WARNING: Wallpaper Engine restart/reapply step failed: $_"
                }
            }
        }
    }

    # Step F: Minimize any windows opened during loading, right before the audio reveal
    if ([bool]$cfg['minimizeAllWindows']) {
        Invoke-MinimizeAllWindows -ContextLabel 'final reveal'
    }

    # Step G: Unmute Wallpaper Engine as the VERY LAST audio step
    try {
        Start-Process -FilePath $wpEngineExec -ArgumentList '-control unmute' -WindowStyle Hidden -ErrorAction Stop | Out-Null
        Start-Sleep -Milliseconds 350
        Write-EggLog 'Wallpaper Engine unmuted — Egg Room reveal complete.'
    } catch {
        Write-EggLog "WARNING: Final Wallpaper Engine unmute failed: $_"
    }

    if (-not $systemVolumeSet -and $audioControllerReady -and $null -ne $effectiveVolumePercent) {
        try {
            [EggRoomAudio.MasterAudio]::SetVolume([float]($effectiveVolumePercent / 100.0))
            $systemVolumeSet = $true
            Write-EggLog "System master volume set to $effectiveVolumePercent% (fallback)."
        } catch {
            Write-EggLog "WARNING: Fallback system volume error: $_"
        }
    }

    if ($globalAudioEnabled -or -not [bool]$cfg['enableGlobalWallpaperAudio']) {
        Write-EggLog "SUCCESS: Egg Room sequence completed ('$volumePropertyKey'=100)."
    } else {
        Write-EggLog "PARTIAL SUCCESS: Wallpaper selected and '$volumePropertyKey'=100 sent, but global Audio Output could not be confirmed."
    }
} catch {
    Write-EggLog "FATAL ERROR: $_"
    if (-not $systemVolumeSet -and $audioControllerReady -and $null -ne $effectiveVolumePercent) {
        try {
            [EggRoomAudio.MasterAudio]::SetVolume([float]($effectiveVolumePercent / 100.0))
            Write-EggLog "System volume set to $effectiveVolumePercent% in error fallback."
        } catch {
            Write-EggLog "Error fallback audio failed: $_"
        }
    }
    Write-EggLog '=== SCRIPT FINISHED WITH ERROR ==='
    Invoke-LogRotation
    exit 1
}

Write-EggLog '=== SCRIPT FINISHED ==='
Invoke-LogRotation
