#!/usr/bin/env -S rust-script
//! ```cargo
//! [dependencies]
//! anyhow = "1"
//! sysinfo = "0.32"
//! libc = "0.2"
//! nix = { version = "0.29", features = ["user", "net", "hostname"] }
//! regex = "1"
//! ```

use anyhow::{Context, Result};
use std::fs;
use std::process::Command;
use std::collections::HashMap;

// Configuration
const MAX_NAME_LEN: usize = 13;
const MIN_DATA_LEN: usize = 20;
const MAX_DATA_LEN: usize = 32;
const BORDERS_AND_PADDING: usize = 7;

struct SystemInfo {
    report_title: String,

    // OS info
    os_name: String,
    os_kernel: String,

    // Network info
    net_hostname: String,
    net_machine_ip: String,
    net_client_ip: String,
    net_current_user: String,
    net_dns_ips: Vec<String>,

    // CPU info
    cpu_model: String,
    cpu_cores: usize,
    cpu_cores_per_socket: usize,
    cpu_sockets: usize,
    cpu_hypervisor: String,
    cpu_freq: f64,
    load_avg_1min: f64,
    load_avg_5min: f64,
    load_avg_15min: f64,

    // Memory info
    mem_total: u64,
    mem_used: u64,
    mem_percent: f64,
    mem_total_gb: f64,
    mem_used_gb: f64,

    // Disk info
    disk_used_gb: f64,
    disk_total_gb: f64,
    disk_percent: f64,
    zfs_present: bool,
    zfs_health: Option<String>,

    // Last login info
    last_login_time: String,
    last_login_ip: Option<String>,

    // Uptime
    sys_uptime: String,
}

impl SystemInfo {
    fn new() -> Result<Self> {
        let mut info = SystemInfo {
            report_title: "UNITED STATES GRAPHICS COMPANY".to_string(),
            os_name: String::new(),
            os_kernel: String::new(),
            net_hostname: String::new(),
            net_machine_ip: String::new(),
            net_client_ip: String::new(),
            net_current_user: String::new(),
            net_dns_ips: Vec::new(),
            cpu_model: String::new(),
            cpu_cores: 0,
            cpu_cores_per_socket: 0,
            cpu_sockets: 0,
            cpu_hypervisor: String::new(),
            cpu_freq: 0.0,
            load_avg_1min: 0.0,
            load_avg_5min: 0.0,
            load_avg_15min: 0.0,
            mem_total: 0,
            mem_used: 0,
            mem_percent: 0.0,
            mem_total_gb: 0.0,
            mem_used_gb: 0.0,
            disk_used_gb: 0.0,
            disk_total_gb: 0.0,
            disk_percent: 0.0,
            zfs_present: false,
            zfs_health: None,
            last_login_time: String::new(),
            last_login_ip: None,
            sys_uptime: String::new(),
        };

        info.gather_os_info()?;
        info.gather_network_info()?;
        info.gather_cpu_info()?;
        info.gather_memory_info()?;
        info.gather_disk_info()?;
        info.gather_login_info()?;
        info.gather_uptime_info()?;

        Ok(info)
    }

    fn gather_os_info(&mut self) -> Result<()> {
        // Read /etc/os-release
        let os_release = fs::read_to_string("/etc/os-release")
            .context("Failed to read /etc/os-release")?;

        let mut os_data = HashMap::new();
        for line in os_release.lines() {
            if let Some((key, value)) = line.split_once('=') {
                let value = value.trim_matches('"');
                os_data.insert(key, value);
            }
        }

        let id = os_data.get("ID").unwrap_or(&"Unknown");
        let version = os_data.get("VERSION").unwrap_or(&"");
        let codename = os_data.get("VERSION_CODENAME").unwrap_or(&"");

        // Capitalize first letter of ID and codename
        let id_cap = capitalize_first(id);
        let codename_cap = capitalize_first(codename);

        self.os_name = format!("{} {} {}", id_cap, version, codename_cap).trim().to_string();

        // Get kernel info
        let uname_output = Command::new("uname").output()?;
        let uname_r_output = Command::new("uname").arg("-r").output()?;

        let uname = String::from_utf8_lossy(&uname_output.stdout).trim().to_string();
        let uname_r = String::from_utf8_lossy(&uname_r_output.stdout).trim().to_string();

        self.os_kernel = format!("{} {}", uname, uname_r);

        Ok(())
    }

