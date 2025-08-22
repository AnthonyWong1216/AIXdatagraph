#!/bin/bash

# InfluxDB Installation Script for AIX/Linux
# This script installs InfluxDB for log collection and monitoring

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
INFLUXDB_VERSION="2.7.1"
INFLUXDB_USER="influxdb"
INFLUXDB_GROUP="influxdb"
INFLUXDB_HOME="/opt/influxdb"
INFLUXDB_DATA="/var/lib/influxdb"
INFLUXDB_CONFIG="/etc/influxdb"
INFLUXDB_LOG="/var/log/influxdb"

echo -e "${GREEN}=== InfluxDB Installation Script ===${NC}"
echo "Version: ${INFLUXDB_VERSION}"
echo ""

# Function to print status messages
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# Detect OS
if [[ -f /etc/redhat-release ]]; then
    OS="rhel"
    RHEL_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
    print_status "Detected Red Hat Enterprise Linux $RHEL_VERSION"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    print_status "Detected generic Linux system"
elif [[ "$OSTYPE" == "aix"* ]]; then
    OS="aix"
    print_status "Detected AIX system"
else
    print_error "Unsupported operating system: $OSTYPE"
    exit 1
fi

print_status "Detected OS: $OS"

# Create influxdb user and group
print_status "Creating influxdb user and group..."
if ! getent group $INFLUXDB_GROUP > /dev/null 2>&1; then
    groupadd $INFLUXDB_GROUP
fi

if ! getent passwd $INFLUXDB_USER > /dev/null 2>&1; then
    useradd -r -g $INFLUXDB_GROUP -d $INFLUXDB_HOME -s /bin/false $INFLUXDB_USER
fi

# Create directories
print_status "Creating directories..."
mkdir -p $INFLUXDB_HOME
mkdir -p $INFLUXDB_DATA
mkdir -p $INFLUXDB_CONFIG
mkdir -p $INFLUXDB_LOG

# Set ownership
chown -R $INFLUXDB_USER:$INFLUXDB_GROUP $INFLUXDB_HOME
chown -R $INFLUXDB_USER:$INFLUXDB_GROUP $INFLUXDB_DATA
chown -R $INFLUXDB_USER:$INFLUXDB_GROUP $INFLUXDB_CONFIG
chown -R $INFLUXDB_USER:$INFLUXDB_GROUP $INFLUXDB_LOG

# Download and install InfluxDB
print_status "Downloading InfluxDB ${INFLUXDB_VERSION}..."
cd /tmp

if [[ "$OS" == "rhel" || "$OS" == "linux" ]]; then
    # For RHEL/Linux systems
    print_status "Installing dependencies..."
    dnf install -y wget curl tar gzip
    
    if command -v wget > /dev/null 2>&1; then
        wget -q https://dl.influxdata.com/influxdb/releases/influxdb2-${INFLUXDB_VERSION}-linux-amd64.tar.gz
    elif command -v curl > /dev/null 2>&1; then
        curl -L -o influxdb2-${INFLUXDB_VERSION}-linux-amd64.tar.gz https://dl.influxdata.com/influxdb/releases/influxdb2-${INFLUXDB_VERSION}-linux-amd64.tar.gz
    else
        print_error "Neither wget nor curl is available"
        exit 1
    fi
    
    tar -xzf influxdb2-${INFLUXDB_VERSION}-linux-amd64.tar.gz
    cp influxdb2-${INFLUXDB_VERSION}-linux-amd64/influxd $INFLUXDB_HOME/
    cp influxdb2-${INFLUXDB_VERSION}-linux-amd64/influx $INFLUXDB_HOME/
    
elif [[ "$OS" == "aix" ]]; then
    # For AIX systems - you might need to download manually or use a different approach
    print_warning "AIX installation requires manual download of InfluxDB binary"
    print_status "Please download InfluxDB for AIX from: https://portal.influxdata.com/downloads/"
    print_status "Extract and copy the binaries to $INFLUXDB_HOME/"
    print_status "Then run this script again with --skip-download flag"
    
    if [[ "$1" != "--skip-download" ]]; then
        exit 1
    fi
