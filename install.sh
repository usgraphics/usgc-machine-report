#!/bin/bash
# TR-100 Machine Report - Automated Installation Script
# Copyright © 2025, Emmett Shaughnessy (RealEmmettS)
# Based on original work by U.S. Graphics, LLC (BSD-3-Clause)

set -e  # Exit on error

echo "=========================================="
echo "TR-100 Machine Report Installation"
echo "=========================================="
echo ""

# Detect OS type
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
    OS_NAME="macos"
    if command -v sw_vers &> /dev/null; then
        MACOS_VERSION=$(sw_vers -productVersion 2>/dev/null)
        echo "✓ Detected OS: macOS ${MACOS_VERSION}"
    else
        echo "✓ Detected OS: macOS (version unknown)"
    fi
    IS_RPI=0
elif [ -f /etc/os-release ]; then
    OS_TYPE="linux"
    . /etc/os-release
    OS_NAME="${ID}"
    OS_VERSION="${VERSION_ID}"
    echo "✓ Detected OS: ${PRETTY_NAME}"

    # Special handling for Raspberry Pi OS detection
    if [ -f /proc/device-tree/model ]; then
        RPI_MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
        if [[ "$RPI_MODEL" == *"Raspberry Pi"* ]]; then
            echo "✓ Raspberry Pi detected: $RPI_MODEL"
            IS_RPI=1
        else
            IS_RPI=0
        fi
    else
        IS_RPI=0
    fi
else
    OS_TYPE="unknown"
    echo "⚠ Warning: Could not detect OS. Proceeding anyway..."
    OS_NAME="unknown"
    IS_RPI=0
fi

# Check architecture
ARCH=$(uname -m)
echo "✓ Architecture: ${ARCH}"

# Check Bash version
BASH_MAJOR="${BASH_VERSINFO[0]}"
BASH_MINOR="${BASH_VERSINFO[1]}"
echo "✓ Bash version: ${BASH_VERSION}"

if [ "$BASH_MAJOR" -lt 4 ]; then
    echo ""
    echo "⚠ WARNING: Bash 4.0+ is recommended for best compatibility"
    echo "  Current version: ${BASH_VERSION}"
    if [ "$OS_TYPE" = "macos" ]; then
        echo ""
        echo "  macOS ships with Bash 3.2 by default."
        echo "  For full compatibility, install Bash 4+ via Homebrew:"
        echo "    brew install bash"
        echo ""
        echo "  The script will still work but may show some fields differently."
    fi
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 1
    fi
fi
echo ""

# Check if script exists in current directory
if [ ! -f "machine_report.sh" ]; then
    echo "❌ Error: machine_report.sh not found in current directory"
    echo "   Please run this script from the repository root:"
    echo "   cd ~/git-projects/RealEmmettS-usgc-machine-report && ./install.sh"
    exit 1
fi

# Install dependencies based on OS
echo "=========================================="
echo "Installing Dependencies"
echo "=========================================="
echo ""

if [ "$OS_TYPE" = "macos" ]; then
    echo "macOS detected - no package installation needed"
    echo "✓ macOS has all required built-in commands (sysctl, vm_stat, etc.)"
    echo ""
    echo "Note: The script will use native macOS commands for system info."
    if [ "$BASH_MAJOR" -lt 4 ]; then
        echo ""
        echo "  Optional: For best experience, install Bash 4+:"
        echo "    brew install bash"
    fi
    echo "✓ Dependencies check complete"

elif [[ "$OS_NAME" == "debian" ]] || [[ "$OS_NAME" == "ubuntu" ]] || [[ "$OS_NAME" == "raspbian" ]]; then
    echo "Installing lastlog2 for Debian/Ubuntu/Raspberry Pi OS..."

    # Check if lastlog2 is already installed
    if command -v lastlog2 &> /dev/null; then
        echo "✓ lastlog2 already installed"
    else
        # Check if running with sudo privileges
        if [ "$EUID" -ne 0 ]; then
            echo "Note: This requires sudo privileges for package installation."

            # Raspberry Pi optimization: Use quieter apt flags to reduce output
            if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "armv7l" ]]; then
                echo "  Detected ARM architecture - using optimized installation..."
                sudo apt-get update -qq > /dev/null 2>&1
                sudo apt-get install -y -qq lastlog2 > /dev/null 2>&1 && \
                    echo "✓ lastlog2 installed successfully" || \
                    echo "⚠ Warning: lastlog2 installation had issues, but script will continue"
            else
                sudo apt update
                sudo apt install -y lastlog2
            fi
        else
            # Running as root
            if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "armv7l" ]]; then
                apt-get update -qq > /dev/null 2>&1
                apt-get install -y -qq lastlog2 > /dev/null 2>&1 && \
                    echo "✓ lastlog2 installed successfully" || \
                    echo "⚠ Warning: lastlog2 installation had issues, but script will continue"
            else
                apt update
                apt install -y lastlog2
            fi
        fi
    fi

    echo "✓ Dependencies check complete"