    fn gather_network_info(&mut self) -> Result<()> {
        // Get current user
        self.net_current_user = std::env::var("USER")
            .or_else(|_| nix::unistd::User::from_uid(nix::unistd::getuid())
                .map(|u| u.map(|user| user.name).unwrap_or_else(|| "unknown".to_string())))
            .unwrap_or_else(|_| "unknown".to_string());

        // Get hostname
        self.net_hostname = nix::unistd::gethostname()
            .ok()
            .and_then(|h| h.into_string().ok())
            .unwrap_or_else(|| "Not Defined".to_string());

        // Get machine IP
        self.net_machine_ip = get_ip_addr();

        // Get client IP (from who am i)
        let who_output = Command::new("who").arg("am").arg("i").output();
        if let Ok(output) = who_output {
            let who_str = String::from_utf8_lossy(&output.stdout);
            self.net_client_ip = extract_client_ip(&who_str);
        } else {
            self.net_client_ip = "Not connected".to_string();
        }

        // Get DNS IPs
        if let Ok(resolv_conf) = fs::read_to_string("/etc/resolv.conf") {
            for line in resolv_conf.lines() {
                if line.starts_with("nameserver") {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 2 && parts[1].contains('.') {
                        self.net_dns_ips.push(parts[1].to_string());
                    }
                }
            }
        }

        Ok(())
    }

    fn gather_cpu_info(&mut self) -> Result<()> {
        // Parse lscpu output
        let lscpu_output = Command::new("lscpu").output()?;
        let lscpu_str = String::from_utf8_lossy(&lscpu_output.stdout);

        for line in lscpu_str.lines() {
            if line.contains("Model name:") && !line.contains("BIOS") {
                let parts: Vec<&str> = line.split(':').collect();
                if parts.len() >= 2 {
                    let words: Vec<&str> = parts[1].split_whitespace().collect();
                    self.cpu_model = words.iter().take(4).map(|s| s.to_string()).collect::<Vec<_>>().join(" ");
                }
            } else if line.contains("Hypervisor vendor:") {
                let parts: Vec<&str> = line.split(':').collect();
                if parts.len() >= 2 {
                    self.cpu_hypervisor = parts[1].trim().to_string();
                }
            } else if line.contains("Core(s) per socket:") {
                let parts: Vec<&str> = line.split(':').collect();
                if parts.len() >= 2 {
                    self.cpu_cores_per_socket = parts[1].trim().parse().unwrap_or(1);
                }
            } else if line.contains("Socket(s):") {
                let parts: Vec<&str> = line.split(':').collect();
                if parts.len() >= 2 {
                    self.cpu_sockets = parts[1].trim().parse().unwrap_or(1);
                }
            }
        }

        if self.cpu_hypervisor.is_empty() {
            self.cpu_hypervisor = "Bare Metal".to_string();
        }

        // Get CPU cores
        let nproc_output = Command::new("nproc").arg("--all").output()?;
        self.cpu_cores = String::from_utf8_lossy(&nproc_output.stdout)
            .trim()
            .parse()
            .unwrap_or(1);

        // Get CPU frequency from /proc/cpuinfo
        if let Ok(cpuinfo) = fs::read_to_string("/proc/cpuinfo") {
            for line in cpuinfo.lines() {
                if line.starts_with("cpu MHz") {
                    let parts: Vec<&str> = line.split(':').collect();
                    if parts.len() >= 2 {
                        if let Ok(mhz) = parts[1].trim().parse::<f64>() {
                            self.cpu_freq = mhz / 1000.0;
                            break;
                        }
                    }
                }
            }
        }

        // Get load averages
        if let Ok(loadavg) = fs::read_to_string("/proc/loadavg") {
            let parts: Vec<&str> = loadavg.split_whitespace().collect();
            if parts.len() >= 3 {
                self.load_avg_1min = parts[0].parse().unwrap_or(0.0);
                self.load_avg_5min = parts[1].parse().unwrap_or(0.0);
                self.load_avg_15min = parts[2].parse().unwrap_or(0.0);
            }
        }

        Ok(())
    }

