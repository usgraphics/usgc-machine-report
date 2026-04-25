<#
.SYNOPSIS
    Helper script to build a TR-100 Machine Report .exe on Windows using PS2EXE.

.DESCRIPTION
    This script is intended to be run on a Windows machine from the WINDOWS
    directory of the usgc-machine-report repo. It looks for the PS2EXE module
    (Invoke-ps2exe). If available, it compiles TR-100-MachineReport.ps1 into a
    standalone TR-100-MachineReport.exe.

    If PS2EXE is not installed, it prints clear instructions for installing it.

.EXAMPLE
    pwsh -File .\build_tr100_exe.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\build_tr100_exe.ps1

.NOTES
    This does not modify PATH or profiles; it just builds the .exe.
#>

[CmdletBinding()]
param(
    [string]$OutputFile = 'TR-100-MachineReport.exe'
)

$ErrorActionPreference = 'Stop'

Write-Host '=========================================='
Write-Host 'TR-100 Machine Report - EXE Builder (PS2EXE)'
Write-Host '=========================================='
Write-Host ''

# Resolve paths relative to this script
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$inputFile  = Join-Path $scriptRoot 'TR-100-MachineReport.ps1'

if (-not (Test-Path $inputFile)) {
    Write-Error "Input script not found: $inputFile"
    exit 1
}

# Try to find PS2EXE (Invoke-ps2exe)
$ps2exeCmd = Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue
if (-not $ps2exeCmd) {
    Write-Warning 'PS2EXE (Invoke-ps2exe) was not found on this system.'
    Write-Host  ''
    Write-Host  'To install PS2EXE, run:'
    Write-Host  '  Install-Module -Name ps2exe -Scope CurrentUser' -ForegroundColor Yellow
    Write-Host  ''
    Write-Host  'Then re-run this script:'
    Write-Host  '  pwsh      -File .\build_tr100_exe.ps1' -ForegroundColor Yellow
    Write-Host  '  # or' -ForegroundColor Yellow
    Write-Host  '  powershell -ExecutionPolicy Bypass -File .\build_tr100_exe.ps1' -ForegroundColor Yellow
    exit 1
}

Write-Host "Using PS2EXE command: $($ps2exeCmd.Source)" -ForegroundColor Green

# Build output path
if (-not [System.IO.Path]::IsPathRooted($OutputFile)) {
    $outputPath = Join-Path $scriptRoot $OutputFile
} else {
    $outputPath = $OutputFile
}

Write-Host "Input : $inputFile"
Write-Host "Output: $outputPath"
Write-Host ''

try {
    Import-Module ($ps2exeCmd.Source) -ErrorAction SilentlyContinue | Out-Null
} catch {
    # If we can't import explicitly, Invoke-ps2exe should still work if exposed as a function/cmdlet
}

try {
    Invoke-ps2exe -inputFile $inputFile -outputFile $outputPath -noConfigFile
    Write-Host ''
    Write-Host '=========================================='
    Write-Host 'Build completed successfully.' -ForegroundColor Green
    Write-Host '=========================================='
    Write-Host "Executable created at: $outputPath"
    Write-Host ''
    Write-Host 'You can now run this .exe directly from Windows Explorer, cmd.exe, or PowerShell.'
} catch {
    Write-Error 'PS2EXE build failed:'
    Write-Error $_
    exit 1
}