elif [[ "$OS_NAME" == "arch" ]] || [[ "$OS_NAME" == "manjaro" ]]; then
    echo "Arch-based system detected - no special packages needed"
    echo "✓ Script will use standard Linux commands"
    echo "✓ Dependencies check complete"

else
    echo "⚠ Unknown/Other Linux system detected"
    echo "  The script should still work with standard commands."
    echo "  If you encounter issues, check that these are available:"
    echo "    - lscpu (or fallback to /proc/cpuinfo)"
    echo "    - df"
    echo "    - uptime"
    echo "✓ Dependencies check complete"
fi

echo ""

# Install script to home directory
echo "=========================================="
echo "Installing Script"
echo "=========================================="
echo ""

TARGET_FILE="$HOME/.machine_report.sh"

if [ -f "$TARGET_FILE" ]; then
    echo "⚠ Warning: $TARGET_FILE already exists"
    read -p "  Overwrite? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Installation cancelled by user"
        exit 1
    fi
    echo "  Backing up existing file to ${TARGET_FILE}.backup"
    cp "$TARGET_FILE" "${TARGET_FILE}.backup"
fi

echo "Copying machine_report.sh to $TARGET_FILE..."
cp machine_report.sh "$TARGET_FILE"
chmod +x "$TARGET_FILE"
echo "✓ Script installed and made executable"
echo ""

# Configure .bashrc
echo "=========================================="
echo "Configuring .bashrc"
echo "=========================================="
echo ""

BASHRC="$HOME/.bashrc"

# Check if already configured
if grep -q "alias report=" "$BASHRC" 2>/dev/null && grep -q ".machine_report.sh" "$BASHRC" 2>/dev/null; then
    echo "✓ .bashrc already configured for Machine Report"
else
    echo "Adding Machine Report configuration to $BASHRC..."
    cat >> "$BASHRC" << 'EOF'

# Machine Report alias - run anytime with 'report' command
alias report='~/.machine_report.sh'

# Run Machine Report only when in interactive mode
if [[ $- == *i* ]]; then
    ~/.machine_report.sh
fi
EOF
    echo "✓ .bashrc configured"
fi

echo ""

# Test installation
echo "=========================================="
echo "Testing Installation"
echo "=========================================="
echo ""

if [ -x "$TARGET_FILE" ]; then
    echo "Running machine report test..."
    echo ""
    "$TARGET_FILE"
    echo ""
    echo "✓ Test successful!"
else
    echo "❌ Error: Script is not executable"
    exit 1
fi

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Type 'report' to run the machine report anytime"
echo "  2. Open a new terminal to see it run automatically"
echo "  3. Customize by editing: nano ~/.machine_report.sh"
echo ""

# Platform-specific tips
if [ "$IS_RPI" -eq 1 ]; then
    echo "Raspberry Pi Specific Notes:"
    echo "  • CPU frequency now shows correctly (thanks to sysfs fallback)"
    echo "  • Script optimized for ARM64 architecture"
    echo "  • Perfect for monitoring your Pi over SSH!"
    echo ""
elif [ "$OS_TYPE" = "macos" ]; then
    echo "macOS Specific Notes:"
    echo "  • Script uses native macOS commands (sysctl, vm_stat, scutil)"
    echo "  • All system info displayed using macOS APIs"
    echo "  • Last login info may not be available (macOS limitation)"
    if [ "$BASH_MAJOR" -lt 4 ]; then
        echo "  • Running with Bash 3.2 - some formatting may differ"
        echo "  • Install Bash 4+ for best experience: brew install bash"
    fi
    echo ""
fi

echo "Documentation:"
echo "  • README.md - Full documentation"
echo "  • CLAUDE.md - Claude Code automation guide"
echo ""
echo "Installed to: $TARGET_FILE"
echo "Configured in: $BASHRC"
echo ""

# Customization suggestions
if [ "$IS_RPI" -eq 1 ]; then
    echo "Raspberry Pi Customization Tips:"
    echo "  • Edit line 20 to change header: report_title=\"YOUR RPI NAME\""
    echo "  • Consider showing temperature (requires vcgencmd)"
    echo "  • Check CLAUDE.md for customization guidance"
    echo ""
elif [ "$OS_TYPE" = "macos" ]; then
    echo "macOS Customization Tips:"
    echo "  • Edit line 20 to change header: report_title=\"YOUR MAC NAME\""
    echo "  • Script respects macOS's built-in commands"
    echo "  • Check CLAUDE.md for platform-specific customization"
    echo ""
fi

echo "To uninstall:"
echo "  rm ~/.machine_report.sh"
echo "  # Then manually remove lines from ~/.bashrc"
echo ""
