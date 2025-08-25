#!/bin/bash

# Script to completely remove Grafana and InfluxDB from RHEL 9 ppc64le
# Run as root or with sudo
# Date: August 25, 2025

# Exit on any error
set -e

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_message "ERROR: This script must be run as root. Use sudo."
    exit 1
fi

# Step 1: Stop running services
log_message "Stopping Grafana and InfluxDB services..."
systemctl stop grafana-server 2>/dev/null || true
systemctl disable grafana-server 2>/dev/null || true
systemctl stop influxdb 2>/dev/null || true
systemctl disable influxdb 2>/dev/null || true

# Terminate any lingering processes
log_message "Terminating any lingering Grafana and InfluxDB processes..."
killall grafana-server 2>/dev/null || true
killall influxd 2>/dev/null || true

# Step 2: Uninstall packages
log_message "Removing Grafana and InfluxDB packages..."
dnf remove -y grafana influxdb 2>/dev/null || true
rpm -e $(rpm -qa | grep -E 'grafana|influxdb') 2>/dev/null || true

# Verify packages are removed
if rpm -qa | grep -q -E 'grafana|influxdb'; then
    log_message "WARNING: Some Grafana or InfluxDB packages may still be installed."
else
    log_message "Packages successfully removed."
fi

# Step 3: Remove configuration files
log_message "Removing configuration files..."
rm -rf /etc/influxdb /etc/grafana 2>/dev/null || true
find /etc -name '*influxdb*' -o -name '*grafana*' -exec rm -rf {} + 2>/dev/null || true

# Step 4: Remove data directories
log_message "Removing data directories..."
rm -rf /var/lib/influxdb /var/lib/grafana /opt/influxdb 2>/dev/null || true
find /var -name '*influxdb*' -o -name '*grafana*' -exec rm -rf {} + 2>/dev/null || true

# Step 5: Remove log files
log_message "Removing log files..."
rm -rf /var/log/influxdb /var/log/grafana /usr/share/grafana/data/log 2>/dev/null || true
find /var/log -name '*influxdb*' -o -name '*grafana*' -exec rm -rf {} + 2>/dev/null || true

# Step 6: Remove repository configurations
log_message "Removing repository configurations..."
rm /etc/yum.repos.d/grafana.repo /etc/yum.repos.d/influxdb.repo 2>/dev/null || true
dnf clean all 2>/dev/null || true

# Step 7: Remove systemd service files
log_message "Removing systemd service files..."
rm /usr/lib/systemd/system/influxdb.service /usr/lib/systemd/system/grafana-server.service 2>/dev/null || true
rm -rf /etc/systemd/system/influxdb.service.d /etc/systemd/system/grafana-server.service.d 2>/dev/null || true
systemctl daemon-reload

# Verify services are removed
if systemctl list-units | grep -q -E 'grafana|influxdb'; then
    log_message "WARNING: Some Grafana or InfluxDB services may still be registered."
else
    log_message "Services successfully removed."
fi

# Step 8: Remove firewall rules
log_message "Removing firewall rules for ports 3000 (Grafana) and 8086 (InfluxDB)..."
firewall-cmd --remove-port=3000/tcp --permanent 2>/dev/null || true
firewall-cmd --remove-port=8086/tcp --permanent 2>/dev/null || true
firewall-cmd --reload 2>/dev/null || true

# Step 9: Final verification
log_message "Performing final verification..."
if find / -name '*influxdb*' -o -name '*grafana*' | grep -q . | grep -v rpm; then
    log_message "WARNING: Some residual files may remain. Check output of 'find / -name *influxdb* -o -name *grafana*' for details."
else
    log_message "No residual Grafana or InfluxDB files found."
fi

log_message "Grafana and InfluxDB removal completed successfully."