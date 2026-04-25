# Comprehensive Bash to PowerShell Conversion Guide for TR-100 Machine Report

Windows Terminal displays Unicode box-drawing characters flawlessly when PowerShell uses UTF-8 encoding—a critical requirement for converting the TR-100 bash script to PowerShell. **The good news: PowerShell 7+ defaults to UTF-8, while PowerShell 5.1 requires explicit configuration.** This guide provides everything needed to convert your bash system information script to PowerShell with feature parity and Windows-specific enhancements.

## Command mapping unlocks direct translation paths

Converting bash commands to PowerShell requires understanding object-oriented versus text-based paradigms. Where bash pipes text through grep and awk, PowerShell pipes rich objects through Where-Object and Select-Object—eliminating fragile text parsing.

**CPU Information (lscpu equivalent):**
PowerShell uses `Get-CimInstance Win32_Processor` as the primary method for CPU details. This returns structured objects with properties like Name, NumberOfCores, NumberOfLogicalProcessors, and MaxClockSpeed. Unlike parsing /proc/cpuinfo line-by-line, you directly access properties: `(Get-CimInstance Win32_Processor).NumberOfCores`. The Win32_Processor class provides hypervisor detection through the HypervisorPresent property on Win32_ComputerSystem—crucial for virtual machine identification. For cross-platform scripts, PowerShell 7+ allows calling native commands like `lscpu` on Linux while using CIM classes on Windows.

**Disk Space (df equivalent):**
Three methods exist with different use cases. `Get-Volume` (PowerShell 3.0+) closely mirrors `df -h` behavior, returning drive letters with size and free space. `Get-PSDrive -PSProvider FileSystem` works across all PowerShell providers. `Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"` provides the most control, where DriveType=3 specifies fixed hard disks. For the TR-100 report, Get-Volume offers the simplest implementation with calculated properties for percentage used.

**System Uptime (uptime equivalent):**
PowerShell 7+ includes `Get-Uptime` cmdlet directly. PowerShell 5.1 requires calculating uptime: `(Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime`. This returns a TimeSpan object with Days, Hours, and Minutes properties—more structured than parsing uptime's text output. The LastBootUpTime property provides precise boot time for display.

**Last Login Information (lastlog equivalent):**
Windows stores login events in the Security event log. Query Event ID 4624 (successful logon) using `Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4624}`. This requires elevated permissions. Extract username from Properties[5].Value. For domain environments, query Active Directory's LastLogonDate property, though LastLogon requires querying all domain controllers as it's not replicated. The TR-100 conversion should show the currently logged-on user from `(Get-CimInstance Win32_ComputerSystem).UserName` for simplicity.

**Network Configuration (ifconfig/ip equivalent):**
PowerShell 5.1+ provides granular network cmdlets. `Get-NetIPConfiguration` mirrors `ipconfig /all` output. `Get-NetAdapter` lists physical and virtual adapters. `Get-NetIPAddress -AddressFamily IPv4` returns all IPv4 addresses. For the script, combine these: use Get-NetIPConfiguration for comprehensive details including IP address, gateway, and DNS servers. Extract specific values with property access rather than regex parsing.

**Memory Information (/proc/meminfo equivalent):**
Win32_OperatingSystem provides TotalVisibleMemorySize and FreePhysicalMemory in kilobytes. Calculate usage percentage: `$used = $total - $free; $percent = ($used / $total) * 100`. For detailed physical memory modules, query Win32_PhysicalMemory which returns objects for each RAM stick with Capacity, Speed, and Manufacturer. Get-ComputerInfo (PowerShell 5.1+) aggregates memory information in a single call.

**Load Average Equivalent:**
Windows lacks direct load average equivalents since the metric differs conceptually. Linux load average includes processes waiting plus running; Windows Processor Queue Length shows only waiting processes. Query `Get-Counter '\System\Processor Queue Length'` for instantaneous values. For TR-100's 1/5/15-minute averages, sample over time intervals: collect 180 samples at 5-second intervals for 15-minute average. Compare against threshold of 2× CPU core count. Alternatively, show CPU percentage with `Get-Counter '\Processor(_Total)\% Processor Time'`.

