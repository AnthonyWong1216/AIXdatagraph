#!/bin/bash

# Grafana Installation Script for Red Hat Enterprise Linux 9
# This script installs Grafana for log visualization and monitoring

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
GRAFANA_VERSION="10.2.3"
GRAFANA_USER="grafana"
GRAFANA_GROUP="grafana"
GRAFANA_HOME="/usr/share/grafana"
GRAFANA_DATA="/var/lib/grafana"
GRAFANA_CONFIG="/etc/grafana"
GRAFANA_LOG="/var/log/grafana"

echo -e "${GREEN}=== Grafana Installation Script for RHEL 9 ===${NC}"
echo "Version: ${GRAFANA_VERSION}"
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

# Check if this is RHEL 9
if [[ ! -f /etc/redhat-release ]]; then
    print_error "This script is designed for Red Hat Enterprise Linux"
    exit 1
fi

RHEL_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
if [[ "$RHEL_VERSION" != "9"* ]]; then
    print_warning "This script is optimized for RHEL 9, but detected RHEL $RHEL_VERSION"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

print_status "Detected RHEL $RHEL_VERSION"

# Update system packages
print_status "Updating system packages..."
dnf update -y

# Install dependencies
print_status "Installing dependencies..."
dnf install -y wget curl tar gzip which

# Create grafana user and group
print_status "Creating grafana user and group..."
if ! getent group $GRAFANA_GROUP > /dev/null 2>&1; then
    groupadd $GRAFANA_GROUP
fi

if ! getent passwd $GRAFANA_USER > /dev/null 2>&1; then
    useradd -r -g $GRAFANA_GROUP -d $GRAFANA_HOME -s /bin/false $GRAFANA_USER
fi

# Create directories
print_status "Creating directories..."
mkdir -p $GRAFANA_HOME
mkdir -p $GRAFANA_DATA
mkdir -p $GRAFANA_CONFIG
mkdir -p $GRAFANA_LOG
mkdir -p /usr/share/grafana/public
mkdir -p /usr/share/grafana/conf

# Set ownership
chown -R $GRAFANA_USER:$GRAFANA_GROUP $GRAFANA_HOME
chown -R $GRAFANA_USER:$GRAFANA_GROUP $GRAFANA_DATA
chown -R $GRAFANA_USER:$GRAFANA_GROUP $GRAFANA_CONFIG
chown -R $GRAFANA_USER:$GRAFANA_GROUP $GRAFANA_LOG

# Download and install Grafana
print_status "Downloading Grafana ${GRAFANA_VERSION}..."
cd /tmp

if command -v wget > /dev/null 2>&1; then
    wget -q https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz
elif command -v curl > /dev/null 2>&1; then
    curl -L -o grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz
else
    print_error "Neither wget nor curl is available"
    exit 1
fi

# Extract Grafana
tar -xzf grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz
cd grafana-${GRAFANA_VERSION}

# Copy files to installation directory
print_status "Installing Grafana files..."
cp -r bin $GRAFANA_HOME/
cp -r conf $GRAFANA_HOME/
cp -r public $GRAFANA_HOME/
cp -r tools $GRAFANA_HOME/
cp -r vendor $GRAFANA_HOME/
cp grafana-server $GRAFANA_HOME/
cp grafana-cli $GRAFANA_HOME/

# Make binaries executable
chmod +x $GRAFANA_HOME/grafana-server
chmod +x $GRAFANA_HOME/grafana-cli

# Create symbolic links
ln -sf $GRAFANA_HOME/grafana-server /usr/local/bin/grafana-server
ln -sf $GRAFANA_HOME/grafana-cli /usr/local/bin/grafana-cli

# Create systemd service file
print_status "Creating systemd service file..."
cat > /etc/systemd/system/grafana-server.service << EOF
[Unit]
Description=Grafana instance
Documentation=http://docs.grafana.org
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=$GRAFANA_USER
Group=$GRAFANA_GROUP
ExecStart=$GRAFANA_HOME/grafana-server --config=$GRAFANA_CONFIG/grafana.ini --homepath=$GRAFANA_HOME
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable grafana-server.service

# Create configuration file
print_status "Creating Grafana configuration..."
cat > $GRAFANA_CONFIG/grafana.ini << EOF
# Grafana Configuration File

[paths]
data = $GRAFANA_DATA
logs = $GRAFANA_LOG
plugins = $GRAFANA_DATA/plugins
provisioning = $GRAFANA_CONFIG/provisioning

