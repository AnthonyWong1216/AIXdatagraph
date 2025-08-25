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
    
    # Update ExecStart line and add WorkingDirectory
    sed -i 's|^ExecStart=.*|ExecStart=/usr/sbin/grafana-server --config=/etc/grafana/grafana.ini --homepath=/usr/share/grafana|' /etc/systemd/system/grafana-server.service
    
    # Add WorkingDirectory if it doesn't exist
    if ! grep -q "^WorkingDirectory=" /etc/systemd/system/grafana-server.service; then
        # Add WorkingDirectory after [Service] section
        sed -i '/^\[Service\]/a WorkingDirectory=/usr/share/grafana' /etc/systemd/system/grafana-server.service
    else
        # Update existing WorkingDirectory
        sed -i 's|^WorkingDirectory=.*|WorkingDirectory=/usr/share/grafana|' /etc/systemd/system/grafana-server.service
    fi
    
    log_message "Grafana service file updated successfully."
else
    log_message "WARNING: Grafana service file not found at /etc/systemd/system/grafana-server.service"
fi

# Step 4: Ensure Grafana configuration exists and set ownership/permissions
log_message "Ensuring Grafana configuration and setting ownership/permissions..."

# Create necessary directories if they don't exist
mkdir -p /etc/grafana
mkdir -p /usr/share/grafana
mkdir -p /var/lib/grafana
mkdir -p /var/log/grafana

# Create/overwrite grafana.ini configuration
log_message "Creating/overwriting grafana.ini configuration..."
cat > /etc/grafana/grafana.ini << 'EOF'
[paths]
data = /var/lib/grafana
logs = /var/log/grafana
plugins = /var/lib/grafana/plugins
provisioning = /etc/grafana/provisioning

[server]
http_port = 3000
domain = localhost
root_url = %(protocol)s://%(domain)s:%(http_port)s/

[database]
type = sqlite3
path = /var/lib/grafana/grafana.db

[security]
admin_user = admin
admin_password = P@ssw0rd

[users]
allow_sign_up = false

[auth.anonymous]
enabled = false
EOF

# Set ownership and permissions
log_message "Setting ownership and permissions for Grafana..."
chown -R grafana:grafana /usr/share/grafana /var/lib/grafana /var/log/grafana /etc/grafana
chmod -R u+rwX /usr/share/grafana /var/lib/grafana /var/log/grafana /etc/grafana

# Step 5: Create InfluxDB database and configure Grafana datasource
log_message "Creating InfluxDB database 'NewDB' and configuring Grafana datasource..."

# Wait for InfluxDB to be ready
sleep 5

# Create InfluxDB database
log_message "Creating InfluxDB database 'NewDB'..."
if command -v influx &> /dev/null; then
    influx -execute "CREATE DATABASE NewDB" || log_message "WARNING: Failed to create database, it may already exist"
else
    log_message "WARNING: influx command not found, database creation skipped"
fi

# Create Grafana datasource provisioning directory
mkdir -p /etc/grafana/provisioning/datasources

# Create InfluxDB datasource configuration
log_message "Creating Grafana datasource configuration for InfluxDB..."
cat > /etc/grafana/provisioning/datasources/influxdb.yaml << 'EOF'
apiVersion: 1

datasources:
  - name: InfluxDB
    type: influxdb
    access: proxy
    url: http://localhost:8086
    database: NewDB
    isDefault: true
    editable: true
    jsonData:
      version: InfluxQL
      httpMethod: GET
      timeInterval: 10s
    secureJsonData:
      password: ""
EOF

# Restart Grafana to apply datasource configuration
log_message "Restarting Grafana to apply datasource configuration..."
systemctl restart grafana-server
sleep 5

# Step 6: Reload systemd daemon
log_message "Reloading systemd daemon..."
systemctl daemon-reload

# Step 7: Start and enable services
log_message "Starting and enabling InfluxDB service..."
systemctl start influxdb
systemctl enable influxdb

log_message "Starting and enabling Grafana service..."
systemctl start grafana-server
systemctl enable grafana-server

# Step 8: Check service status
log_message "Checking service status..."
echo "=== InfluxDB Status ==="
systemctl status influxdb --no-pager -l

echo ""
echo "=== Grafana Status ==="
systemctl status grafana-server --no-pager -l

# Step 9: Ensure Grafana is running properly
log_message "Ensuring Grafana is running properly..."
# Wait a bit for Grafana to fully start up
sleep 10

# Check if Grafana is running
if systemctl is-active --quiet grafana-server; then
    log_message "SUCCESS: Grafana is running with admin password P@ssw0rd"
else
    log_message "ERROR: Grafana service is not running."
    log_message "Attempting to start Grafana again..."
    systemctl start grafana-server
    sleep 5
    
    if systemctl is-active --quiet grafana-server; then
        log_message "SUCCESS: Grafana started successfully with admin password P@ssw0rd"
    else
        log_message "ERROR: Failed to start Grafana service. Please check logs and start manually."
        log_message "Troubleshooting steps:"
        log_message "1. Check Grafana logs: journalctl -u grafana-server -f"
        log_message "2. Verify configuration: ls -la /etc/grafana/"
        log_message "3. Check permissions: ls -la /usr/share/grafana /var/lib/grafana /var/log/grafana"
        log_message "4. Try manual start: sudo -u grafana /usr/sbin/grafana-server --config=/etc/grafana/grafana.ini --homepath=/usr/share/grafana"
    fi
fi

# Step 10: Configure firewall
log_message "Configuring firewall for InfluxDB (port 8086) and Grafana (port 3000)..."
firewall-cmd --add-port=8086/tcp --permanent
firewall-cmd --add-port=3000/tcp --permanent
firewall-cmd --reload

log_message "Firewall configured successfully."

# Step 11: Verify InfluxDB database and connection
log_message "Verifying InfluxDB database and connection..."
if command -v influx &> /dev/null; then
    if influx -execute "SHOW DATABASES" | grep -q "NewDB"; then
        log_message "SUCCESS: InfluxDB database 'NewDB' is ready"
    else
        log_message "WARNING: InfluxDB database 'NewDB' not found, attempting to create..."
        influx -execute "CREATE DATABASE NewDB" && log_message "Database 'NewDB' created successfully"
    fi
    
    # Test InfluxDB connection
    log_message "Testing InfluxDB connection..."
    if curl -s http://localhost:8086/ping > /dev/null; then
        log_message "SUCCESS: InfluxDB is responding on port 8086"
    else
        log_message "ERROR: InfluxDB is not responding on port 8086"
    fi
else
    log_message "WARNING: influx command not available for verification"
fi

# Step 12: Display access information
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
echo ""
echo "=== Troubleshooting InfluxDB Connection ==="
echo "If you see 'Error reading InfluxDB' in Grafana:"
echo "1. Verify InfluxDB is running: systemctl status influxdb"
echo "2. Test InfluxDB connection: curl http://localhost:8086/ping"
echo "3. Check InfluxDB logs: journalctl -u influxdb -f"
echo "4. Verify database exists: influx -execute 'SHOW DATABASES'"
echo "5. Restart Grafana: systemctl restart grafana-server"
echo "6. Check Grafana logs: journalctl -u grafana-server -f"