**Text Processing (grep/awk/sed):**
PowerShell's object pipeline eliminates most text processing needs. `Select-String` replaces grep with advantages: returns MatchInfo objects containing line numbers, filenames, and matched text. The `-Pattern` parameter accepts regex. For filtering objects, use `Where-Object {$_.Property -match 'pattern'}`. String replacement uses the `-replace` operator: `$text -replace 'old', 'new'`. Field extraction that required awk becomes property access: instead of `awk '{print $1}'`, use `$line.Split()[0]` or better yet, access object properties directly.

**ZFS and BSD-Specific Commands:**
Windows doesn't support ZFS natively. PowerShell can call zfs commands on systems with OpenZFS on Windows, or manage ZFS systems remotely via SSH using `New-SSHSession`. For Windows equivalents, Storage Spaces provides similar functionality: `Get-StoragePool`, `Get-VirtualDisk`, and related cmdlets manage software-defined storage. The TR-100 conversion should detect ZFS availability and gracefully handle its absence on Windows.

## PowerShell best practices ensure maintainable, professional scripts

Modern PowerShell development in 2024-2025 emphasizes consistency, readability, and cross-platform compatibility. Scripts should work identically whether running on PowerShell 5.1 or 7+, Windows or Linux.

**Script Structure and Organization:**
Every script begins with comment-based help using `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, and `.NOTES` keywords. This enables `Get-Help` functionality. The `#Requires` statement enforces version and module requirements: `#Requires -Version 5.1` ensures compatibility. Advanced functions use `[CmdletBinding()]` attribute for common parameters like -Verbose and -ErrorAction. Organize code in begin/process/end blocks: begin for initialization, process for pipeline processing, end for cleanup.

**Naming Conventions:**
Use PascalCase universally—variables, functions, parameters. Functions follow Verb-Noun pattern with approved verbs from `Get-Verb`. For TR-100, functions might be `Get-SystemReport`, `Show-SystemMetrics`, `Format-ResourceUsage`. Two-letter acronyms capitalize both letters (VMList), three+ letter acronyms capitalize only the first (HtmlContent). Boolean variables phrase as questions: `$IsVirtual`, `$HasNetworkAccess`. Collections use plural nouns: `$Processes`, while single items use singular: `$Process`.

**Function Definitions:**
Advanced functions include comprehensive parameter validation. Use `[Parameter(Mandatory)]` for required parameters, `[ValidateSet()]` for allowed values, `[ValidateRange()]` for numeric bounds. The `ValueFromPipeline` enables pipeline input. Position parameters with `Position = 0` for natural syntax. Example for TR-100:

```powershell
function Get-SystemReport {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Summary', 'Detailed', 'Minimal')]
        [string]$ReportType = 'Summary',
        
        [switch]$IncludeNetwork,
        
        [switch]$ShowGraphs
    )
}
```

**Error Handling Patterns:**
Use try-catch-finally blocks around operations that might fail. Force non-terminating errors to terminating with `-ErrorAction Stop` to trigger catch blocks. Catch specific exception types before general exceptions. Log errors meaningfully—include operation attempted, target resource, and error details. For the TR-100 script, wrap network operations and WMI queries in try-catch since these commonly fail on restricted systems. Never use empty catch blocks—always log or handle errors appropriately.

**Cross-Platform Compatibility:**
PowerShell 7+ provides `$IsWindows`, `$IsLinux`, `$IsMacOS` automatic variables for platform detection. PowerShell 5.1 doesn't have these—detect with `$PSVersionTable.PSEdition -eq 'Desktop'` indicating Windows PowerShell 5.1. Use `Join-Path` or `[System.IO.Path]::Combine()` instead of hardcoded path separators. The [Environment] .NET class works cross-platform: `[Environment]::MachineName`, `[Environment]::UserName`. For the TR-100 conversion, implement platform detection early and branch logic accordingly.