[server]
protocol = http
http_addr = 0.0.0.0
http_port = 3000
domain = localhost
root_url = %(protocol)s://%(domain)s:%(http_port)s/
serve_from_sub_path = false

[database]
type = sqlite3
path = $GRAFANA_DATA/grafana.db

[security]
admin_user = admin
admin_password = admin
secret_key = $(openssl rand -hex 16)

[users]
allow_sign_up = false
allow_org_create = false
auto_assign_org = true
auto_assign_org_role = Viewer

[auth.anonymous]
enabled = false

[log]
mode = file file
level = info
format = text

[log.file]
log_rotate = true
max_lines = 1000000
max_size_shift = 28
daily_rotate = true
rotate = true

[metrics]
enabled = true
interval_seconds = 10

[snapshots]
external_enabled = true
external_snapshot_url = https://snapshots-origin.raintank.io
external_snapshot_name = Publish to snapshot.raintank.io

[alerting]
enabled = true
execute_alerts = true

[unified_alerting]
enabled = true

[explore]
enabled = true

[panels]
enable_alpha = false

[plugins]
enable_alpha = false
app_tls_skip_verify_insecure = false

[rendering]
server_url =
callback_url =
concurrent_render_request_limit = 30

[analytics]
reporting_enabled = true
check_for_updates = true
google_analytics_ua_id =

[security]
disable_initial_admin_creation = false
cookie_secure = false
cookie_samesite = lax
allow_embedding = false
strict_transport_security = false
strict_transport_security_max_age_seconds = 31536000
strict_transport_security_subdomains = false
strict_transport_security_preload = false
x_content_type_options = true
x_xss_protection = true
EOF

# Set proper permissions
chown $GRAFANA_USER:$GRAFANA_GROUP $GRAFANA_CONFIG/grafana.ini
chmod 644 $GRAFANA_CONFIG/grafana.ini

# Create log rotation configuration
print_status "Setting up log rotation..."
cat > /etc/logrotate.d/grafana << EOF
$GRAFANA_LOG/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 $GRAFANA_USER $GRAFANA_GROUP
    postrotate
        systemctl reload grafana-server > /dev/null 2>&1 || true
    endscript
}
EOF

# Configure SELinux if enabled
if command -v sestatus > /dev/null 2>&1 && sestatus | grep -q "enabled"; then
    print_status "Configuring SELinux..."
    setsebool -P httpd_can_network_connect 1
    
    # Create SELinux policy for Grafana
    cat > /tmp/grafana.te << EOF
module grafana 1.0;

require {
    type unconfined_t;
    type http_port_t;
    type httpd_t;
    class tcp_socket name_connect;
}

# Allow Grafana to connect to HTTP ports
allow unconfined_t http_port_t:tcp_socket name_connect;
EOF
    
    if command -v checkmodule > /dev/null 2>&1; then
        checkmodule -M -m -o /tmp/grafana.mod /tmp/grafana.te
        semodule_package -o /tmp/grafana.pp -m /tmp/grafana.mod
        semodule -i /tmp/grafana.pp
        rm -f /tmp/grafana.te /tmp/grafana.mod /tmp/grafana.pp
    fi
fi

# Configure firewall
if command -v firewall-cmd > /dev/null 2>&1; then
    print_status "Configuring firewall..."
    firewall-cmd --permanent --add-port=3000/tcp
    firewall-cmd --reload
fi

# Clean up
cd /
rm -rf /tmp/grafana-${GRAFANA_VERSION}
rm -f /tmp/grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz

print_status "Grafana installation completed successfully!"
echo ""
print_status "Next steps:"
echo "1. Start Grafana: systemctl start grafana-server"
echo "2. Access Grafana at: http://localhost:3000"
echo "3. Default credentials: admin/admin"
echo "4. Configure InfluxDB as a data source in Grafana"
echo "5. Import dashboards for log visualization"
echo ""
print_status "Configuration files:"
echo "- Config: $GRAFANA_CONFIG/grafana.ini"
echo "- Data: $GRAFANA_DATA"
echo "- Logs: $GRAFANA_LOG"
echo ""
print_status "Useful commands:"
echo "- Check status: systemctl status grafana-server"
echo "- View logs: journalctl -u grafana-server -f"
echo "- Restart service: systemctl restart grafana-server"
