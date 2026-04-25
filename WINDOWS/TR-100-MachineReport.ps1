<#!
.SYNOPSIS
    TR-100 Machine Report for Windows (PowerShell implementation).

.DESCRIPTION
    Windows-native implementation of the TR-100 Machine Report originally written
    as a cross-platform bash script. This script collects system information
    using Windows APIs (CIM/WMI, performance counters, network cmdlets) and
    renders a Unicode box-drawing report very similar to the Unix version.

    It is designed to be:
      * Dot-sourced from a PowerShell profile so that the `report` command
        is available in every interactive session.
      * Executed directly as a script (e.g. via a batch shim or `-File`) to
        immediately show the report.

.NOTES
    Author  : TR-100 original by U.S. Graphics, LLC
              Windows port and enhancements by Emmett Shaughnessy (RealEmmettS)
    License : BSD-3-Clause
    Tested  : Windows PowerShell 5.1 and PowerShell 7+
#>

#region Encoding and box-drawing configuration

# Ensure UTF-8 output for proper box-drawing characters on Windows PowerShell 5.1
try {
    if ($PSVersionTable.PSEdition -eq 'Desktop' -and $env:OS -like 'Windows*') {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    }
} catch {
    # Non-fatal; fallback to whatever the console supports
}

# Box-drawing characters and bar fill characters
$script:TR100Chars = [pscustomobject]@{
    TopLeft      = [char]0x250C  # ┌
    TopRight     = [char]0x2510  # ┐
    BottomLeft   = [char]0x2514  # └
    BottomRight  = [char]0x2518  # ┘
    Horizontal   = [char]0x2500  # ─
    Vertical     = [char]0x2502  # │
    TDown        = [char]0x252C  # ┬
    TUp          = [char]0x2534  # ┴
    TRight       = [char]0x251C  # ├
    TLeft        = [char]0x2524  # ┤
    Cross        = [char]0x253C  # ┼
    BarFilled    = [char]0x2588  # █
    BarEmpty     = [char]0x2591  # ░
}

#endregion Encoding and box-drawing configuration

#region Utility helpers

function New-TR100BarGraph {
    [CmdletBinding()]
    param(
        [double]$Used,
        [double]$Total,
        [int]   $Width
    )

    if ($Total -le 0) {
        return ($TR100Chars.BarEmpty * [math]::Max($Width, 1))
    }

    $percent    = [math]::Max([math]::Min(($Used / $Total) * 100.0, 100.0), 0.0)
    $filledBars = [int]([math]::Round(($percent / 100.0) * $Width))
    if ($filledBars -gt $Width) { $filledBars = $Width }

    $filled = $TR100Chars.BarFilled * $filledBars
    $empty  = $TR100Chars.BarEmpty * ([math]::Max($Width,0) - $filledBars)
    return "$filled$empty"
}

function Get-TR100UptimeString {
    [CmdletBinding()]
    param()

    try {
        if (Get-Command Get-Uptime -ErrorAction SilentlyContinue) {
            $uptime = Get-Uptime
        } else {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $bootTime = $os.LastBootUpTime
            $uptime = (Get-Date) - $bootTime
        }

        $days  = [int]$uptime.Days
        $hours = [int]$uptime.Hours
        $mins  = [int]$uptime.Minutes

        $parts = @()
        if ($days  -gt 0) { $parts += "${days}d" }
        if ($hours -gt 0) { $parts += "${hours}h" }
        if ($mins  -gt 0 -or $parts.Count -eq 0) { $parts += "${mins}m" }
        return ($parts -join ' ')
    } catch {
        return 'Unknown'
    }
}

#endregion Utility helpers

#region Data collection