**Code Formatting:**
Indent with 4 spaces, never tabs. Opening braces on same line as statement. Pipeline operators on new lines when splitting, indented one level. Use splatting for long parameter lists—creates hashtable of parameters passed with `@` symbol. Format output objects with PSCustomObject for consistent display. Avoid Write-Host except for colored console output; prefer Write-Output or return objects directly.

## Windows system information gathering provides rich metrics

Windows exposes extensive system information through WMI/CIM, performance counters, and specialized cmdlets. Understanding which method serves each use case optimizes both performance and code clarity.

**CIM vs WMI Cmdlets:**
Always prefer CIM cmdlets over deprecated WMI cmdlets. `Get-CimInstance` (not Get-WmiObject) uses WS-MAN protocol, which is firewall-friendly and supports parallel queries. CIM automatically converts WMI datetime strings to PowerShell DateTime objects—eliminating manual conversion. Create reusable CIM sessions with `New-CimSession` when querying multiple classes: sessions reduce overhead. For the TR-100 script on PowerShell 5.1+, use CIM exclusively. Legacy WMI cmdlets will be removed in future PowerShell versions.

**Essential Win32 Classes:**
Win32_Processor provides CPU details including cores, logical processors, clock speed, and current load percentage. Win32_OperatingSystem returns OS version, architecture, install date, last boot time, and memory totals. Win32_ComputerSystem includes machine name, manufacturer, model, domain membership, and critically—HypervisorPresent property for VM detection. Win32_LogicalDisk filtered by DriveType=3 (fixed disks) provides storage metrics. Win32_NetworkAdapterConfiguration filtered by IPEnabled=True shows active network configurations. Query these with calculated properties to format sizes in GB and percentages.

**Get-ComputerInfo Capabilities:**
PowerShell 5.1+ includes Get-ComputerInfo aggregating 182+ properties from multiple sources in one call. Returns Cs* properties (computer system), Os* properties (operating system), Bios* properties, and Windows* properties. Excellent for overview reports but slower than targeted CIM queries. For TR-100, use Get-ComputerInfo for initial overview, then targeted CIM queries for real-time metrics like CPU load and memory usage. Filter properties with `-Property` parameter: `Get-ComputerInfo -Property "Os*", "Cs*"` for OS and computer system info only.

**Performance Counters:**
`Get-Counter` accesses Windows performance counters for real-time metrics. Processor counter: `'\Processor(_Total)\% Processor Time'` shows CPU percentage. Memory counter: `'\Memory\Available MBytes'` shows free memory. Disk counters provide IOPS, latency, queue length. Network counters show bytes/packets per second. Sample multiple times for averages using `-SampleInterval` and `-MaxSamples` parameters. For the TR-100 script's CPU load equivalent to bash's load average, sample Processor Queue Length over intervals: 60 samples at 1-second intervals for 1-minute average, 300 samples for 5-minute average.

**Hypervisor Detection:**
Modern Windows (8+) exposes virtualization through Win32_ComputerSystem's HypervisorPresent property—simple boolean indicating VM status. For deeper detection, check Model and Manufacturer properties: "Virtual Machine" indicates Hyper-V, "VMware" indicates VMware, "VirtualBox" indicates Oracle VirtualBox. Xen-based systems (AWS EC2) show manufacturer "Xen" or UUID starting with "EC2". Azure VMs run WindowsAzureGuestAgent service. Implement comprehensive detection checking multiple indicators:

```powershell
$computerSystem = Get-CimInstance Win32_ComputerSystem
$isVirtual = $computerSystem.HypervisorPresent
$platform = switch -Regex ($computerSystem.Model) {
    'Virtual Machine' { 'Hyper-V' }
    'VMware' { 'VMware' }
    'VirtualBox' { 'VirtualBox' }
    default { if ($isVirtual) { 'Unknown VM' } else { 'Physical' } }
}
```