fi

# Make binaries executable
chmod +x $INFLUXDB_HOME/influxd
chmod +x $INFLUXDB_HOME/influx

# Create symbolic links
ln -sf $INFLUXDB_HOME/influxd /usr/local/bin/influxd
ln -sf $INFLUXDB_HOME/influx /usr/local/bin/influx

# Create systemd service file (for RHEL/Linux)
if [[ "$OS" == "rhel" || "$OS" == "linux" ]]; then
    print_status "Creating systemd service file..."
    cat > /etc/systemd/system/influxdb.service << EOF
[Unit]
Description=InfluxDB is an open-source, distributed, time series database
Documentation=https://docs.influxdata.com/influxdb/
After=network-online.target
Wants=network-online.target

[Service]
User=$INFLUXDB_USER
Group=$INFLUXDB_GROUP
Type=simple
ExecStart=$INFLUXDB_HOME/influxd --config $INFLUXDB_CONFIG/influxdb.conf
KillMode=mixed
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable influxdb.service
fi

# Create basic configuration file
print_status "Creating InfluxDB configuration..."
cat > $INFLUXDB_CONFIG/influxdb.conf << EOF
# InfluxDB Configuration File

[meta]
  dir = "$INFLUXDB_DATA/meta"

[data]
  dir = "$INFLUXDB_DATA/data"
  wal-dir = "$INFLUXDB_DATA/wal"
  series-id-set-cache-size = 100

[coordinator]
  write-timeout = "10s"
  query-timeout = "0s"

[retention]
  enabled = true
  check-interval = "30m"

[shard-precreation]
  enabled = true
  check-interval = "10m"
  advance-period = "30m"

[admin]
  enabled = true
  bind-address = ":8083"
  https-enabled = false

[http]
  enabled = true
  bind-address = ":8086"
  auth-enabled = false
  log-enabled = true
  write-tracing = false
  pprof-enabled = false
  https-enabled = false
  https-certificate = "/etc/ssl/influxdb.pem"

[logging]
  level = "info"
  file = "$INFLUXDB_LOG/influxdb.log"

[subscriber]
  enabled = true
  http-timeout = "30s"

[udp]
  enabled = false

[continuous_queries]
  enabled = true
  log-enabled = true
  run-interval = "1s"
EOF

# Set proper permissions
chown $INFLUXDB_USER:$INFLUXDB_GROUP $INFLUXDB_CONFIG/influxdb.conf
chmod 644 $INFLUXDB_CONFIG/influxdb.conf

# Create log rotation configuration
if [[ "$OS" == "rhel" || "$OS" == "linux" ]]; then
    print_status "Setting up log rotation..."
    cat > /etc/logrotate.d/influxdb << EOF
$INFLUXDB_LOG/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 $INFLUXDB_USER $INFLUXDB_GROUP
    postrotate
        systemctl reload influxdb > /dev/null 2>&1 || true
    endscript
}
EOF
fi

# Clean up
rm -rf /tmp/influxdb2-${INFLUXDB_VERSION}-linux-amd64*
rm -f /tmp/influxdb2-${INFLUXDB_VERSION}-linux-amd64.tar.gz

print_status "InfluxDB installation completed successfully!"
echo ""
print_status "Next steps:"
echo "1. Start InfluxDB: systemctl start influxdb (RHEL/Linux) or $INFLUXDB_HOME/influxd --config $INFLUXDB_CONFIG/influxdb.conf"
echo "2. Access InfluxDB at: http://localhost:8086"
echo "3. Create initial admin user: influx setup"
echo "4. Configure log collection to send data to InfluxDB"
echo ""
print_status "Configuration files:"
echo "- Config: $INFLUXDB_CONFIG/influxdb.conf"
echo "- Data: $INFLUXDB_DATA"
echo "- Logs: $INFLUXDB_LOG"
