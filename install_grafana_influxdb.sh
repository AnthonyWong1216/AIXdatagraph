#!/bin/bash

# Script to install Grafana and InfluxDB on RHEL 9 ppc64le
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

# Check if packages directory exists
PACKAGES_DIR="./packages"
if [ ! -d "$PACKAGES_DIR" ]; then
    log_message "ERROR: Packages directory '$PACKAGES_DIR' not found."
    log_message "Please ensure the packages directory exists and contains the required RPM files."
    exit 1
fi

# Check if required RPM files exist
INFLUXDB_RPM="$PACKAGES_DIR/influxdb-1.8.3-1.el8.ppc64le.rpm"
GRAFANA_RPM="$PACKAGES_DIR/grafana-7.3.6-1.el8.ppc64le.rpm"

if [ ! -f "$INFLUXDB_RPM" ]; then
    log_message "ERROR: InfluxDB RPM file not found: $INFLUXDB_RPM"
    exit 1
fi

if [ ! -f "$GRAFANA_RPM" ]; then
    log_message "ERROR: Grafana RPM file not found: $GRAFANA_RPM"
    exit 1
fi

log_message "Starting installation of InfluxDB and Grafana..."

# Step 1: Install packages
log_message "Installing InfluxDB package..."
rpm -ivh "$INFLUXDB_RPM"

log_message "Installing Grafana package..."
rpm -ivh "$GRAFANA_RPM"

# Step 2: Modify InfluxDB service file
log_message "Modifying InfluxDB service configuration..."
if [ -f "/etc/systemd/system/influxdb.service" ]; then
    # Backup original file
    cp /etc/systemd/system/influxdb.service /etc/systemd/system/influxdb.service.backup
    
    # Update ExecStart line
    sed -i 's|^ExecStart=.*|ExecStart=/usr/bin/influxd --config /etc/influxdb/influxdb.conf|' /etc/systemd/system/influxdb.service
    
    log_message "InfluxDB service file updated successfully."
else
    log_message "WARNING: InfluxDB service file not found at /etc/systemd/system/influxdb.service"
fi

# Step 3: Modify Grafana service file
log_message "Modifying Grafana service configuration..."
if [ -f "/etc/systemd/system/grafana-server.service" ]; then
    # Backup original file
    cp /etc/systemd/system/grafana-server.service /etc/systemd/system/grafana-server.service.backup
    
    # Update ExecStart line
    sed -i 's|^ExecStart=.*|ExecStart=/usr/sbin/grafana-server --config=/etc/grafana/grafana.ini --homepath=/usr/share/grafana|' /etc/systemd/system/grafana-server.service
    
    log_message "Grafana service file updated successfully."
else
    log_message "WARNING: Grafana service file not found at /etc/systemd/system/grafana-server.service"
fi

# Step 4: Set ownership and permissions for Grafana
log_message "Setting ownership and permissions for Grafana..."
chown -R grafana:grafana /usr/share/grafana /var/lib/grafana /var/log/grafana
chmod -R u+rwX /usr/share/grafana /var/lib/grafana /var/log/grafana

# Step 5: Reload systemd daemon
log_message "Reloading systemd daemon..."
systemctl daemon-reload

# Step 6: Start and enable services
log_message "Starting and enabling InfluxDB service..."
systemctl start influxdb
systemctl enable influxdb

log_message "Starting and enabling Grafana service..."
systemctl start grafana-server
systemctl enable grafana-server

# Step 7: Check service status
log_message "Checking service status..."
echo "=== InfluxDB Status ==="
systemctl status influxdb --no-pager -l

echo ""
echo "=== Grafana Status ==="
systemctl status grafana-server --no-pager -l

# Step 8: Ensure Grafana is running and reset admin password
log_message "Ensuring Grafana is running and resetting admin password..."
# Wait a bit for Grafana to fully start up
sleep 10

# Check if Grafana is running
if systemctl is-active --quiet grafana-server; then
    log_message "Grafana is running. Resetting admin password to P@ssw0rd..."
    
    # Reset admin password using grafana-cli
    if grafana-cli admin reset-admin-password P@ssw0rd; then
        log_message "Admin password successfully reset to P@ssw0rd"
    else
        log_message "WARNING: Failed to reset admin password. You may need to do this manually."
    fi
else
    log_message "ERROR: Grafana service is not running. Cannot reset password."
    log_message "Attempting to start Grafana again..."
    systemctl start grafana-server
    sleep 5
    
    if systemctl is-active --quiet grafana-server; then
        log_message "Grafana started successfully. Resetting admin password..."
        if grafana-cli admin reset-admin-password P@ssw0rd; then
            log_message "Admin password successfully reset to P@ssw0rd"
        else
            log_message "WARNING: Failed to reset admin password. You may need to do this manually."
        fi
    else
        log_message "ERROR: Failed to start Grafana service. Please check logs and start manually."
    fi
fi

# Step 9: Configure firewall
log_message "Configuring firewall for InfluxDB (port 8086) and Grafana (port 3000)..."
firewall-cmd --add-port=8086/tcp --permanent
firewall-cmd --add-port=3000/tcp --permanent
firewall-cmd --reload

log_message "Firewall configured successfully."

# Step 10: Display access information
log_message "Installation completed successfully!"
echo ""
echo "=== Access Information ==="
echo "InfluxDB: http://$(hostname -I | awk '{print $1}'):8086"
echo "Grafana:  http://$(hostname -I | awk '{print $1}'):3000"
echo ""
echo "Grafana credentials:"
echo "Username: admin"
echo "Password: P@ssw0rd"
echo ""
echo "Services are now running and enabled to start on boot."
echo "Check service status with: systemctl status influxdb grafana-server"