**Registry Access:**
PowerShell exposes registry as drives: HKLM: and HKCU:. Navigate with `Set-Location HKLM:\SOFTWARE` and query with `Get-ItemProperty`. Registry contains system info like Windows version in `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion`, installed programs in `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*`. For the TR-100 script, registry access supplements WMI data but shouldn't be primary source—CIM classes provide structured, documented interfaces.

**Complete System Metrics:**
A comprehensive TR-100 equivalent queries: OS name/version from Win32_OperatingSystem Caption and Version; hostname from [Environment]::MachineName; CPU model/cores from Win32_Processor Name and NumberOfCores; total/used/free memory calculated from Win32_OperatingSystem TotalVisibleMemorySize and FreePhysicalMemory; disk usage from Win32_LogicalDisk with calculated percentage; uptime from LastBootUpTime; current user from Win32_ComputerSystem UserName; network configuration from Get-NetIPConfiguration; processor load from performance counters; hypervisor status from Win32_ComputerSystem.

## Box-drawing characters require proper encoding configuration

The TR-100 bash script's distinctive visual output depends on Unicode box-drawing characters (┌─┐│├┤└┘). PowerShell fully supports these characters when console encoding is correctly configured—the limitation lies in terminal capabilities, not PowerShell itself.

**Console Encoding Setup:**
PowerShell 7+ defaults to UTF-8 for all operations—no configuration needed. PowerShell 5.1 defaults to system OEM code page (437 on US English Windows) requiring explicit UTF-8 configuration. Set three encoding values: `[Console]::OutputEncoding`, `[Console]::InputEncoding`, and `$OutputEncoding`. All should be `[System.Text.Encoding]::UTF8`. Add this configuration to PowerShell profile for persistence. The profile ($PROFILE) runs on every PowerShell startup, making encoding changes permanent.

**Windows Terminal vs Legacy Console:**
Windows Terminal (default in Windows 11 22H2+) provides excellent Unicode support with GPU-accelerated rendering, Cascadia Code font including comprehensive Unicode glyphs, and UTF-8 by default. Legacy conhost.exe console requires manual activation with `chcp 65001` for UTF-8, limited font selection (Consolas, Lucida Console), and registry changes to enable ANSI escape sequences. For TR-100 deployment, recommend Windows Terminal but ensure graceful fallback for legacy consoles. Test character rendering and provide ASCII-based alternative if Unicode fails.

