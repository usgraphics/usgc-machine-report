# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the TR-100 Machine Report installation.

## Project Overview

**TR-100 Machine Report** is a lightweight bash-based system information tool that displays machine stats in a tabular format. It's designed to run automatically on terminal/SSH login and can be invoked on-demand with the `report` command.

This is a fork maintained by @RealEmmettS with improvements for:
- Modern Debian/Raspberry Pi OS compatibility (`lastlog2` support)
- Non-ZFS filesystem support (ext4, btrfs, etc.)
- ARM64 architecture (Raspberry Pi tested)
- Graceful fallback mechanisms

## Project Philosophy

**IMPORTANT**: This project follows a "direct source editing" philosophy:
- ✅ Encourage users to directly modify `machine_report.sh` for customization
- ❌ Do NOT create config files, templates, or abstraction layers
- ❌ Do NOT add complexity through modules or DSLs
- ✅ Keep it as a single, readable bash script

When users request customizations, guide them to edit the source directly at specific line numbers.

## Installation Workflow

When a user asks to install TR-100 Machine Report, you have **two options**:

### Option 1: Automated Installation (Recommended)

**Use the provided install.sh script** for fully automated setup:

```bash
cd ~/git-projects
gh repo clone RealEmmettS/usgc-machine-report
cd RealEmmettS-usgc-machine-report
./install.sh
```

The `install.sh` script automatically:
- ✅ Detects OS and architecture
- ✅ Installs `lastlog2` on Debian/Ubuntu/Raspberry Pi OS
- ✅ Backs up existing installations
- ✅ Copies script to `~/.machine_report.sh`
- ✅ Makes it executable
- ✅ Configures `.bashrc` with alias and auto-run
- ✅ Tests the installation
- ✅ Provides clear feedback and next steps

**This is the easiest method and should be your default choice.**

### Option 2: Manual Installation (Advanced)

Follow these steps for manual control:

#### 1. Clone the Repository

```bash
cd ~/git-projects
gh repo clone RealEmmettS/usgc-machine-report
```

**Expected location**: `~/git-projects/RealEmmettS-usgc-machine-report/`

#### 2. Check System Compatibility

```bash
# Check OS
cat /etc/os-release | grep -E "^ID=|^VERSION="

# Check architecture
uname -m

# Check for lastlog or lastlog2
which lastlog lastlog2
```

### 3. Install Dependencies

**For Debian/Ubuntu/Raspberry Pi OS (Trixie+)**:
```bash
sudo apt install -y lastlog2
```

**Note**: The script has fallback logic:
- Tries `lastlog2` first (modern systems)
- Falls back to `lastlog` (legacy systems)
- Gracefully handles neither being available

### 4. Install the Script

```bash
# Copy to home directory as hidden file
cp ~/git-projects/RealEmmettS-usgc-machine-report/machine_report.sh ~/.machine_report.sh

# Make executable
chmod +x ~/.machine_report.sh
```

### 5. Configure .bashrc

Add these lines to the user's `~/.bashrc`:

```bash
# Machine Report alias - run anytime with 'report' command
alias report='~/.machine_report.sh'

# Run Machine Report only when in interactive mode
if [[ $- == *i* ]]; then
    ~/.machine_report.sh
fi
```

**Implementation**:
```bash
cat >> ~/.bashrc << 'EOF'

# Machine Report alias - run anytime with 'report' command
alias report='~/.machine_report.sh'

# Run Machine Report only when in interactive mode
if [[ $- == *i* ]]; then
    ~/.machine_report.sh
fi
EOF
```

### 6. Test Installation

```bash
# Run directly
~/.machine_report.sh

# Test alias (in new shell)
bash -c "source ~/.bashrc && type -a report"
```

**Expected output**: A tabular report showing OS, network, CPU, disk, memory, and uptime information.

## Common Customizations

When users ask to customize the report, guide them to edit `~/.machine_report.sh` at these locations:

### Change Header Text
**Line 20**: `report_title="UNITED STATES GRAPHICS COMPANY"`

