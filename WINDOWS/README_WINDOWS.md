# TR-100 Machine Report for Windows

This is the Windows-native implementation of the **TR-100 Machine Report**, originally written as a cross-platform bash script (`machine_report.sh`). It collects detailed system information using Windows APIs and renders a Unicode box-drawing report similar to the Unix version.

Features:

- Native **PowerShell** implementation (no WSL required)
- Works on **Windows PowerShell 5.1** and **PowerShell 7+ (pwsh)**
- Unicode box-drawing layout very close to the bash report
- Simple `report` command in **PowerShell** and **Command Prompt**
- Auto-runs on login / SSH sessions (configurable)
- Optional path to build a **standalone .exe** on Windows

---

## Files

All Windows-specific files live in the `WINDOWS/` folder:

- `TR-100-MachineReport.ps1` – core PowerShell implementation
  - `Get-TR100Report` – gathers system metrics and returns a PSCustomObject
  - `Show-TR100Report` – renders the Unicode table to the console
  - Auto-runs the report when executed directly as a script
- `install_windows.ps1` – installer for Windows
  - Installs the script to a per-user directory
  - Creates a `report.cmd` shim
  - Adds the install directory to your **user PATH**
  - Configures your PowerShell profile to expose a `report` function
  - Optionally auto-runs the report on interactive / SSH sessions
- `build_tr100_exe.ps1` (optional helper, see below) – helper for building a .exe via PS2EXE on Windows

---

## Requirements

- Windows 10/11 (or Server equivalent)
- At least one of:
  - **PowerShell 7+** (`pwsh`), or
  - **Windows PowerShell 5.1** (`powershell`)
- For best visual output:
  - Use **Windows Terminal** with a Unicode-capable font (e.g. Cascadia Code)
  - PowerShell 7+ uses UTF-8 by default; 5.1 is adjusted by the script

The script uses standard Windows cmdlets and CIM classes:

- `Get-CimInstance` (Win32_OperatingSystem, Win32_ComputerSystem, Win32_Processor, Win32_LogicalDisk)
- `Get-NetIPAddress`, `Get-DnsClientServerAddress` (if available)
- `Get-Counter` (for CPU load-style metrics)

If some of these cmdlets are missing (very old or restricted environments), the report will still run but some fields may fall back to defaults.

---

## Installation

> Run these commands **on the Windows machine**, from the root of this repo.

### 1. Copy the repo to Windows

Clone or copy this repo to a folder on your Windows system. For example:

```powershell
cd C:\Users\YourUser\Documents\usgc-machine-report
```

### 2. Run the Windows installer

From that repo root, run one of the following:

```powershell
# Preferred (PowerShell 7+)
pwsh -File .\WINDOWS\install_windows.ps1

# Or, Windows PowerShell 5.1
powershell -ExecutionPolicy Bypass -File .\WINDOWS\install_windows.ps1
```

By default, the installer:

1. Creates an install directory under your home:
   - `C:\Users\YourUser\TR100` (per-user, no admin required)
2. Copies `TR-100-MachineReport.ps1` there
3. Creates a **batch shim** at `C:\Users\YourUser\TR100\report.cmd`
4. Adds that directory to your **user PATH**
5. Updates your **PowerShell profile** to:
   - Dot-source the installed script so its functions are always available
   - Define a `report` function that runs `Show-TR100Report`
   - **Auto-run** the report when you start an interactive session or connect via SSH
6. Runs a **test report** once at the end

If you do **not** want auto-run, you can install with:

```powershell
pwsh -File .\WINDOWS\install_windows.ps1 -NoAutoRun
# or
powershell -ExecutionPolicy Bypass -File .\WINDOWS\install_windows.ps1 -NoAutoRun
```

In that case the `report` command is still available, but the report will not run automatically on login.

---

## Usage

After installing (and opening a **new** terminal so PATH/profile changes apply):

### PowerShell

```powershell
# From any PowerShell session
report          # preferred, from profile

# Or directly
Show-TR100Report

# Or execute the installed script directly
& "$HOME\TR100\TR-100-MachineReport.ps1"
```

### Command Prompt (cmd.exe)

```bat
C:\> report
```

Because the installer adds the TR100 directory to your **user PATH** and places `report.cmd` there, `report` should work in both **cmd.exe** and **PowerShell**.

### SSH / Remote sessions

If you connect to the Windows machine via **SSH** (OpenSSH), the installer’s profile snippet checks for `$env:SSH_CLIENT` / `$env:SSH_CONNECTION` and treats those sessions as remote:

- On SSH connection, your PowerShell profile will load and automatically run `Show-TR100Report`.
- The report should appear **at the top of the SSH terminal** immediately after login.

This mirrors the behavior of the Unix bash installer and is suitable for quick remote checks.