function Get-TR100Report {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    # Initialize variables with safe defaults
    $osName           = 'Unknown OS'
    $osKernel         = 'Unknown Kernel'
    $hostname         = $env:COMPUTERNAME
    $machineIP        = 'No IP found'
    $clientIP         = 'Not connected'
    $dnsServers       = @()
    $currentUser      = [Environment]::UserName

    $cpuModel         = 'Unknown CPU'
    $cpuCores         = 0
    $cpuSockets       = '-'
    $cpuHypervisor    = 'Unknown'
    $cpuFreqGHz       = ''
    $cpuUsagePercent  = $null

    $memTotalGiB      = 0.0
    $memUsedGiB       = 0.0
    $memPercent       = 0.0

    $diskTotalGiB     = 0.0
    $diskUsedGiB      = 0.0
    $diskPercent      = 0.0

    $lastLoginTime    = 'Login tracking unavailable'

    $uptimeString     = Get-TR100UptimeString

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $osName   = "{0} {1}" -f $os.Caption.Trim(), $os.Version
        $osKernel = "Windows {0}" -f $os.Version
    } catch { }

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs.Name) { $hostname = $cs.Name }

        # Hypervisor detection
        if ($cs.HypervisorPresent -eq $true) {
            $model = $cs.Model
            switch -Regex ($model) {
                'Virtual Machine' { $cpuHypervisor = 'Hyper-V'; break }
                'VMware'          { $cpuHypervisor = 'VMware'; break }
                'VirtualBox'      { $cpuHypervisor = 'VirtualBox'; break }
                default           { $cpuHypervisor = 'Virtualized' }
            }
        } else {
            $cpuHypervisor = 'Bare Metal'
        }
    } catch { }

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu) {
            $cpuModel = $cpu.Name.Trim()
            $cpuCores = $cpu.NumberOfLogicalProcessors
            $cpuSockets = $cpu.SocketDesignation
            if ($cpu.MaxClockSpeed -gt 0) {
                $cpuFreqGHz = [math]::Round($cpu.MaxClockSpeed / 1000.0, 2)
            }
        }
    } catch { }

    try {
        # Memory in KB from Win32_OperatingSystem
        $osMem = $os
        if (-not $osMem) {
            $osMem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        }

        $totalKB = [double]$osMem.TotalVisibleMemorySize
        $freeKB  = [double]$osMem.FreePhysicalMemory
        $usedKB  = $totalKB - $freeKB

        if ($totalKB -gt 0) {
            $memTotalGiB = [math]::Round($totalKB / (1024.0 * 1024.0), 2)
            $memUsedGiB  = [math]::Round($usedKB  / (1024.0 * 1024.0), 2)
            $memPercent  = [math]::Round(($usedKB / $totalKB) * 100.0, 2)
        }
    } catch { }

    try {
        # System drive (usually C:)
        $systemDrive = $env:SystemDrive
        if (-not $systemDrive) { $systemDrive = 'C:' }
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$systemDrive'" -ErrorAction Stop
        if ($disk.Size -gt 0) {
            $diskTotalGiB = [math]::Round($disk.Size / 1GB, 2)
            $diskUsedGiB  = [math]::Round(($disk.Size - $disk.FreeSpace) / 1GB, 2)
            $diskPercent  = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100.0, 2)
        }
    } catch { }

    try {
        # Machine IP (IPv4 preferred)
        if (Get-Command Get-NetIPAddress -ErrorAction SilentlyContinue) {
            $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
                 Select-Object -First 1 -ExpandProperty IPAddress
            if (-not $ip) {
                $ip = Get-NetIPAddress -AddressFamily IPv6 -ErrorAction SilentlyContinue |
                     Where-Object { $_.IPAddress -notlike 'fe80::*' } |
                     Select-Object -First 1 -ExpandProperty IPAddress
            }
            if ($ip) { $machineIP = $ip }
        } else {
            # Fallback to WMI-based network info
            $nics = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=true" -ErrorAction SilentlyContinue
            if ($nics) {
                $candidate = $nics | Where-Object { $_.IPAddress } | Select-Object -First 1
                if ($candidate -and $candidate.IPAddress) {
                    $machineIP = $candidate.IPAddress | Where-Object { $_ -notlike '127.*' } | Select-Object -First 1
                }
            }
        }
    } catch { }

    try {
        # DNS servers
        if (Get-Command Get-DnsClientServerAddress -ErrorAction SilentlyContinue) {
            $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.ServerAddresses } |
                ForEach-Object { $_.ServerAddresses } |
                Select-Object -First 5
        } elseif ($nics) {
            $dnsServers = $nics | Where-Object { $_.DNSServerSearchOrder } |
                ForEach-Object { $_.DNSServerSearchOrder } |
                Select-Object -First 5
        }
    } catch { }

    try {
        # Approximate client IP for SSH/remote sessions using environment variables
        if ($env:SSH_CLIENT -or $env:SSH_CONNECTION) {
            # SSH_CLIENT format: "client_ip client_port server_port"
            $raw = $env:SSH_CLIENT
            if (-not $raw) { $raw = $env:SSH_CONNECTION }
            if ($raw) {
                $clientIP = $raw.Split(' ')[0]
            }
        } else {
            $clientIP = 'Not connected'
        }
    } catch { }

    try {
        # CPU usage: instantaneous sample of % Processor Time
        if (Get-Command Get-Counter -ErrorAction SilentlyContinue) {
            $counter = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop
            $cpuUsagePercent = [math]::Round($counter.CounterSamples[0].CookedValue, 2)
        }
    } catch { }

    [pscustomobject]@{
        ReportTitle      = 'UNITED STATES GRAPHICS COMPANY'
        ReportSubtitle   = 'TR-100 MACHINE REPORT'

        OSName           = $osName
        OSKernel         = $osKernel

        Hostname         = $hostname
        MachineIP        = $machineIP
        ClientIP         = $clientIP
        DNSServers       = $dnsServers
        CurrentUser      = $currentUser

        CPUModel         = $cpuModel
        CPUCores         = $cpuCores
        CPUSockets       = $cpuSockets
        CPUHypervisor    = $cpuHypervisor
        CPUFreqGHz       = $cpuFreqGHz
        CPUUsagePercent  = $cpuUsagePercent

        MemTotalGiB      = $memTotalGiB
        MemUsedGiB       = $memUsedGiB
        MemPercent       = $memPercent

        DiskTotalGiB     = $diskTotalGiB
        DiskUsedGiB      = $diskUsedGiB
        DiskPercent      = $diskPercent

        LastLoginTime    = $lastLoginTime
        Uptime           = $uptimeString
    }
}