Example:
```bash
nano ~/.machine_report.sh
# Change line 20 to:
report_title="YOUR CUSTOM HEADER"
```

### Change ZFS Pool Name
**Line 23**: `zfs_filesystem="zroot/ROOT/os"`

Example:
```bash
# For users with ZFS, change to their pool name
zfs_filesystem="tank/ROOT/default"
```

### Adjust Column Widths
**Lines 11-16**: Global width variables
```bash
MIN_NAME_LEN=5
MAX_NAME_LEN=13
MIN_DATA_LEN=20
MAX_DATA_LEN=32
BORDERS_AND_PADDING=7
```

### Change Disk Partition (Non-ZFS)
**Line 524**: `root_partition="/"`

## Troubleshooting

### Issue: "lastlog: command not found"

**Solution**: Install `lastlog2` package
```bash
sudo apt install -y lastlog2
```

The script will automatically detect and use it. No code changes needed.

### Issue: CPU frequency shows blank on Raspberry Pi

**Explanation**: This is normal on some ARM systems. The script continues working correctly; this field just won't be populated.

**If user wants to fix**: Guide them to check `/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq` and potentially modify line 394 in the script.

### Issue: Wrong disk partition shown

**For non-ZFS systems**:
- Edit line 524: Change `root_partition="/"` to desired mount point
- Example: `root_partition="/home"` or `root_partition="/mnt/data"`

**For ZFS systems**:
- Edit line 23: Change `zfs_filesystem="zroot/ROOT/os"` to their pool
- Use `zfs list` to find the correct filesystem name

### Issue: Script runs but doesn't appear on login

**Check**:
1. Verify `.bashrc` has the interactive check and script call
2. Check if the script is executable: `ls -l ~/.machine_report.sh`
3. Verify path is correct in `.bashrc`

**Fix**:
```bash
chmod +x ~/.machine_report.sh
source ~/.bashrc
```

## File Structure

```
RealEmmettS-usgc-machine-report/
├── CLAUDE.md              # This file - Claude Code instructions
├── README.md              # User-facing documentation
├── LICENSE                # BSD 3-Clause License
├── .gitignore            # Git ignore rules
└── machine_report.sh      # Main script (single file!)
```

## Script Architecture

The `machine_report.sh` script is organized into sections:

1. **Lines 1-9**: Header comments and license
2. **Lines 10-23**: Global variables and configuration
3. **Lines 25-68**: Cross-platform compatibility framework (detect_os, command_exists, file_readable, is_ipv4, OS_TYPE detection, Bash version check)
4. **Lines 70-284**: Utility functions (max_length, set_current_len, PRINT_* functions, bar_graph, get_ip_addr)
5. **Lines 286-313**: OS information detection (Linux and macOS support)
6. **Lines 315-357**: Network information (hostname, IPs, DNS, user)
7. **Lines 359-423**: CPU information (cross-platform: lscpu, sysctl, /proc)
8. **Lines 425-439**: Load averages (cross-platform: /proc/loadavg, sysctl, uptime)
9. **Lines 441-493**: Memory information (cross-platform: /proc/meminfo, vm_stat)
10. **Lines 495-549**: Disk information (ZFS and standard filesystem support)
11. **Lines 551-617**: Last login detection (lastlog2/lastlog fallback) and system uptime (cross-platform)
12. **Lines 619-633**: Graph generation (CPU load, memory, disk)
13. **Lines 635-684**: Output rendering (PRINT_* function calls)

### Cross-Platform Support (v1.2.0+)

The script now includes a **cross-platform compatibility framework** that automatically detects the OS and uses appropriate commands:

**Helper Functions (Lines 30-55)**:
- `detect_os()` - Returns "macos", "linux", "bsd", or "unknown"
- `command_exists()` - Safely checks if a command is available
- `file_readable()` - Checks if a file exists and is readable
- `is_ipv4()` - Validates IPv4 address format