    fn gather_memory_info(&mut self) -> Result<()> {
        if let Ok(meminfo) = fs::read_to_string("/proc/meminfo") {
            let mut mem_total_kb = 0u64;
            let mut mem_available_kb = 0u64;

            for line in meminfo.lines() {
                if line.starts_with("MemTotal:") {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 2 {
                        mem_total_kb = parts[1].parse().unwrap_or(0);
                    }
                } else if line.starts_with("MemAvailable:") {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 2 {
                        mem_available_kb = parts[1].parse().unwrap_or(0);
                    }
                }
            }

            self.mem_total = mem_total_kb;
            self.mem_used = mem_total_kb.saturating_sub(mem_available_kb);
            self.mem_percent = if mem_total_kb > 0 {
                (self.mem_used as f64 / mem_total_kb as f64) * 100.0
            } else {
                0.0
            };

            self.mem_total_gb = mem_total_kb as f64 / (1024.0 * 1024.0);
            self.mem_used_gb = self.mem_used as f64 / (1024.0 * 1024.0);
        }

        Ok(())
    }

    fn gather_disk_info(&mut self) -> Result<()> {
        // Check if ZFS is present
        let zfs_check = Command::new("which").arg("zfs").output();
        let zfs_mounts = fs::read_to_string("/proc/mounts")
            .unwrap_or_default()
            .contains("zfs");

        if zfs_check.is_ok() && zfs_mounts {
            self.zfs_present = true;
            let zfs_filesystem = "zroot/ROOT/os";

            // Get ZFS health
            let health_output = Command::new("zpool")
                .args(&["status", "-x", "zroot"])
                .output();

            if let Ok(output) = health_output {
                let health_str = String::from_utf8_lossy(&output.stdout);
                if health_str.contains("is healthy") {
                    self.zfs_health = Some("HEALTH O.K.".to_string());
                }
            }

            // Get ZFS available space
            let available_output = Command::new("zfs")
                .args(&["get", "-o", "value", "-Hp", "available", zfs_filesystem])
                .output();

            let used_output = Command::new("zfs")
                .args(&["get", "-o", "value", "-Hp", "used", zfs_filesystem])
                .output();

            if let (Ok(avail), Ok(used)) = (available_output, used_output) {
                let available_bytes: u64 = String::from_utf8_lossy(&avail.stdout)
                    .trim()
                    .parse()
                    .unwrap_or(0);
                let used_bytes: u64 = String::from_utf8_lossy(&used.stdout)
                    .trim()
                    .parse()
                    .unwrap_or(0);

                self.disk_total_gb = available_bytes as f64 / (1024.0 * 1024.0 * 1024.0);
                self.disk_used_gb = used_bytes as f64 / (1024.0 * 1024.0 * 1024.0);
                self.disk_percent = if available_bytes > 0 {
                    (used_bytes as f64 / available_bytes as f64) * 100.0
                } else {
                    0.0
                };
            }
        } else {
            // Use df for root partition
            let df_output = Command::new("df")
                .args(&["-m", "/"])
                .output()?;

            let df_str = String::from_utf8_lossy(&df_output.stdout);
            let lines: Vec<&str> = df_str.lines().collect();

            if lines.len() >= 2 {
                let parts: Vec<&str> = lines[1].split_whitespace().collect();
                if parts.len() >= 4 {
                    let total_mb: u64 = parts[1].parse().unwrap_or(0);
                    let used_mb: u64 = parts[2].parse().unwrap_or(0);

                    self.disk_total_gb = total_mb as f64 / 1024.0;
                    self.disk_used_gb = used_mb as f64 / 1024.0;
                    self.disk_percent = if total_mb > 0 {
                        (used_mb as f64 / total_mb as f64) * 100.0
                    } else {
                        0.0
                    };
                }
            }
        }

        Ok(())
    }