#endregion Data collection

#region Rendering

function Show-TR100Report {
    [CmdletBinding()]
    param()

    $data = Get-TR100Report

    # Build list of label/value pairs in order
    $rows = @()
    $rows += [pscustomobject]@{ Label = 'OS';        Value = $data.OSName }
    $rows += [pscustomobject]@{ Label = 'KERNEL';    Value = $data.OSKernel }
    $rows += 'DIVIDER'
    $rows += [pscustomobject]@{ Label = 'HOSTNAME';  Value = $data.Hostname }
    $rows += [pscustomobject]@{ Label = 'MACHINE IP';Value = $data.MachineIP }
    $rows += [pscustomobject]@{ Label = 'CLIENT  IP';Value = $data.ClientIP }

    if ($data.DNSServers -and $data.DNSServers.Count -gt 0) {
        $i = 1
        foreach ($dns in $data.DNSServers) {
            $rows += [pscustomobject]@{ Label = "DNS  IP $i"; Value = $dns }
            $i++
        }
    }

    $rows += [pscustomobject]@{ Label = 'USER';      Value = $data.CurrentUser }
    $rows += 'DIVIDER'

    $rows += [pscustomobject]@{ Label = 'PROCESSOR'; Value = $data.CPUModel }
    $rows += [pscustomobject]@{ Label = 'CORES';     Value = ("{0} vCPU(s) / {1} Socket(s)" -f $data.CPUCores, $data.CPUSockets) }
    $rows += [pscustomobject]@{ Label = 'HYPERVISOR';Value = $data.CPUHypervisor }
    if ($data.CPUFreqGHz) {
        $rows += [pscustomobject]@{ Label = 'CPU FREQ'; Value = ("{0} GHz" -f $data.CPUFreqGHz) }
    }

    # CPU load-style bar graphs (using instantaneous CPU percentage)
    $rows += [pscustomobject]@{ Label = 'LOAD  1m'; Value = '$CPU_LOAD_1M$' }
    $rows += [pscustomobject]@{ Label = 'LOAD  5m'; Value = '$CPU_LOAD_5M$' }
    $rows += [pscustomobject]@{ Label = 'LOAD 15m'; Value = '$CPU_LOAD_15M$' }

    $rows += 'DIVIDER'

    $rows += [pscustomobject]@{ Label = 'VOLUME';    Value = ("{0}/{1} GB [{2}%]" -f $data.DiskUsedGiB, $data.DiskTotalGiB, $data.DiskPercent) }
    $rows += [pscustomobject]@{ Label = 'DISK USAGE';Value = '$DISK_USAGE$' }

    $rows += 'DIVIDER'

    $rows += [pscustomobject]@{ Label = 'MEMORY';    Value = ("{0}/{1} GiB [{2}%]" -f $data.MemUsedGiB, $data.MemTotalGiB, $data.MemPercent) }
    $rows += [pscustomobject]@{ Label = 'USAGE';     Value = '$MEM_USAGE$' }

    $rows += 'DIVIDER'

    $rows += [pscustomobject]@{ Label = 'LAST LOGIN';Value = $data.LastLoginTime }
    $rows += [pscustomobject]@{ Label = 'UPTIME';    Value = $data.Uptime }

    # Compute column widths
    $labelStrings = $rows | Where-Object { $_ -isnot [string] } | ForEach-Object { $_.Label }
    $valueStrings = $rows | Where-Object { $_ -isnot [string] } | ForEach-Object { $_.Value }

    $minLabel = 5
    $maxLabel = 13
    $minData  = 20
    $maxData  = 32

    $labelWidth = $labelStrings | ForEach-Object { $_.Length } | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
    if (-not $labelWidth) { $labelWidth = $minLabel }
    $labelWidth = [math]::Max($minLabel, [math]::Min($labelWidth, $maxLabel))

    $dataWidth = $valueStrings | ForEach-Object { ($_.ToString()).Length } | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
    if (-not $dataWidth) { $dataWidth = $minData }
    $dataWidth = [math]::Max($minData, [math]::Min($dataWidth, $maxData))

    # Bar graph width based on data column width
    $barWidth = $dataWidth

    # Now that we know bar width, generate bar strings and substitute placeholders
    $cpuUsed = if ($data.CPUUsagePercent -ne $null) { $data.CPUUsagePercent } else { 0 }
    $cpuBar  = New-TR100BarGraph -Used $cpuUsed -Total 100 -Width $barWidth

    $diskBar = New-TR100BarGraph -Used $data.DiskUsedGiB -Total $data.DiskTotalGiB -Width $barWidth
    $memBar  = New-TR100BarGraph -Used $data.MemUsedGiB -Total $data.MemTotalGiB -Width $barWidth

    $rows = $rows | ForEach-Object {
        if ($_ -is [string]) { return $_ }
        $value = $_.Value
        switch ($value) {
            '$CPU_LOAD_1M$'  { $value = $cpuBar }
            '$CPU_LOAD_5M$'  { $value = $cpuBar }
            '$CPU_LOAD_15M$' { $value = $cpuBar }
            '$DISK_USAGE$'   { $value = $diskBar }
            '$MEM_USAGE$'    { $value = $memBar }
        }
        [pscustomobject]@{ Label = $_.Label; Value = $value }
    }

    # Total inner width of table (excluding outer borders)
    $innerWidth = 2 + $labelWidth + 3 + $dataWidth + 2  # "│ <label> │ <value> │"

    # Helper to write the top header and borders
    function Write-TR100TopHeader {
        param()
        $top = $TR100Chars.TopLeft + ($TR100Chars.Horizontal * ($innerWidth)) + $TR100Chars.TopRight
        Write-Host $top
        $mid = $TR100Chars.TRight + ($TR100Chars.TDown * ($innerWidth)) + $TR100Chars.TLeft
        Write-Host $mid
    }

    function Write-TR100Divider {
        param([string]$Position)

        $left  = $TR100Chars.TRight
        $right = $TR100Chars.TLeft
        $mid   = if ($Position -eq 'Bottom') { $TR100Chars.TUp } else { $TR100Chars.Cross }

        $line = $left
        for ($i = 0; $i -lt $innerWidth; $i++) {
            if ($i -eq ($labelWidth + 2)) {
                $line += $mid
            } else {
                $line += $TR100Chars.Horizontal
            }
        }
        $line += $right
        Write-Host $line
    }

    function Write-TR100Footer {
        param()
        $bottom = $TR100Chars.BottomLeft + ($TR100Chars.Horizontal * ($innerWidth)) + $TR100Chars.BottomRight
        Write-Host $bottom
    }

    function Write-TR100CenteredLine {
        param([string]$Text)
        $totalWidth = $innerWidth
        $text = $Text
        if ($text.Length -gt $totalWidth) {
            $text = $text.Substring(0, $totalWidth)
        }
        $padding = $totalWidth - $text.Length
        $leftPad  = [int]([math]::Floor($padding / 2.0))
        $rightPad = $padding - $leftPad
        Write-Host ("{0}{1}{2}{3}{4}" -f $TR100Chars.Vertical, ' ' * $leftPad, $text, ' ' * $rightPad, $TR100Chars.Vertical)
    }

    function Write-TR100Row {
        param(
            [string]$Label,
            [string]$Value
        )

        # Trim/truncate label
        $lbl = $Label
        if ($lbl.Length -gt $labelWidth) {
            $lbl = $lbl.Substring(0, [math]::Max($labelWidth - 3, 1)) + '...'
        } else {
            $lbl = $lbl.PadRight($labelWidth)
        }

        # Trim/truncate value
        $val = $Value
        if ($null -eq $val) { $val = '' }
        if ($val.Length -gt $dataWidth) {
            $val = $val.Substring(0, [math]::Max($dataWidth - 3, 1)) + '...'
        } else {
            $val = $val.PadRight($dataWidth)
        }

        Write-Host ("{0} {1} {2} {3} {4}" -f $TR100Chars.Vertical, $lbl, $TR100Chars.Vertical, $val, $TR100Chars.Vertical)
    }

    # Render table
    Write-TR100TopHeader
    Write-TR100CenteredLine -Text $data.ReportTitle
    Write-TR100CenteredLine -Text $data.ReportSubtitle
    Write-TR100Divider -Position 'Top'

    foreach ($row in $rows) {
        if ($row -is [string]) {
            if ($row -eq 'DIVIDER') {
                Write-TR100Divider -Position 'Middle'
            }
        } else {
            Write-TR100Row -Label $row.Label -Value ($row.Value.ToString())
        }
    }

    Write-TR100Divider -Position 'Bottom'
    Write-TR100Footer
}

#endregion Rendering

# If the script is executed directly (not dot-sourced), show the report immediately
try {
    if ($MyInvocation.InvocationName -ne '.') {
        # Only auto-run when invoked as a script, not when dot-sourced from a profile
        Show-TR100Report
    }
} catch {
    Write-Error $_
}
