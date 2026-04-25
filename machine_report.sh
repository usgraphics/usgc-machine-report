#!/bin/bash
# TR-100 Machine Report
# Copyright © 2024, U.S. Graphics, LLC. BSD-3-Clause License.
# Fork enhancements © 2025, Emmett Shaughnessy (RealEmmettS)
#
# Cross-platform system information tool
# Supports: Linux (all major distros), macOS 10.13+, partial BSD support
# Requires: Bash 4.0+ (macOS users: brew install bash)

# Global variables
MIN_NAME_LEN=5
MAX_NAME_LEN=13

MIN_DATA_LEN=20
MAX_DATA_LEN=32

BORDERS_AND_PADDING=7

# Basic configuration, change as needed
report_title="UNITED STATES GRAPHICS COMPANY"
last_login_ip_present=0
zfs_present=0
zfs_filesystem="zroot/ROOT/os"

# ============================================================================
# CROSS-PLATFORM COMPATIBILITY FRAMEWORK
# ============================================================================

# Detect operating system type
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux"* ]] || [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "freebsd"* ]] || [[ "$OSTYPE" == "openbsd"* ]] || [[ "$OSTYPE" == "netbsd"* ]]; then
        echo "bsd"
    else
        echo "unknown"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check if file exists and is readable
file_readable() {
    [ -f "$1" ] && [ -r "$1" ]
}

# Validate that a value looks like an IPv4 address (basic check)
is_ipv4() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Set OS type
OS_TYPE=$(detect_os)

# Check Bash version (warn but don't exit)
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "⚠ Warning: Bash 4.0+ recommended for best compatibility" >&2
    echo "  Current version: ${BASH_VERSION}" >&2
    if [ "$OS_TYPE" = "macos" ]; then
        echo "  macOS users: Install with 'brew install bash'" >&2
    fi
    echo "" >&2
fi

# ============================================================================
# UTILITIES
# ============================================================================
max_length() {
    local max_len=0
    local len

    for str in "$@"; do
        len=${#str}
        if (( len > max_len )); then
            max_len=$len
        fi
    done

    if [ $max_len -lt $MAX_DATA_LEN ]; then
        printf '%s' "$max_len"
    else
        printf '%s' "$MAX_DATA_LEN"
    fi
}

# All data strings must go here
set_current_len() {
    CURRENT_LEN=$(max_length                                     \
        "$report_title"                                          \
        "$os_name"                                               \
        "$os_kernel"                                             \
        "$net_hostname"                                          \
        "$net_machine_ip"                                        \
        "$net_client_ip"                                         \
        "$net_current_user"                                      \
        "$cpu_model"                                             \
        "$cpu_cores_per_socket vCPU(s) / $cpu_sockets Socket(s)" \
        "$cpu_hypervisor"                                        \
        "$cpu_freq GHz"                                          \
        "$cpu_1min_bar_graph"                                    \
        "$cpu_5min_bar_graph"                                    \
        "$cpu_15min_bar_graph"                                   \
        "$zfs_used_gb/$zfs_available_gb GB [$disk_percent%]"     \
        "$disk_bar_graph"                                        \
        "$zfs_health"                                            \
        "$root_used_gb/$root_total_gb GB [$disk_percent%]"       \
        "${mem_used_gb}/${mem_total_gb} GiB [${mem_percent}%]"   \
        "${mem_bar_graph}"                                       \
        "$last_login_time"                                       \
        "$last_login_ip"                                         \
        "$last_login_ip"                                         \
        "$sys_uptime"                                            \
    )
}

PRINT_HEADER() {
    local length=$((CURRENT_LEN+MAX_NAME_LEN+BORDERS_AND_PADDING))

    local top="┌"
    local bottom="├"
    for (( i = 0; i < length - 2; i++ )); do
        top+="┬"
        bottom+="┴"
    done
    top+="┐"
    bottom+="┤"

    printf '%s\n' "$top"
    printf '%s\n' "$bottom"
}

PRINT_CENTERED_DATA() {
    local max_len=$((CURRENT_LEN+MAX_NAME_LEN-BORDERS_AND_PADDING))
    local text="$1"
    local total_width=$((max_len + 12))

    local text_len=${#text}
    local padding_left=$(( (total_width - text_len) / 2 ))
    local padding_right=$(( total_width - text_len - padding_left ))

    printf "│%${padding_left}s%s%${padding_right}s│\n" "" "$text" ""
}

PRINT_DIVIDER() {
    # either "top" or "bottom", no argument means middle divider
    local side="$1"
    case "$side" in
        "top")
            local left_symbol="├"
            local middle_symbol="┬"
            local right_symbol="┤"
            ;;
        "bottom")
            local left_symbol="└"
            local middle_symbol="┴"
            local right_symbol="┘"
            ;;
        *)
            local left_symbol="├"
            local middle_symbol="┼"
            local right_symbol="┤"
    esac

    local length=$((CURRENT_LEN+MAX_NAME_LEN+BORDERS_AND_PADDING))
    local divider="$left_symbol"
    for (( i = 0; i < length - 3; i++ )); do
        divider+="─"
        if [ "$i" -eq 14 ]; then
            divider+="$middle_symbol"
        fi
    done
    divider+="$right_symbol"
    printf '%s\n' "$divider"
}