**PowerShell Version Differences:**
PowerShell 7+ supports Unicode escape sequences with \`u{XXXX} syntax: `Write-Host "\`u{2514}\`u{2500}\`u{2518}"` outputs └─┘. PowerShell 5.1 lacks this syntax—use [char] casting: `[char]0x2514 + [char]0x2500 + [char]0x2518`. For maximum compatibility, define box-drawing characters as variables or use [char] casting throughout. PowerShell 7's default UTF-8 NoBOM for file operations versus 5.1's UTF-16LE affects script portability—save TR-100 script as UTF-8 with BOM for 5.1 compatibility.

**Cross-Platform Encoding:**
Linux and macOS use UTF-8 as standard system encoding—no configuration needed. Windows requires explicit UTF-8 setup. For cross-platform TR-100 script, detect platform and configure encoding only on Windows PowerShell 5.1. Windows 10 1903+ offers beta "Use Unicode UTF-8 for worldwide language support" setting enabling system-wide UTF-8, but this breaks legacy applications—not recommended for general deployment.

**Font Requirements:**
Box-drawing character display requires fonts including Unicode U+2500-U+257F range. Recommended fonts: Cascadia Code/Mono (default Windows Terminal, excellent coverage), Consolas (widely available, basic Unicode), DejaVu Sans Mono (excellent cross-platform option). Verify font support by displaying test characters. For TR-100, include test function displaying various box-drawing characters with instructions for font installation if rendering fails.

**Alternative Approaches:**
When Unicode support isn't available or reliable, implement ASCII fallbacks using +, -, |, and = characters. Create detection function testing Unicode character display and switching between Unicode and ASCII rendering modes. ANSI escape sequences (supported in Windows Terminal and PowerShell 7+) enable colored output without special characters—use for highlighting headers or critical metrics. The $PSStyle automatic variable in PowerShell 7.2+ provides structured styling: `$PSStyle.Bold`, `$PSStyle.Foreground.Red`. For comprehensive compatibility, implement three rendering modes: Unicode (best), ANSI colors with ASCII (good), plain ASCII (fallback).

**Progress Bars and Visual Indicators:**
Replicate bash script's progress bars using Unicode block elements: █ (full block, \u2588), ░ (light shade, \u2591). Create bar graph function accepting percentage and bar length, calculating filled blocks proportionally. Write-Progress cmdlet provides native PowerShell progress bars but interrupts output flow—better for long-running operations than compact reports. For TR-100 memory/disk usage bars, implement custom function displaying percentage with visual bar: `[████████░░░░░░░] 55%`.

## PowerShell profiles enable seamless auto-run configuration

The TR-100 script should load automatically when PowerShell starts, making its functions immediately available. PowerShell profiles provide this functionality across different versions and platforms.

**Profile Types and Locations:**
PowerShell supports four profile scopes: AllUsersAllHosts (all users, all hosts), AllUsersCurrentHost (all users, current host), CurrentUserAllHosts (current user, all hosts), CurrentUserCurrentHost (current user, current host—default $PROFILE). Each has distinct file location. Windows PowerShell 5.1 stores profiles in `$HOME\Documents\WindowsPowerShell\`. PowerShell 7+ uses `$HOME\Documents\PowerShell\` on Windows, `~/.config/powershell/` on Linux/macOS. Access locations through $PROFILE properties: `$PROFILE.CurrentUserCurrentHost`, `$PROFILE.AllUsersAllHosts`, etc.

**Creating Profile Files:**
Check existence with `Test-Path $PROFILE`. Create if missing: `New-Item -ItemType File -Path $PROFILE -Force`. AllUsers profiles require administrator privileges. Edit with any text editor: `code $PROFILE` (VS Code), `notepad $PROFILE` (Notepad), `ise $PROFILE` (PowerShell ISE). Profile is standard PowerShell script executing on startup—functions, variables, and aliases defined in profile become globally available.

**Loading TR-100 Script:**
Dot-source the script from profile: `. "C:\Scripts\TR-100-Report.ps1"`. The dot-space prefix executes script in current scope, making functions available. Direct execution with `& "C:\Scripts\TR-100-Report.ps1"` runs in isolated scope—functions disappear after execution. Implement error handling: test path existence before dot-sourcing, wrap in try-catch block, provide user feedback on success/failure. For network-stored scripts, verify network availability before attempting load.

**Execution Policy:**
Windows requires execution policy permitting script execution. Check with `Get-ExecutionPolicy`. Set to RemoteSigned for security/usability balance: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`. CurrentUser scope doesn't require administrator privileges. Linux and macOS don't implement execution policies—scripts run without restriction. For enterprise deployment, coordinate with Group Policy settings—MachinePolicy and UserPolicy scopes override local settings.

**Performance Considerations:**
Profile scripts execute on every PowerShell startup—keep fast. Target sub-500ms load time. Measure with `Measure-Command { . $PROFILE }`. Defer heavy operations using lazy loading—create wrapper functions that import modules or load data only on first use. Avoid network operations in profile—these add unpredictable latency. For TR-100, dot-source the script to load functions but don't execute report automatically. Add startup message indicating TR-100 is ready: `Write-Host "TR-100 Report loaded. Type 'Get-SystemReport' to run." -ForegroundColor Green`.