    fn gather_login_info(&mut self) -> Result<()> {
        // Try lastlog2 first (for Ubuntu 25.04+), then fall back to lastlog
        let username = &self.net_current_user;

        let lastlog_output = Command::new("lastlog2")
            .arg("show")
            .arg("--user")
            .arg(username)
            .output()
            .or_else(|_| Command::new("lastlog").arg("-u").arg(username).output());

        if let Ok(output) = lastlog_output {
            let lastlog_str = String::from_utf8_lossy(&output.stdout);
            let lines: Vec<&str> = lastlog_str.lines().collect();

            // Parse lastlog output
            if lines.len() >= 2 {
                let data_line = lines[1];
                let parts: Vec<&str> = data_line.split_whitespace().collect();

                // Check if there's an IP address in the output
                let ip_regex = regex::Regex::new(r"^\d+\.\d+\.\d+\.\d+$").unwrap();

                if parts.len() >= 4 {
                    // Try to find IP address
                    let mut found_ip = false;
                    for (i, part) in parts.iter().enumerate() {
                        if ip_regex.is_match(part) {
                            self.last_login_ip = Some(part.to_string());
                            found_ip = true;

                            // Time format: month day year time
                            if i >= 3 {
                                self.last_login_time = format!(
                                    "{} {} {} {}",
                                    parts.get(i.saturating_sub(2)).unwrap_or(&""),
                                    parts.get(i.saturating_sub(1)).unwrap_or(&""),
                                    parts.get(i + 2).unwrap_or(&""),
                                    parts.get(i + 1).unwrap_or(&"")
                                ).trim().to_string();
                            }
                            break;
                        }
                    }

                    if !found_ip {
                        // No IP, check for "Never logged in"
                        if data_line.contains("**Never") || data_line.contains("Never logged in") {
                            self.last_login_time = "Never logged in".to_string();
                        } else if parts.len() >= 6 {
                            // Format without IP
                            self.last_login_time = format!(
                                "{} {} {} {}",
                                parts.get(3).unwrap_or(&""),
                                parts.get(4).unwrap_or(&""),
                                parts.get(7).unwrap_or(&""),
                                parts.get(5).unwrap_or(&"")
                            ).trim().to_string();
                        }
                    }
                }
            }
        }

        if self.last_login_time.is_empty() {
            self.last_login_time = "Unknown".to_string();
        }

        Ok(())
    }

    fn gather_uptime_info(&mut self) -> Result<()> {
        let uptime_output = Command::new("uptime")
            .arg("-p")
            .output()?;

        let uptime_str = String::from_utf8_lossy(&uptime_output.stdout);
        self.sys_uptime = uptime_str
            .trim()
            .replace("up ", "")
            .replace(" days", "d")
            .replace(" day", "d")
            .replace(" hours", "h")
            .replace(" hour", "h")
            .replace(" minutes", "m")
            .replace(" minute", "m")
            .replace(",", "");

        Ok(())
    }

    fn max_data_length(&self) -> usize {
        let mut lengths = vec![
            self.report_title.len(),
            self.os_name.len(),
            self.os_kernel.len(),
            self.net_hostname.len(),
            self.net_machine_ip.len(),
            self.net_client_ip.len(),
            self.net_current_user.len(),
            self.cpu_model.len(),
            self.cpu_hypervisor.len(),
            self.last_login_time.len(),
            self.sys_uptime.len(),
        ];

        // Add formatted string lengths
        lengths.push(format!("{} vCPU(s) / {} Socket(s)", self.cpu_cores_per_socket, self.cpu_sockets).len());
        lengths.push(format!("{:.2} GHz", self.cpu_freq).len());
        lengths.push(format!("{:.2}/{:.2} GB [{:.2}%]", self.disk_used_gb, self.disk_total_gb, self.disk_percent).len());
        lengths.push(format!("{:.2}/{:.2} GiB [{:.2}%]", self.mem_used_gb, self.mem_total_gb, self.mem_percent).len());

        let max = lengths.iter().max().copied().unwrap_or(MIN_DATA_LEN);
        max.min(MAX_DATA_LEN)
    }
}

fn capitalize_first(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        None => String::new(),
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
    }
}

