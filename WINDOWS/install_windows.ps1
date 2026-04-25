<#!
.SYNOPSIS
    Windows installer for TR-100 Machine Report (PowerShell version).

.DESCRIPTION
    Copies the TR-100 PowerShell script to a per-user install directory,
    wires up a `report` command for both PowerShell and Command Prompt,
    and configures your PowerShell profile so the report is easy to run
    and automatically displays on login/SSH sessions if desired.

.NOTES
    Run this on the Windows machine (not from WSL) using:

      pwsh   -File WINDOWS/install_windows.ps1
      # or
      powershell -ExecutionPolicy Bypass -File WINDOWS/install_windows.ps1

    The script uses only per-user locations and does not require admin rights.
#>

param(
    [switch]$NoAutoRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host '=========================================='
Write-Host 'TR-100 Machine Report - Windows Installer'
Write-Host '=========================================='
Write-Host ''

# Resolve paths relative to this script
$scriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceScript = Join-Path $scriptRoot 'TR-100-MachineReport.ps1'

if (-not (Test-Path $sourceScript)) {
    Write-Error "TR-100-MachineReport.ps1 not found next to this installer: $sourceScript"
    exit 1
}

# Choose install directory under the user profile so both PowerShell and Cmd can see it
$home = $HOME
if (-not $home) { $home = $env:USERPROFILE }
if (-not $home) {
    Write-Error 'Unable to determine user home directory.'
    exit 1
}

$installDir   = Join-Path $home 'TR100'
$targetScript = Join-Path $installDir 'TR-100-MachineReport.ps1'
$batchShim    = Join-Path $installDir 'report.cmd'

Write-Host "Install directory: $installDir"

if (-not (Test-Path $installDir)) {
    Write-Host 'Creating install directory...'
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

Write-Host 'Copying TR-100 PowerShell script...'
Copy-Item -Path $sourceScript -Destination $targetScript -Force

# Ensure the script is readable
if (-not (Test-Path $targetScript)) {
    Write-Error "Failed to install script to $targetScript"
    exit 1
}

Write-Host '✓ Script installed.'
Write-Host ''

# Create a batch shim so `report` works from Command Prompt and PowerShell via PATH
Write-Host 'Creating report.cmd shim...'
$batchContent = @"
@echo off
REM TR-100 Machine Report launcher
REM First try PowerShell 7 (pwsh), then Windows PowerShell 5.1

where pwsh >nul 2>&1
if %errorlevel%==0 (
    pwsh -NoLogo -NoProfile -File "%~dp0TR-100-MachineReport.ps1" %*
    goto :EOF
)

where powershell >nul 2>&1
if %errorlevel%==0 (
    powershell -NoLogo -NoProfile -File "%~dp0TR-100-MachineReport.ps1" %*
    goto :EOF
)

echo Could not find pwsh.exe or powershell.exe in PATH.
exit /b 1
"@

Set-Content -Path $batchShim -Value $batchContent -Encoding ASCII
Write-Host "✓ Created: $batchShim"
Write-Host ''

# Ensure install directory is on the per-user PATH so `report` works everywhere
Write-Host 'Configuring user PATH so `report` is available in Cmd/PowerShell...'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ([string]::IsNullOrWhiteSpace($userPath)) {
    $userPath = ''
}

$pathEntries = $userPath.Split(';') | Where-Object { $_ -ne '' }
$alreadyInPath = $pathEntries -contains $installDir

if (-not $alreadyInPath) {
    if ($userPath -and -not $userPath.EndsWith(';')) {
        $userPath += ';'
    }
    $userPath += $installDir
    [Environment]::SetEnvironmentVariable('Path', $userPath, 'User')
    Write-Host "✓ Added to user PATH: $installDir"
    Write-Host '  (You may need to open a new terminal/console for this to take effect.)'
} else {
    Write-Host '✓ Install directory already present in user PATH.'
}

Write-Host ''

# Configure PowerShell profile for convenient `report` function and optional auto-run
Write-Host 'Configuring PowerShell profile...'
try {
    $profilePath = $PROFILE.CurrentUserAllHosts
} catch {
    $profilePath = $PROFILE
}

if (-not $profilePath) {
    Write-Warning 'Could not determine PowerShell profile path; skipping profile configuration.'
} else {
    $profileDir = Split-Path -Parent $profilePath
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    if (-not (Test-Path $profilePath)) {
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }

    $profileContent = Get-Content -Path $profilePath -ErrorAction SilentlyContinue
    $marker = '# >>> TR-100 Machine Report configuration >>>'

    if ($profileContent -and ($profileContent -contains $marker)) {
        Write-Host '✓ Profile already configured for TR-100.'
    } else {
        Write-Host "Adding TR-100 configuration to profile: $profilePath"

        $autoRunLogic = if ($NoAutoRun) {
            '# Auto-run disabled by installer switch'
        } else {
            @'
        # Auto-run TR-100 on interactive or SSH sessions
        $isSSH = $env:SSH_CLIENT -or $env:SSH_CONNECTION
        $isInteractiveHost = $Host.Name -ne 'ServerRemoteHost'
        if ($isSSH -or $isInteractiveHost) {
            try { Show-TR100Report } catch { }
        }
'@
        }

        $profileAppend = @"
$marker
# Load TR-100 Machine Report script and define `report` function
if (Test-Path '$targetScript') {
    try {
        . '$targetScript'

        function report {
            [CmdletBinding()]
            param()
            Show-TR100Report
        }
$autoRunLogic
    } catch {
        Write-Warning 'Failed to load TR-100 Machine Report script from profile.'
    }
} else {
    Write-Warning 'TR-100 Machine Report script not found at $targetScript.'
}
# <<< TR-100 Machine Report configuration <<<
"@

        Add-Content -Path $profilePath -Value $profileAppend
        Write-Host '✓ Profile updated. New PowerShell sessions will have `report` available.'
    }
}

Write-Host ''

# Test run using the installed script
Write-Host '=========================================='
Write-Host 'Testing installed TR-100 Machine Report...'
Write-Host '=========================================='
Write-Host ''

try {
    # Prefer pwsh if available, otherwise invoke directly in this host
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        pwsh -NoLogo -NoProfile -File $targetScript
    } else {
        # In the current PowerShell process
        . $targetScript
    }
    Write-Host ''
    Write-Host '✓ Test completed.'
} catch {
    Write-Warning 'Test run encountered an error:'
    Write-Warning $_
}

Write-Host ''
Write-Host '=========================================='
Write-Host 'Installation complete.'
Write-Host '=========================================='
Write-Host ''
Write-Host 'You can now:'
Write-Host '  • Open a NEW PowerShell session and run:  report'
Write-Host '  • Open Command Prompt and run:           report'
Write-Host '  • SSH into this Windows machine; the report should display automatically.'
Write-Host ''
Write-Host 'To disable auto-run but keep the `report` command:'
Write-Host '  • Edit your PowerShell profile and remove or comment the auto-run section.'
Write-Host ''
Write-Host "Install directory: $installDir"
Write-Host "Profile file:     $profilePath"
Write-Host ''