If you used `-NoAutoRun`, the report will not auto-run on SSH; you can still type `report` manually.

---

## Controlling the auto-run behavior

The installer appends a clearly marked block to your PowerShell profile (CurrentUserAllHosts) similar to:

```powershell
# >>> TR-100 Machine Report configuration >>>
if (Test-Path 'C:\Users\YourUser\TR100\TR-100-MachineReport.ps1') {
    try {
        . 'C:\Users\YourUser\TR100\TR-100-MachineReport.ps1'

        function report {
            [CmdletBinding()]
            param()
            Show-TR100Report
        }

        # Auto-run TR-100 on interactive or SSH sessions
        $isSSH = $env:SSH_CLIENT -or $env:SSH_CONNECTION
        $isInteractiveHost = $Host.Name -ne 'ServerRemoteHost'
        if ($isSSH -or $isInteractiveHost) {
            try { Show-TR100Report } catch { }
        }
    } catch {
        Write-Warning 'Failed to load TR-100 Machine Report script from profile.'
    }
} else {
    Write-Warning 'TR-100 Machine Report script not found at C:\Users\YourUser\TR100.'
}
# <<< TR-100 Machine Report configuration <<<
```

You can adjust behavior by editing your profile:

- To **disable auto-run** but keep `report`:
  - Comment out or remove the `if ($isSSH -or $isInteractiveHost) { ... }` block.
- To **disable everything**:
  - Remove the entire TR-100 block between the marker comments.

To open your profile quickly:

```powershell
notepad $PROFILE
# or in pwsh
code $PROFILE    # if you use VS Code
```

---

## Building a standalone .exe (optional)

You can build a Windows **.exe** wrapper for the report using the community `ps2exe` tool.

> NOTE: Building the .exe must be done on a **Windows** machine with PowerShell. The repo includes a helper script to make this easier.

### 1. Install PS2EXE

In an elevated or user PowerShell session on Windows:

```powershell
Install-Module -Name ps2exe -Scope CurrentUser
# If prompted about the repository or untrusted modules, review and accept as desired.
```

### 2. Use the helper script (recommended)

From the `WINDOWS` directory of this repo on Windows:

```powershell
cd PATH\TO\usgc-machine-report\WINDOWS
pwsh -File .\build_tr100_exe.ps1
# or
powershell -ExecutionPolicy Bypass -File .\build_tr100_exe.ps1
```

By default this will:

- Look for `ps2exe` (specifically `Invoke-ps2exe`)
- If available, build `TR-100-MachineReport.exe` in the same folder
- Use `TR-100-MachineReport.ps1` as the input script

You can then copy the resulting `.exe` anywhere on your Windows PATH or run it directly.

If `ps2exe` is **not** installed, the helper script will print the exact `Install-Module` command you need to run.

### 3. Manual PS2EXE usage (if you prefer)

Once `ps2exe` is installed, you can also run it yourself:

```powershell
Import-Module ps2exe

Invoke-ps2exe -inputFile .\WINDOWS\TR-100-MachineReport.ps1 `
              -outputFile .\WINDOWS\TR-100-MachineReport.exe `
              -noConfigFile
```

Refer to the `ps2exe` documentation for additional options (icons, version info, etc.).

---

## Uninstalling

To remove the Windows TR-100 installation:

1. **Delete the installed files**:
   - Remove `C:\Users\YourUser\TR100` (or wherever you installed it)
2. **Remove PATH entry**:
   - Open *Environment Variables* → *User variables* → edit `Path`
   - Remove the `TR100` directory entry
3. **Clean your PowerShell profile**:
   - Edit `$PROFILE`
   - Remove the block between `# >>> TR-100 Machine Report configuration >>>` and `# <<< TR-100 Machine Report configuration <<<`

After doing this and opening a new terminal, the `report` command and auto-run behavior will no longer be present.

---

## Troubleshooting

- **Unicode boxes look wrong or show as ? or garbled characters**
  - Use **Windows Terminal** with a font like Cascadia Code
  - Make sure you’re not in a very old legacy console
  - On PowerShell 5.1, the script attempts to force UTF-8 output; if that fails, you may need to adjust your console encoding manually.

- **`report` not found in cmd.exe or PowerShell**
  - Open a **new** terminal – PATH is read when the process starts
  - Check that `C:\Users\YourUser\TR100` is in your user PATH
  - Ensure `report.cmd` exists in that directory

- **Profile errors on startup**
  - Open `$PROFILE` in a text editor
  - Temporarily comment out the TR-100 block to verify the rest of your profile is fine

If you run into issues or want behavior tweaked (different install path, different auto-run rules, etc.), you can adjust the installer and profile snippets directly or ask for a tailored variant.