fn get_ip_addr() -> String {
    // Try ifconfig first
    if let Ok(output) = Command::new("ifconfig").output() {
        let ifconfig_str = String::from_utf8_lossy(&output.stdout);

        // Look for IPv4 address (not lo, not docker)
        for block in ifconfig_str.split('\n') {
            if block.contains("inet ") && !block.contains("127.0.0.1") {
                let parts: Vec<&str> = block.split_whitespace().collect();
                for (i, part) in parts.iter().enumerate() {
                    if *part == "inet" && i + 1 < parts.len() {
                        return parts[i + 1].to_string();
                    }
                }
            }
        }
    }

    // Try ip command
    if let Ok(output) = Command::new("ip").args(&["-o", "-4", "addr", "show"]).output() {
        let ip_str = String::from_utf8_lossy(&output.stdout);

        for line in ip_str.lines() {
            if !line.contains(" lo ") && !line.contains("docker") {
                let parts: Vec<&str> = line.split_whitespace().collect();
                for (i, part) in parts.iter().enumerate() {
                    if *part == "inet" && i + 1 < parts.len() {
                        let addr = parts[i + 1].split('/').next().unwrap_or("");
                        if !addr.is_empty() {
                            return addr.to_string();
                        }
                    }
                }
            }
        }
    }

    "No IP found".to_string()
}

fn extract_client_ip(who_output: &str) -> String {
    let re = regex::Regex::new(r"\(([0-9.]+)\)").unwrap();
    if let Some(caps) = re.captures(who_output) {
        if let Some(ip) = caps.get(1) {
            return ip.as_str().to_string();
        }
    }
    "Not connected".to_string()
}

fn bar_graph(used: f64, total: f64, width: usize) -> String {
    let percent = if total > 0.0 {
        (used / total) * 100.0
    } else {
        0.0
    };

    let num_blocks = ((percent / 100.0) * width as f64) as usize;
    let filled = "█".repeat(num_blocks);
    let empty = "░".repeat(width.saturating_sub(num_blocks));

    format!("{}{}", filled, empty)
}

struct TablePrinter {
    current_len: usize,
}

impl TablePrinter {
    fn new(current_len: usize) -> Self {
        Self { current_len }
    }

    fn total_width(&self) -> usize {
        self.current_len + MAX_NAME_LEN + BORDERS_AND_PADDING
    }

    fn print_header(&self) {
        let length = self.total_width();
        let mut top = "┌".to_string();
        let mut bottom = "├".to_string();

        for _ in 0..length - 2 {
            top.push('┬');
            bottom.push('┴');
        }

        top.push('┐');
        bottom.push('┤');

        println!("{}", top);
        println!("{}", bottom);
    }

    fn print_centered_data(&self, text: &str) {
        let max_len = self.current_len + MAX_NAME_LEN - BORDERS_AND_PADDING;
        let total_width = max_len + 12;
        let text_len = text.len();
        let padding_left = (total_width - text_len) / 2;
        let padding_right = total_width - text_len - padding_left;

        println!("│{:padding_left$}{}{:padding_right$}│",
            "", text, "",
            padding_left = padding_left,
            padding_right = padding_right
        );
    }

    fn print_divider(&self, side: &str) {
        let (left_symbol, middle_symbol, right_symbol) = match side {
            "top" => ("├", "┬", "┤"),
            "bottom" => ("└", "┴", "┘"),
            _ => ("├", "┼", "┤"),
        };

        // The data line format is: "│ NAME(13 chars) │ DATA │"
        // So the middle │ appears at position: 1(│) + 1(space) + 13(name) + 1(space) = 16
        let middle_position = 1 + 1 + MAX_NAME_LEN + 1; // = 16

        let mut divider = String::new();
        divider.push_str(left_symbol);

        let total_dashes = self.total_width() - 2; // Total chars minus left and right symbols

        for i in 0..total_dashes {
            if i == middle_position - 1 { // -1 because we already added left_symbol
                divider.push_str(middle_symbol);
            } else {
                divider.push('─');
            }
        }

        divider.push_str(right_symbol);
        println!("{}", divider);
    }