**Platform-Specific Commands**:
- **macOS**: Uses `sysctl`, `vm_stat`, `scutil`, `sw_vers` for native macOS data
- **Linux**: Uses `lscpu`, `/proc/meminfo`, `/proc/cpuinfo`, `lastlog2`/`lastlog`
- **BSD**: Partial support with fallback mechanisms

**Key Design Pattern**: The script checks `$OS_TYPE` variable throughout and branches to platform-specific implementations. This maintains the single-file philosophy while supporting multiple platforms.

## Important Implementation Notes

### DO NOT modify the script automatically

- When users request installation, install it as-is
- When users request customizations, **guide them** to edit specific lines
- Do not write custom wrapper scripts or config files
- Follow the project's "edit the source" philosophy

### Testing Installations

After installation, ALWAYS test by running:
```bash
~/.machine_report.sh
```

Look for:
- ✅ Clean tabular output with box-drawing characters
- ✅ No error messages (except harmless warnings)
- ✅ Last login info appears (if lastlog2/lastlog installed)
- ✅ Disk, CPU, memory stats populate

### Version Information

- **Upstream**: usgraphics/usgc-machine-report (original)
- **This fork**: RealEmmettS/usgc-machine-report (enhanced)
- **Current version**: v1.2.0-RealEmmettS (2025-11-10) - PRODUCTION READY

## Development Workflow

This is a fork. When making changes:

1. **Test on multiple platforms** (Linux, macOS, Raspberry Pi)
2. **Maintain single-file design** (no modules/dependencies)
3. **Use helper functions** (`command_exists`, `file_readable`) for safe checks
4. **Update README.md** with changes
5. **Update CHANGELOG** section in README
6. **Update this CLAUDE.md** with any line number changes
7. **Tag releases** with `vX.Y.Z-RealEmmettS` format

### Testing Checklist

When making code changes, test on:
- ✅ Linux (Debian/Ubuntu) with modern tools (lastlog2)
- ✅ Linux (older systems) with legacy tools (lastlog)
- ✅ Raspberry Pi OS (ARM64) - primary target
- ✅ macOS (both Apple Silicon and Intel)
- ⚠️ BSD (optional - best effort support)

**Key areas to verify**:
- OS detection works correctly
- CPU info displays (especially frequency on ARM)
- Memory stats calculate properly (different on macOS)
- Disk usage shows correctly (ZFS vs standard filesystems)
- Last login detection (lastlog2 vs lastlog vs unavailable)
- No bash errors or unhandled edge cases

## License

BSD 3-Clause License (original project)
Fork modifications also BSD 3-Clause (RealEmmettS)

When helping users, respect the license terms and maintain attribution to US Graphics Company for the original work.

## Contact & Resources

- **Fork maintainer**: @RealEmmettS (github@emmetts.dev)
- **Original project**: https://github.com/usgraphics/usgc-machine-report
- **This fork**: https://github.com/RealEmmettS/usgc-machine-report
- **US Graphics Company**: https://x.com/usgraphics

## Quick Reference Commands

```bash
# Install from scratch (RECOMMENDED - uses install.sh)
cd ~/git-projects && \
gh repo clone RealEmmettS/usgc-machine-report && \
cd RealEmmettS-usgc-machine-report && \
./install.sh

# Manual installation (advanced)
cd ~/git-projects && gh repo clone RealEmmettS/usgc-machine-report && \
cp ~/git-projects/RealEmmettS-usgc-machine-report/machine_report.sh ~/.machine_report.sh && \
chmod +x ~/.machine_report.sh && \
cat >> ~/.bashrc << 'EOF'

# Machine Report alias - run anytime with 'report' command
alias report='~/.machine_report.sh'

# Run Machine Report only when in interactive mode
if [[ $- == *i* ]]; then
    ~/.machine_report.sh
fi
EOF

# Run the report
~/.machine_report.sh
# or simply:
report

# Edit for customization
nano ~/.machine_report.sh

# Test across platforms
./machine_report.sh  # Should work on Linux, macOS, BSD

# Uninstall
rm ~/.machine_report.sh
# Then remove the lines from ~/.bashrc manually
```