**Cross-Version Compatibility:**
Maintain separate profiles for Windows PowerShell 5.1 and PowerShell 7+ or create shared profile script sourced from both. Detect version with `$PSVersionTable.PSVersion.Major` and branch logic accordingly. For TR-100, use version-agnostic code where possible—avoid features exclusive to 7+ if targeting both versions. Test profile on both versions before deployment.

**Best Practices:**
Use CurrentUserCurrentHost profile for personal customizations. Document profile contents with comments. Organize sections with #region/#endregion markers. Implement reload function for testing: `function Reload-Profile { . $PROFILE }`. Back up profile regularly—losing customizations is frustrating. Version control profiles in git for change tracking. For organizational deployment, store master profile on network share and configure local profiles to source it—enables centralized updates.

## Cross-platform PowerShell enables unified system management

PowerShell 7+ runs identically on Windows, Linux, and macOS—enabling true cross-platform scripting. The TR-100 conversion can support all platforms with conditional logic for platform-specific operations.

**Platform Detection:**
PowerShell 6+ provides `$IsWindows`, `$IsLinux`, `$IsMacOS` automatic boolean variables. Check platform: `if ($IsWindows) { ... } elseif ($IsLinux) { ... }`. PowerShell 5.1 doesn't have these variables—it's Windows-only, so assume Windows. For cross-version compatibility, detect edition: `$PSVersionTable.PSEdition -eq 'Desktop'` indicates Windows PowerShell 5.1, 'Core' indicates PowerShell 6+. Create wrapper at script start: `$IsWindowsEnv = if ($PSVersionTable.PSEdition -eq 'Desktop') { $true } else { $IsWindows }`.

**Cmdlet Availability:**
WMI/CIM cmdlets (Get-CimInstance, Get-WmiObject) are Windows-only—don't exist on Linux/macOS. Network cmdlets (Get-NetAdapter, Get-NetIPAddress) are Windows-only. Storage cmdlets (Get-Volume, Get-Disk) are Windows-only. Check availability: `if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) { ... }`. On non-Windows platforms, call native commands: `lscpu`, `df`, `uptime`, `ip addr`. Parse output with -split, -match, and regex. For the TR-100 script, implement parallel logic branches—CIM classes on Windows, /proc filesystem on Linux, sysctl on macOS.

**Path Handling:**
Windows uses backslash separators, Linux/macOS use forward slash. File systems differ: case-insensitive on Windows (usually), case-sensitive on Linux/macOS. Use `Join-Path` or `[System.IO.Path]::Combine()` for platform-agnostic paths. PowerShell 7+ accepts forward slashes on all platforms. Environment variables differ: $env:USERPROFILE on Windows vs $env:HOME on Linux/macOS—use $HOME which exists on all platforms. For TR-100, use `$HOME` for user directories and Join-Path for all path construction.

**Line Endings:**
Windows uses CRLF (\r\n), Linux/macOS use LF (\n). PowerShell handles both transparently when reading. Save scripts with LF endings for cross-platform compatibility. Git can auto-convert with `core.autocrlf=input`. VS Code can configure with `"files.eol": "\n"`. PowerShell 7+ defaults to UTF-8 NoBOM with LF endings.

**System Information Access Patterns:**
Windows: WMI/CIM classes provide structured data. Linux: /proc filesystem and system commands provide text output requiring parsing. macOS: sysctl, vm_stat, system_profiler commands with text output. For TR-100, abstract platform differences behind functions—Get-CPUInfo, Get-MemoryInfo, Get-DiskInfo—with platform-specific implementations selected based on $IsWindows/$IsLinux/$IsMacOS.

**Testing Without All Platforms:**
Use Docker containers for Linux testing: `docker run -it mcr.microsoft.com/powershell`. Use GitHub Actions or Azure Pipelines for automated cross-platform testing. Virtual machines provide full platform testing environments. Focus testing on platform-specific code—path handling, command execution, character encoding. Shared logic (calculations, formatting) typically works universally.

## Implementation strategy ensures successful conversion

Converting the TR-100 bash script to PowerShell requires systematic approach: start with structure, add Windows functionality, implement formatting, test extensively, then add cross-platform support.