PRINT_DATA() {
    local name="$1"
    local data="$2"
    local max_data_len=$CURRENT_LEN

    # Pad name
    local name_len=${#name}
    if (( name_len < MIN_NAME_LEN )); then
        name=$(printf "%-${MIN_NAME_LEN}s" "$name")
    elif (( name_len > MAX_NAME_LEN )); then
        name=$(echo "$name" | cut -c 1-$((MAX_NAME_LEN-3)))...
    else
        name=$(printf "%-${MAX_NAME_LEN}s" "$name")
    fi

    # Truncate or pad data
    local data_len=${#data}
    if (( data_len >= MAX_DATA_LEN || data_len == MAX_DATA_LEN-1 )); then
        data=$(echo "$data" | cut -c 1-$((MAX_DATA_LEN-3-2)))...
    else
        data=$(printf "%-${max_data_len}s" "$data")
    fi

    printf "│ %-${MAX_NAME_LEN}s │ %s │\n" "$name" "$data"
}

PRINT_FOOTER() {
    local length=$((CURRENT_LEN+MAX_NAME_LEN+BORDERS_AND_PADDING))
    local footer="└"
    for (( i = 0; i < length - 3; i++ )); do
        footer+="─"
        if [ "$i" -eq 14 ]; then
            footer+="┴"
        fi
    done
    footer+="┘"
    printf '%s\n' "$footer"
}

bar_graph() {
    local percent
    local num_blocks
    local width=$CURRENT_LEN
    local graph=""
    local used=$1
    local total=$2

    if (( total == 0 )); then
        percent=0
    else
        percent=$(awk -v used="$used" -v total="$total" 'BEGIN { printf "%.2f", (used / total) * 100 }')
    fi

    num_blocks=$(awk -v percent="$percent" -v width="$width" 'BEGIN { printf "%d", (percent / 100) * width }')

    for (( i = 0; i < num_blocks; i++ )); do
        graph+="█"
    done
    for (( i = num_blocks; i < width; i++ )); do
        graph+="░"
    done
    printf "%s" "${graph}"
}

get_ip_addr() {
    # Initialize variables
    ipv4_address=""
    ipv6_address=""

    # Check if ifconfig command exists
    if command -v ifconfig &> /dev/null; then
        # Try to get IPv4 address using ifconfig
        ipv4_address=$(ifconfig | awk '
            /^[a-z]/ {iface=$1}
            iface != "lo:" && iface !~ /^docker/ && /inet / && !found_ipv4 {found_ipv4=1; print $2}')

        # If IPv4 address not available, try IPv6 using ifconfig
        if [ -z "$ipv4_address" ]; then
            ipv6_address=$(ifconfig | awk '
                /^[a-z]/ {iface=$1}
                iface != "lo:" && iface !~ /^docker/ && /inet6 / && !found_ipv6 {found_ipv6=1; print $2}')
        fi
    elif command -v ip &> /dev/null; then
        # Try to get IPv4 address using ip addr
        ipv4_address=$(ip -o -4 addr show | awk '
            $2 != "lo" && $2 !~ /^docker/ {split($4, a, "/"); if (!found_ipv4++) print a[1]}')

        # If IPv4 address not available, try IPv6 using ip addr
        if [ -z "$ipv4_address" ]; then
            ipv6_address=$(ip -o -6 addr show | awk '
                $2 != "lo" && $2 !~ /^docker/ {split($4, a, "/"); if (!found_ipv6++) print a[1]}')
        fi
    fi

    # If neither IPv4 nor IPv6 address is available, assign "No IP found"
    if [ -z "$ipv4_address" ] && [ -z "$ipv6_address" ]; then
        ip_address="No IP found"
    else
        # Prioritize IPv4 if available, otherwise use IPv6
        ip_address="${ipv4_address:-$ipv6_address}"
    fi

    printf '%s' "$ip_address"
}

# ============================================================================
# OPERATING SYSTEM INFORMATION
# ============================================================================

if [ "$OS_TYPE" = "macos" ]; then
    # macOS detection using sw_vers
    if command_exists sw_vers; then
        os_name="macOS $(sw_vers -productVersion 2>/dev/null || echo 'Unknown')"
    else
        os_name="macOS (Unknown Version)"
    fi
elif file_readable /etc/os-release; then
    # Linux detection using os-release
    source /etc/os-release
    if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
        # Bash 4+: Use capitalize
        os_name="${ID^} ${VERSION} ${VERSION_CODENAME^}"
    else
        # Bash 3: Plain format
        os_name="${ID} ${VERSION} ${VERSION_CODENAME}"
    fi
else
    # Fallback for systems without os-release
    os_name="$(uname -s) (Unknown Version)"
fi

# Kernel information - portable format
os_kernel="$(uname -s) $(uname -r)"

# ============================================================================
# NETWORK INFORMATION
# ============================================================================

net_current_user=$(whoami)

# Hostname detection with fallbacks
if command_exists hostname; then
    # Try hostname -f first (FQDN), fallback to plain hostname
    if hostname -f &> /dev/null 2>&1; then
        net_hostname=$(hostname -f 2>/dev/null)
    else
        net_hostname=$(hostname 2>/dev/null)
    fi
elif file_readable /etc/hosts; then
    # Fallback: try to find hostname in /etc/hosts
    net_hostname=$(grep -w "$(uname -n)" /etc/hosts 2>/dev/null | awk '{print $2}' | head -n 1)
else
    # Last resort: use uname
    net_hostname=$(uname -n 2>/dev/null)
fi

# Ensure we have something
[ -z "$net_hostname" ] && net_hostname="Not Defined"

# Get machine IP address (uses get_ip_addr function defined earlier)
net_machine_ip=$(get_ip_addr)

# Get client IP (for SSH sessions)
net_client_ip=$(who am i 2>/dev/null | awk '{print $5}' | tr -d '()')
[ -z "$net_client_ip" ] && net_client_ip="Not connected"

# DNS servers detection
if [ "$OS_TYPE" = "macos" ] && command_exists scutil; then
    # macOS: use scutil to get DNS servers
    net_dns_ip=($(scutil --dns 2>/dev/null | grep 'nameserver\[[0-9]*\]' | awk '{print $3}' | head -5))
elif file_readable /etc/resolv.conf; then
    # Linux/Unix: parse resolv.conf
    net_dns_ip=($(grep '^nameserver [0-9.]' /etc/resolv.conf 2>/dev/null | awk '{print $2}'))
else
    # No DNS info available
    net_dns_ip=()
fi

# ============================================================================
# CPU INFORMATION
# ============================================================================

if [ "$OS_TYPE" = "macos" ]; then
    # macOS CPU detection using sysctl
    cpu_model="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Unknown CPU')"
    cpu_cores="$(sysctl -n hw.ncpu 2>/dev/null || echo '0')"
    cpu_cores_per_socket="$(sysctl -n machdep.cpu.core_count 2>/dev/null || echo '')"
    cpu_sockets="$(sysctl -n hw.packages 2>/dev/null || sysctl -n hw.physicalcpu 2>/dev/null || echo '-')"
    cpu_hypervisor="Bare Metal"  # macOS doesn't expose hypervisor easily

    # CPU frequency on macOS (may not always be available)
    cpu_freq_hz="$(sysctl -n hw.cpufrequency_max 2>/dev/null || sysctl -n hw.cpufrequency 2>/dev/null)"
    if [ -n "$cpu_freq_hz" ] && [ "$cpu_freq_hz" != "0" ]; then
        cpu_freq=$(awk -v freq="$cpu_freq_hz" 'BEGIN { printf "%.2f", freq / 1000000000 }')
    else
        cpu_freq=""  # Will show blank like on some ARM systems
    fi

elif command_exists lscpu; then
    # Linux with lscpu
    cpu_model="$(lscpu | grep -E 'Model name:|^Model:' | grep -v 'BIOS' | cut -f 2 -d ':' | awk '{$1=$1; print $1 " " $2 " " $3 " " $4}')"
    cpu_hypervisor="$(lscpu | grep 'Hypervisor vendor' | cut -f 2 -d ':' | awk '{$1=$1}1')"
    [ -z "$cpu_hypervisor" ] && cpu_hypervisor="Bare Metal"

    cpu_cores="$(lscpu | grep -E '^CPU\(s\):' | awk '{print $2}' | head -1)"
    cpu_cores_per_socket="$(lscpu | grep 'Core(s) per socket' | cut -f 2 -d ':' | awk '{$1=$1}1')"
    cpu_sockets="$(lscpu | grep 'Socket(s)' | cut -f 2 -d ':' | awk '{$1=$1}1')"

    # CPU frequency - try multiple sources
    if file_readable /proc/cpuinfo; then
        cpu_freq="$(grep 'cpu MHz' /proc/cpuinfo | cut -f 2 -d ':' | awk 'NR==1 { printf "%.2f", $1 / 1000 }')"
    fi
    # Fallback for ARM: try sysfs
    if [ -z "$cpu_freq" ] && [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
        cpu_freq_khz="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)"
        [ -n "$cpu_freq_khz" ] && cpu_freq=$(awk -v freq="$cpu_freq_khz" 'BEGIN { printf "%.2f", freq / 1000000 }')
    fi

else
    # Fallback: No lscpu available
    cpu_model="Unknown CPU"
    cpu_hypervisor="Unknown"

    # Try nproc or fallback to getconf
    if command_exists nproc; then
        cpu_cores="$(nproc --all 2>/dev/null || nproc 2>/dev/null)"
    elif command_exists getconf; then
        cpu_cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo '0')"
    else
        cpu_cores="0"
    fi

    cpu_cores_per_socket=""
    cpu_sockets="-"
    cpu_freq=""
fi

# Normalize cpu_cores if using nproc as fallback
if [ -z "$cpu_cores" ] || [ "$cpu_cores" = "0" ]; then
    if command_exists nproc; then
        cpu_cores="$(nproc --all 2>/dev/null || echo '0')"
    fi
fi

# Load averages - prefer /proc/loadavg on Linux, use uptime elsewhere
if file_readable /proc/loadavg; then
    read load_avg_1min load_avg_5min load_avg_15min rest < /proc/loadavg
elif [ "$OS_TYPE" = "macos" ] && command_exists sysctl; then
    # macOS: use sysctl
    load_avg="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}')"
    load_avg_1min="$(echo "$load_avg" | awk '{print $1}')"
    load_avg_5min="$(echo "$load_avg" | awk '{print $2}')"
    load_avg_15min="$(echo "$load_avg" | awk '{print $3}')"
else
    # Fallback: parse uptime (less reliable with different locales)
    load_avg_1min=$(uptime | awk -F'load average: ' '{print $2}' | cut -d ',' -f1 | tr -d ' ')
    load_avg_5min=$(uptime | awk -F'load average: ' '{print $2}' | cut -d ',' -f2 | tr -d ' ')
    load_avg_15min=$(uptime | awk -F'load average: ' '{print $2}' | cut -d ',' -f3 | tr -d ' ')
fi

# ============================================================================
# MEMORY INFORMATION
# ============================================================================

if [ "$OS_TYPE" = "macos" ]; then
    # macOS memory detection using sysctl and vm_stat
    mem_total_bytes="$(sysctl -n hw.memsize 2>/dev/null || echo '0')"
    mem_total=$((mem_total_bytes / 1024))  # Convert to KB to match Linux format

    if command_exists vm_stat; then
        # Parse vm_stat for memory usage
        vm_stat_output="$(vm_stat)"
        page_size=$(echo "$vm_stat_output" | grep 'page size' | awk '{print $8}' | tr -d '.')
        [ -z "$page_size" ] && page_size=4096  # Default page size

        pages_free=$(echo "$vm_stat_output" | grep 'Pages free' | awk '{print $3}' | tr -d '.')
        pages_inactive=$(echo "$vm_stat_output" | grep 'Pages inactive' | awk '{print $3}' | tr -d '.')
        pages_speculative=$(echo "$vm_stat_output" | grep 'Pages speculative' | awk '{print $3}' | tr -d '.')

        # Calculate available memory in KB
        mem_available=$((((pages_free + pages_inactive + pages_speculative) * page_size) / 1024))
    else
        # Rough estimate if vm_stat unavailable
        mem_available=$((mem_total / 4))
    fi

    mem_used=$((mem_total - mem_available))

elif file_readable /proc/meminfo; then
    # Linux memory detection
    mem_total=$(grep 'MemTotal' /proc/meminfo | awk '{print $2}')
    mem_available=$(grep 'MemAvailable' /proc/meminfo | awk '{print $2}')
    mem_used=$((mem_total - mem_available))

else
    # Fallback for unknown systems
    mem_total=0
    mem_available=0
    mem_used=0
fi

# Calculate percentages and convert to GB
if [ "$mem_total" -gt 0 ]; then
    mem_percent=$(awk -v used="$mem_used" -v total="$mem_total" 'BEGIN { printf "%.2f", (used / total) * 100 }')
    mem_total_gb=$(echo "$mem_total" | awk '{ printf "%.2f", $1 / (1024 * 1024) }')
    mem_available_gb=$(echo "$mem_available" | awk '{ printf "%.2f", $1 / (1024 * 1024) }')
    mem_used_gb=$(echo "$mem_used" | awk '{ printf "%.2f", $1 / (1024 * 1024) }')
else
    mem_percent="0.00"
    mem_total_gb="0.00"
    mem_available_gb="0.00"
    mem_used_gb="0.00"
fi

# ============================================================================
# DISK INFORMATION
# ============================================================================

# Check for ZFS (Linux only)
if [ "$OS_TYPE" = "linux" ] && command_exists zfs && grep -q "zfs" /proc/mounts 2>/dev/null; then
    zfs_present=1

    # ZFS health check - handle different ZFS versions
    zfs_health_output="$(zpool status -x zroot 2>/dev/null | head -1)"
    if [[ "$zfs_health_output" == "all pools are healthy" ]] || [[ "$zfs_health_output" == *"is healthy"* ]]; then
        zfs_health="HEALTH O.K."
    elif [ -z "$zfs_health_output" ]; then
        zfs_health="Unknown"
    else
        zfs_health="CHECK REQUIRED"
    fi

    # Get ZFS usage
    zfs_available=$(zfs get -o value -Hp available "$zfs_filesystem" 2>/dev/null || echo "0")
    zfs_used=$(zfs get -o value -Hp used "$zfs_filesystem" 2>/dev/null || echo "0")
    zfs_available_gb=$(echo "$zfs_available" | awk '{ printf "%.2f", $1 / (1024 * 1024 * 1024) }')
    zfs_used_gb=$(echo "$zfs_used" | awk '{ printf "%.2f", $1 / (1024 * 1024 * 1024) }')

    # FIX: Correct percentage calculation - used / (used + available)
    disk_percent=$(awk -v used="$zfs_used" -v available="$zfs_available" \
        'BEGIN { total = used + available; if (total > 0) printf "%.2f", (used / total) * 100; else print "0.00" }')
else
    # Standard filesystem detection (Linux, macOS, BSD)
    root_partition="/"

    # Try df -m first (MB), fallback to df -k (KB) if unsupported
    if df -m "$root_partition" &> /dev/null 2>&1; then
        root_used=$(df -m "$root_partition" 2>/dev/null | awk 'NR==2 {print $3}')
        root_total=$(df -m "$root_partition" 2>/dev/null | awk 'NR==2 {print $2}')
        root_total_gb=$(awk -v total="$root_total" 'BEGIN { printf "%.2f", total / 1024 }')
        root_used_gb=$(awk -v used="$root_used" 'BEGIN { printf "%.2f", used / 1024 }')
    else
        # Fallback to KB and convert
        root_used=$(df -k "$root_partition" 2>/dev/null | awk 'NR==2 {print $3}')
        root_total=$(df -k "$root_partition" 2>/dev/null | awk 'NR==2 {print $2}')
        root_total_gb=$(awk -v total="$root_total" 'BEGIN { printf "%.2f", total / 1024 / 1024 }')
        root_used_gb=$(awk -v used="$root_used" 'BEGIN { printf "%.2f", used / 1024 / 1024 }')
    fi

    # Calculate percentage with safety check
    if [ -n "$root_total" ] && [ "$root_total" -gt 0 ]; then
        disk_percent=$(awk -v used="$root_used" -v total="$root_total" \
            'BEGIN { printf "%.2f", (used / total) * 100 }')
    else
        disk_percent="0.00"
        root_total_gb="0.00"
        root_used_gb="0.00"
    fi
fi

# Last login and Uptime
# Try lastlog2 first (modern Debian), fall back to lastlog if available
if command -v lastlog2 &> /dev/null; then
    last_login=$(lastlog2 -u "$USER" 2>/dev/null)
    last_login_ip=$(echo "$last_login" | awk 'NR==2 {print $3}')

    # Check if last_login_ip is an IP address
    if [[ "$last_login_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        last_login_ip_present=1
        last_login_time=$(echo "$last_login" | awk 'NR==2 {print $4, $5, $6, $7, $8}' | sed 's/  */ /g')
    else
        last_login_time=$(echo "$last_login" | awk 'NR==2 {print $4, $5, $6, $7, $8}' | sed 's/  */ /g')
        # Check for never logged in edge case
        if [ -z "$last_login_time" ] || [ "$last_login_time" = "in**" ]; then
            last_login_time="Never logged in"
        fi
    fi
elif command -v lastlog &> /dev/null; then
    last_login=$(lastlog -u "$USER" 2>/dev/null)
    last_login_ip=$(echo "$last_login" | awk 'NR==2 {print $3}')

    # Check if last_login_ip is an IP address
    if [[ "$last_login_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        last_login_ip_present=1
        last_login_time=$(echo "$last_login" | awk 'NR==2 {print $6, $7, $10, $8}')
    else
        last_login_time=$(echo "$last_login" | awk 'NR==2 {print $4, $5, $8, $6}')
        # Check for **Never logged in** edge case
        if [ "$last_login_time" = "in**" ]; then
            last_login_time="Never logged in"
        fi
    fi
else
    # Neither command available
    last_login_time="Login tracking unavailable"
    last_login_ip=""
    last_login_ip_present=0
fi

# System uptime - use uptime -p if available, otherwise calculate from boot time
if uptime -p &> /dev/null 2>&1; then
    # Linux with uptime -p
    sys_uptime=$(uptime -p 2>/dev/null | sed 's/up\s*//; s/\s*day\(s*\)/d/; s/\s*hour\(s*\)/h/; s/\s*minute\(s*\)/m/')
elif [ "$OS_TYPE" = "macos" ] && command_exists sysctl; then
    # macOS: calculate from boot time
    boot_time=$(sysctl -n kern.boottime 2>/dev/null | awk '{print $4}' | tr -d ',')
    if [ -n "$boot_time" ]; then
        current_time=$(date +%s)
        uptime_seconds=$((current_time - boot_time))
        uptime_days=$((uptime_seconds / 86400))
        uptime_hours=$(( (uptime_seconds % 86400) / 3600 ))
        uptime_mins=$(( (uptime_seconds % 3600) / 60 ))

        # Format similar to Linux uptime -p
        sys_uptime=""
        [ "$uptime_days" -gt 0 ] && sys_uptime="${uptime_days}d "
        [ "$uptime_hours" -gt 0 ] && sys_uptime="${sys_uptime}${uptime_hours}h "
        [ "$uptime_mins" -gt 0 ] && sys_uptime="${sys_uptime}${uptime_mins}m"
        sys_uptime=$(echo "$sys_uptime" | sed 's/  */ /g; s/ $//')  # Clean up spacing
    else
        sys_uptime="Unknown"
    fi
else
    # Fallback: parse uptime command output (less reliable)
    sys_uptime=$(uptime 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="up") {for(j=i+1;j<=NF;j++) {if($j ~ /user/) break; printf "%s ", $j}}}' | sed 's/,//g')
    [ -z "$sys_uptime" ] && sys_uptime="Unknown"
fi

# Set current length before graphs get calculated
set_current_len

# Create graphs
cpu_1min_bar_graph=$(bar_graph "$load_avg_1min" "$cpu_cores")
cpu_5min_bar_graph=$(bar_graph "$load_avg_5min" "$cpu_cores")
cpu_15min_bar_graph=$(bar_graph "$load_avg_15min" "$cpu_cores")

mem_bar_graph=$(bar_graph "$mem_used" "$mem_total")

if [ $zfs_present -eq 1 ]; then
    disk_bar_graph=$(bar_graph "$zfs_used" "$zfs_available")
else
    disk_bar_graph=$(bar_graph "$root_used" "$root_total")
fi

# Machine Report
PRINT_HEADER
PRINT_CENTERED_DATA "$report_title"
PRINT_CENTERED_DATA "TR-100 MACHINE REPORT"
PRINT_DIVIDER "top"
PRINT_DATA "OS" "$os_name"
PRINT_DATA "KERNEL" "$os_kernel"
PRINT_DIVIDER
PRINT_DATA "HOSTNAME" "$net_hostname"
PRINT_DATA "MACHINE IP" "$net_machine_ip"
PRINT_DATA "CLIENT  IP" "$net_client_ip"

for dns_num in "${!net_dns_ip[@]}"; do
    PRINT_DATA "DNS  IP $(($dns_num + 1))" "${net_dns_ip[dns_num]}"
done

PRINT_DATA "USER" "$net_current_user"
PRINT_DIVIDER
PRINT_DATA "PROCESSOR" "$cpu_model"
PRINT_DATA "CORES" "$cpu_cores_per_socket vCPU(s) / $cpu_sockets Socket(s)"
PRINT_DATA "HYPERVISOR" "$cpu_hypervisor"
PRINT_DATA "CPU FREQ" "$cpu_freq GHz"
PRINT_DATA "LOAD  1m" "$cpu_1min_bar_graph"
PRINT_DATA "LOAD  5m" "$cpu_5min_bar_graph"
PRINT_DATA "LOAD 15m" "$cpu_15min_bar_graph"

if [ $zfs_present -eq 1 ]; then
    PRINT_DIVIDER
    PRINT_DATA "VOLUME" "$zfs_used_gb/$zfs_available_gb GB [$disk_percent%]"
    PRINT_DATA "DISK USAGE" "$disk_bar_graph"
    PRINT_DATA "ZFS HEALTH" "$zfs_health"
else
    PRINT_DIVIDER
    PRINT_DATA "VOLUME" "$root_used_gb/$root_total_gb GB [$disk_percent%]"
    PRINT_DATA "DISK USAGE" "$disk_bar_graph"
fi

PRINT_DIVIDER
PRINT_DATA "MEMORY" "${mem_used_gb}/${mem_total_gb} GiB [${mem_percent}%]"
PRINT_DATA "USAGE" "${mem_bar_graph}"
PRINT_DIVIDER
PRINT_DATA "LAST LOGIN" "$last_login_time"

if [ $last_login_ip_present -eq 1 ]; then
    PRINT_DATA "" "$last_login_ip"
fi

PRINT_DATA "UPTIME" "$sys_uptime"
PRINT_DIVIDER "bottom"