    fn print_data(&self, name: &str, data: &str) {
        let max_data_len = self.current_len;

        // Format name - left align and pad to MAX_NAME_LEN
        let formatted_name = if name.len() > MAX_NAME_LEN {
            // Truncate if too long
            format!("{}...", &name[..MAX_NAME_LEN - 3])
        } else {
            // Pad to MAX_NAME_LEN for all other cases
            format!("{:<width$}", name, width = MAX_NAME_LEN)
        };

        // Format data - left align and pad to max_data_len
        // Note: We need to be careful with UTF-8 character boundaries
        let formatted_data = if data.chars().count() > max_data_len {
            // Truncate by character count, not bytes, to handle multi-byte chars like █
            let truncated: String = data.chars().take(max_data_len.saturating_sub(3)).collect();
            let truncated_with_ellipsis = format!("{}...", truncated);
            format!("{:<width$}", truncated_with_ellipsis, width = max_data_len)
        } else {
            format!("{:<width$}", data, width = max_data_len)
        };

        // formatted_name is already padded to MAX_NAME_LEN, formatted_data is already padded
        println!("│ {} │ {} │", formatted_name, formatted_data);
    }
}

fn main() -> Result<()> {
    let info = SystemInfo::new()?;
    let current_len = info.max_data_length();
    let printer = TablePrinter::new(current_len);

    // Print report
    printer.print_header();
    printer.print_centered_data(&info.report_title);
    printer.print_centered_data("TR-100 MACHINE REPORT");
    printer.print_divider("top");

    printer.print_data("OS", &info.os_name);
    printer.print_data("KERNEL", &info.os_kernel);
    printer.print_divider("");

    printer.print_data("HOSTNAME", &info.net_hostname);
    printer.print_data("MACHINE IP", &info.net_machine_ip);
    printer.print_data("CLIENT  IP", &info.net_client_ip);

    for (i, dns_ip) in info.net_dns_ips.iter().enumerate() {
        printer.print_data(&format!("DNS  IP {}", i + 1), dns_ip);
    }

    printer.print_data("USER", &info.net_current_user);
    printer.print_divider("");

    printer.print_data("PROCESSOR", &info.cpu_model);
    printer.print_data("CORES", &format!("{} vCPU(s) / {} Socket(s)",
        info.cpu_cores_per_socket, info.cpu_sockets));
    printer.print_data("HYPERVISOR", &info.cpu_hypervisor);
    printer.print_data("CPU FREQ", &format!("{:.2} GHz", info.cpu_freq));

    let cpu_1min_graph = bar_graph(info.load_avg_1min, info.cpu_cores as f64, current_len);
    let cpu_5min_graph = bar_graph(info.load_avg_5min, info.cpu_cores as f64, current_len);
    let cpu_15min_graph = bar_graph(info.load_avg_15min, info.cpu_cores as f64, current_len);

    printer.print_data("LOAD  1m", &cpu_1min_graph);
    printer.print_data("LOAD  5m", &cpu_5min_graph);
    printer.print_data("LOAD 15m", &cpu_15min_graph);

    printer.print_divider("");

    if info.zfs_present {
        printer.print_data("VOLUME", &format!("{:.2}/{:.2} GB [{:.2}%]",
            info.disk_used_gb, info.disk_total_gb, info.disk_percent));
        let disk_graph = bar_graph(info.disk_used_gb, info.disk_total_gb, current_len);
        printer.print_data("DISK USAGE", &disk_graph);
        if let Some(health) = &info.zfs_health {
            printer.print_data("ZFS HEALTH", health);
        }
    } else {
        printer.print_data("VOLUME", &format!("{:.2}/{:.2} GB [{:.2}%]",
            info.disk_used_gb, info.disk_total_gb, info.disk_percent));
        let disk_graph = bar_graph(info.disk_used_gb, info.disk_total_gb, current_len);
        printer.print_data("DISK USAGE", &disk_graph);
    }

    printer.print_divider("");

    printer.print_data("MEMORY", &format!("{:.2}/{:.2} GiB [{:.2}%]",
        info.mem_used_gb, info.mem_total_gb, info.mem_percent));
    let mem_graph = bar_graph(info.mem_used as f64, info.mem_total as f64, current_len);
    printer.print_data("USAGE", &mem_graph);

    printer.print_divider("");

    printer.print_data("LAST LOGIN", &info.last_login_time);
    if let Some(ip) = &info.last_login_ip {
        printer.print_data("", ip);
    }

    printer.print_data("UPTIME", &info.sys_uptime);
    printer.print_divider("bottom");

    Ok(())
}