**Phase 1: Core Structure:**
Create main function `Get-TR100Report` following advanced function pattern. Define parameters: `-ShowGraphs` switch for progress bars, `-Format` parameter for output format (Unicode/ASCII/HTML), `-IncludeNetwork` switch for network details. Implement basic system information gathering using Win32 classes: OS name, hostname, CPU model, memory totals, disk space, uptime. Return structured PSCustomObject—don't format output yet. This phase establishes working foundation.

**Phase 2: Windows Enhancements:**
Add Windows-specific metrics missing from bash version: hypervisor detection showing VM platform, installed Windows features, Windows Update status, Windows Defender status, detailed network adapter properties. Use Get-ComputerInfo for aggregated system overview. Query performance counters for real-time CPU percentage. Access event logs for last login events. Calculate processor queue length averages for load equivalent. These enhancements showcase PowerShell's Windows capabilities.

**Phase 3: Formatting and Display:**
Implement box-drawing character rendering with encoding configuration. Create Format-TR100Output function accepting data object and returning formatted string. Build table structure with headers, borders, and content rows. Implement progress bar rendering for memory/disk/CPU usage—calculate filled blocks based on percentage. Use calculated column widths based on content length plus padding. Add color highlighting with Write-Host -ForegroundColor for critical thresholds—red for >90% usage, yellow for >75%, green for normal.

**Phase 4: Encoding and Compatibility:**
Add encoding configuration at script start—detect PowerShell version and set UTF-8 for 5.1. Implement rendering mode detection—test Unicode character display and fall back to ASCII if needed. Create ASCII rendering alternative using +, -, |, = characters. Test on Windows Terminal and legacy console. Verify UTF-8 file encoding for script itself. Add -NoEncode parameter forcing ASCII mode for systems with Unicode problems.

**Phase 5: Profile Integration:**
Create installation script deploying TR-100 to standard location like `$HOME\Documents\PowerShell\Scripts\`. Modify user profile adding dot-sourcing statement with error handling. Set execution policy if needed. Provide uninstall script removing profile modifications. Test profile loading on clean system. Measure profile load time and optimize if exceeding 200ms.

**Phase 6: Cross-Platform Extension:**
Add platform detection at script start. Implement Linux-specific gathering using /proc filesystem: CPU info from /proc/cpuinfo, memory from /proc/meminfo, load average from /proc/loadavg. Implement macOS gathering using sysctl and vm_stat. Create unified output format regardless of platform. Test on Linux using Docker, macOS using virtual machine. Ensure identical output format across platforms—users shouldn't notice platform differences except in metrics themselves.

**Phase 7: Documentation and Packaging:**
Write comprehensive comment-based help with .SYNOPSIS, .DESCRIPTION, .PARAMETER sections, and multiple .EXAMPLE entries. Create README with installation instructions, system requirements, troubleshooting guide. Document encoding requirements and font recommendations. Provide configuration examples for different scenarios. Include screenshots showing proper Unicode rendering. Create GitHub repository with releases for easy distribution.

**Testing Checklist:**
Verify Windows PowerShell 5.1 compatibility. Verify PowerShell 7+ compatibility. Test on Windows Terminal and legacy console. Test with various fonts. Verify Unicode and ASCII rendering modes. Test on systems without admin privileges. Test with restrictive execution policies. Verify profile auto-loading. Test error handling with missing permissions. Validate output accuracy against native tools. Measure and optimize performance—full report generation should complete under 2 seconds.

This comprehensive guide provides all necessary information for converting the TR-100 bash script to PowerShell. The resulting script will support Windows PowerShell 5.1 and PowerShell 7+, display formatted output with box-drawing characters, auto-load from profiles, and optionally support cross-platform execution. PowerShell's object-oriented approach and rich system information APIs enable cleaner implementation than text-parsing bash equivalents while adding Windows-specific enhancements that elevate functionality beyond the original.