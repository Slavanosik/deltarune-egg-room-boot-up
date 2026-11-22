<#
.SYNOPSIS
    Installs or removes the Windows Task Scheduler logon task for Deltarune Egg Room Boot Up.

.DESCRIPTION
    Registers a zero-flash Windows logon task using wscript.exe + Launch-EggRoom.vbs so that
    EggRoom.ps1 rolls its configured probability every time you sign into Windows without
    flashing a PowerShell window.

.PARAMETER TaskName
    Name of the Scheduled Task in Windows Task Scheduler.
    Defaults to "Deltarune Egg Room Boot Up".

.PARAMETER DelaySeconds
    Seconds to wait after Windows logon before running the script (allows Wallpaper Engine
    to initialize cleanly). Defaults to 10.

.PARAMETER Elevated
    Register the task with RunLevel Highest (requires running this installer as Administrator).
    Not required for standard Steam / Wallpaper Engine installations.

.PARAMETER Uninstall
    Removes the scheduled task instead of installing it.

.EXAMPLE
    .\Install-EggTask.ps1
    Registers the logon task using the current folder.

.EXAMPLE
    .\Install-EggTask.ps1 -DelaySeconds 15
    Registers the logon task with a 15-second startup delay.

.EXAMPLE
    .\Install-EggTask.ps1 -Uninstall
    Removes the scheduled task cleanly.
#>
[CmdletBinding()]
param(
    [string]$TaskName = 'Deltarune Egg Room Boot Up',

    [ValidateRange(0, 300)]
    [int]$DelaySeconds = 10,

    [switch]$Elevated,

    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

if ($Uninstall) {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed scheduled task: '$TaskName'." -ForegroundColor Green
    } else {
        Write-Host "Scheduled task '$TaskName' was not found (already removed)." -ForegroundColor Yellow
    }
    exit 0
}

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$mainScriptPath = Join-Path -Path $scriptDir -ChildPath 'EggRoom.ps1'
$vbsLauncherPath = Join-Path -Path $scriptDir -ChildPath 'Launch-EggRoom.vbs'
$configPath = Join-Path -Path $scriptDir -ChildPath 'config.json'

if (-not (Test-Path -LiteralPath $mainScriptPath -PathType Leaf)) {
    throw "Main script not found at '$mainScriptPath'. Run Install-EggTask.ps1 from the repository folder."
}
if (-not (Test-Path -LiteralPath $vbsLauncherPath -PathType Leaf)) {
    throw "Silent launcher not found at '$vbsLauncherPath'. Run Install-EggTask.ps1 from the repository folder."
}

# Read configured chance for accurate status output
$configuredChance = 100
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    try {
        $cfg = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($cfg.chance -and [int]$cfg.chance -ge 1) {
            $configuredChance = [int]$cfg.chance
        }
    } catch {
        # Fall back to default display value
    }
}

$wscriptPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\wscript.exe'
$arguments = '//B //Nologo "{0}"' -f $vbsLauncherPath

$action = New-ScheduledTaskAction -Execute $wscriptPath -Argument $arguments -WorkingDirectory $scriptDir
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
if ($DelaySeconds -gt 0) {
    $trigger.Delay = "PT${DelaySeconds}S"
}

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

$runLevel = if ($Elevated) { 'Highest' } else { 'Limited' }
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel $runLevel

Register-ScheduledTask `
    -TaskName $TaskName `
    -Description 'Probabilistic Deltarune Egg Room easter egg for Windows logon + Wallpaper Engine.' `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Force | Out-Null

$task = Get-ScheduledTask -TaskName $TaskName
Write-Host ''
Write-Host "Scheduled task registered: $TaskName" -ForegroundColor Green
Write-Host "  Launcher : wscript.exe $arguments"
Write-Host "  Script   : $mainScriptPath"
Write-Host "  Trigger  : At logon for '$env:USERNAME' (${DelaySeconds}s delay)"
Write-Host "  RunLevel : $runLevel"
Write-Host "  Chance   : 1 / $configuredChance (configurable in config.json)"
Write-Host "  State    : $($task.State)"
Write-Host "  Log file : $(Join-Path $scriptDir 'egg_log.txt')"
Write-Host ''
Write-Host "Tip: Run '.\EggRoom.ps1 -DryRun' to verify setup, or '.\EggRoom.ps1 -Force' to test it live." -ForegroundColor Cyan
