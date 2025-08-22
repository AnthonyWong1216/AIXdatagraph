#!/bin/bash

# Native Installation Script for IBM Power (ppc64le) Servers
# This script installs InfluxDB and Grafana natively on Power architecture

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  AIX Data Graph - Power Native Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo "This script installs InfluxDB and Grafana natively on IBM Power servers"
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

print_header() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to check if services are already installed
check_existing_installation() {
    local influxdb_installed=false
    local grafana_installed=false
    
    if [[ -f "/opt/influxdb/influxd" && -f "/usr/local/bin/influxd" ]]; then
        influxdb_installed=true
        print_status "InfluxDB appears to be already installed"
    fi
    
    if [[ -f "/usr/share/grafana/grafana-server" && -f "/usr/local/bin/grafana-server" ]]; then
        grafana_installed=true
        print_status "Grafana appears to be already installed"
    fi
    
    if [[ "$influxdb_installed" == "true" && "$grafana_installed" == "true" ]]; then
        print_warning "Both InfluxDB and Grafana appear to be already installed"
        read -p "Do you want to reinstall? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Skipping installation. Checking service status..."
            systemctl status influxdb grafana-server 2>/dev/null || print_warning "Services not found, but binaries exist"
            exit 0
        fi
    fi
}

# Function to check network connectivity
check_network_connectivity() {
    print_status "Checking network connectivity..."
    
    # Test basic connectivity
    if ! ping -c 1 -W 5 8.8.8.8 > /dev/null 2>&1; then
        print_error "No internet connectivity detected"
        print_status "Please check your network connection and try again"
        exit 1
    fi
    
    # Test DNS resolution
    if ! nslookup dl.influxdata.com > /dev/null 2>&1; then
        print_warning "DNS resolution issues detected"
        print_status "This may cause download problems"
    fi
    
    print_status "Network connectivity check passed"
}

# Function to check system requirements
check_system_requirements() {
    print_status "Checking system requirements..."
    
    # Check available disk space (need at least 1GB)
    local available_space=$(df /tmp | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 1048576 ]]; then
        print_error "Insufficient disk space. Need at least 1GB free space"
        exit 1
    fi
    
    # Check available memory (need at least 1GB)
    local available_memory=$(free -m | awk 'NR==2 {print $7}')
    if [[ $available_memory -lt 1024 ]]; then
        print_warning "Low memory detected. Installation may be slow"
    fi
    
    print_status "System requirements check passed"
}

# Function to find extracted directory
find_extracted_dir() {
    local pattern=$1
    local current_dir=$(pwd)
    
    # Look for directories matching the pattern
    for dir in */; do
        if [[ -d "$dir" && "$dir" =~ $pattern ]]; then
            echo "$dir"
            return 0
        fi
    done
    
    # If no exact match, look for any directory containing the pattern
    for dir in */; do
        if [[ -d "$dir" && "$dir" =~ influxdb2 ]] && [[ "$pattern" =~ influxdb2 ]]; then
            echo "$dir"
            return 0
        elif [[ -d "$dir" && "$dir" =~ grafana ]] && [[ "$pattern" =~ grafana ]]; then
            echo "$dir"
            return 0
        fi
    done
    
    return 1
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

# Detect architecture
ARCH=$(uname -m)
print_status "Detected architecture: $ARCH"

# Run pre-installation checks
check_existing_installation
check_network_connectivity
check_system_requirements

if [[ "$ARCH" != "ppc64le" ]]; then
    print_warning "This script is optimized for ppc64le architecture, but detected $ARCH"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Step 1: Update system and install dependencies
print_header "Installing system dependencies..."
print_status "Updating system packages..."
dnf update -y

print_status "Installing required packages..."
dnf install -y wget curl tar gzip which jq openssl

# Step 2: Install InfluxDB
print_header "Installing InfluxDB..."
INFLUXDB_VERSION="2.7.1"
INFLUXDB_USER="influxdb"
INFLUXDB_GROUP="influxdb"
INFLUXDB_HOME="/opt/influxdb"
INFLUXDB_DATA="/var/lib/influxdb"
INFLUXDB_CONFIG="/etc/influxdb"
INFLUXDB_LOG="/var/log/influxdb"

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

# Download InfluxDB for Power architecture
print_status "Downloading InfluxDB ${INFLUXDB_VERSION} for Power architecture..."
cd /tmp

# Check if files already exist
if [[ -f "influxdb2-${INFLUXDB_VERSION}-linux-amd64.tar.gz" ]]; then
    print_status "InfluxDB amd64 binary already exists, using existing file"
    INFLUX_DOWNLOADED=true
    INFLUX_ARCH="amd64"
elif [[ -f "influxdb2-${INFLUXDB_VERSION}-linux-ppc64le.tar.gz" ]]; then
    print_status "InfluxDB ppc64le binary already exists, using existing file"
    INFLUX_DOWNLOADED=true
    INFLUX_ARCH="ppc64le"
else
    # Try different sources for Power architecture
    INFLUX_DOWNLOADED=false
    INFLUX_ARCH=""

    # Try official InfluxDB ppc64le binary first
    print_status "Attempting to download ppc64le binary..."
    if command -v wget > /dev/null 2>&1; then
        if wget -q --timeout=30 --tries=3 https://dl.influxdata.com/influxdb/releases/influxdb2-${INFLUXDB_VERSION}-linux-ppc64le.tar.gz; then
            if [[ -f "influxdb2-${INFLUXDB_VERSION}-linux-ppc64le.tar.gz" ]]; then
                INFLUX_DOWNLOADED=true
                INFLUX_ARCH="ppc64le"
                print_status "Successfully downloaded ppc64le binary"
            fi
        fi
    elif command -v curl > /dev/null 2>&1; then
        if curl -L --connect-timeout 30 --max-time 300 -o influxdb2-${INFLUXDB_VERSION}-linux-ppc64le.tar.gz https://dl.influxdata.com/influxdb/releases/influxdb2-${INFLUXDB_VERSION}-linux-ppc64le.tar.gz; then
            if [[ -f "influxdb2-${INFLUXDB_VERSION}-linux-ppc64le.tar.gz" ]]; then
                INFLUX_DOWNLOADED=true
                INFLUX_ARCH="ppc64le"
                print_status "Successfully downloaded ppc64le binary"
            fi
        fi
    fi

    # If ppc64le not available, try amd64 with emulation
    if [[ "$INFLUX_DOWNLOADED" == "false" ]]; then
        print_warning "Power-specific InfluxDB binary not available, trying amd64 with emulation..."
        if command -v wget > /dev/null 2>&1; then
            if wget -q --timeout=30 --tries=3 https://dl.influxdata.com/influxdb/releases/influxdb2-${INFLUXDB_VERSION}-linux-amd64.tar.gz; then
                if [[ -f "influxdb2-${INFLUXDB_VERSION}-linux-amd64.tar.gz" ]]; then
                    INFLUX_DOWNLOADED=true
                    INFLUX_ARCH="amd64"
                    print_status "Successfully downloaded amd64 binary"
                fi
            fi
        elif command -v curl > /dev/null 2>&1; then
            if curl -L --connect-timeout 30 --max-time 300 -o influxdb2-${INFLUXDB_VERSION}-linux-amd64.tar.gz https://dl.influxdata.com/influxdb/releases/influxdb2-${INFLUXDB_VERSION}-linux-amd64.tar.gz; then
                if [[ -f "influxdb2-${INFLUXDB_VERSION}-linux-amd64.tar.gz" ]]; then
                    INFLUX_DOWNLOADED=true
                    INFLUX_ARCH="amd64"
                    print_status "Successfully downloaded amd64 binary"
                fi
            fi
        fi
    fi
fi

if [[ "$INFLUX_DOWNLOADED" == "false" ]]; then
    print_error "Failed to download InfluxDB binary"
    print_status "Please check network connectivity and try again"
    exit 1
fi

# Extract and install InfluxDB
print_status "Extracting and installing InfluxDB ${INFLUX_ARCH} binary..."
if [[ "$INFLUX_ARCH" == "ppc64le" ]]; then
    tar -xzf influxdb2-${INFLUXDB_VERSION}-linux-ppc64le.tar.gz
    cp influxdb2-${INFLUXDB_VERSION}-linux-ppc64le/influxd $INFLUXDB_HOME/
    cp influxdb2-${INFLUXDB_VERSION}-linux-ppc64le/influx /usr/local/bin/
    chmod +x /usr/local/bin/influx
elif [[ "$INFLUX_ARCH" == "amd64" ]]; then
    tar -xzf influxdb2-${INFLUXDB_VERSION}-linux-amd64.tar.gz
    # Find the extracted directory automatically
    influx_dir=$(find_extracted_dir "influxdb2")
    if [[ -n "$influx_dir" ]]; then
        print_status "Found InfluxDB directory: $influx_dir"
        cp "${influx_dir%/}/influxd" $INFLUXDB_HOME/
        # Check if influx CLI exists, if not download it separately
        if [[ -f "${influx_dir%/}/influx" ]]; then
            cp "${influx_dir%/}/influx" /usr/local/bin/
            chmod +x /usr/local/bin/influx
        else
            print_warning "Influx CLI not found in package, downloading separately..."
            cd /tmp
            if command -v wget > /dev/null 2>&1; then
                wget -q --timeout=30 --tries=3 https://dl.influxdata.com/influxdb/releases/influxdb2-client-${INFLUXDB_VERSION}-linux-amd64.tar.gz
            elif command -v curl > /dev/null 2>&1; then
                curl -L --connect-timeout 30 --max-time 300 -o influxdb2-client-${INFLUXDB_VERSION}-linux-amd64.tar.gz https://dl.influxdata.com/influxdb/releases/influxdb2-client-${INFLUXDB_VERSION}-linux-amd64.tar.gz
            fi
            if [[ -f "influxdb2-client-${INFLUXDB_VERSION}-linux-amd64.tar.gz" ]]; then
                tar -xzf influxdb2-client-${INFLUXDB_VERSION}-linux-amd64.tar.gz
                cp influx /usr/local/bin/
                chmod +x /usr/local/bin/influx
            else
                print_warning "Could not download influx CLI, you may need to install it manually"
            fi
        fi
    else
        print_error "Could not find InfluxDB binary directory after extraction"
        print_status "Available directories:"
        ls -la | grep influxdb2 || print_status "No influxdb2 directories found"
        exit 1
    fi
fi

# Make binaries executable
chmod +x $INFLUXDB_HOME/influxd
chmod +x /usr/local/bin/influx

# Create symbolic link for influxd
ln -sf $INFLUXDB_HOME/influxd /usr/local/bin/influxd

# Create systemd service file
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

# Create configuration file
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

# Step 3: Install Grafana
print_header "Installing Grafana..."
GRAFANA_VERSION="10.2.3"
GRAFANA_USER="grafana"
GRAFANA_GROUP="grafana"
GRAFANA_HOME="/usr/share/grafana"
GRAFANA_DATA="/var/lib/grafana"
GRAFANA_CONFIG="/etc/grafana"
GRAFANA_LOG="/var/log/grafana"

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

# Download Grafana for Power architecture
print_status "Downloading Grafana ${GRAFANA_VERSION} for Power architecture..."
cd /tmp

# Check if files already exist
if [[ -f "grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz" ]]; then
    print_status "Grafana amd64 binary already exists, using existing file"
    GRAFANA_DOWNLOADED=true
    GRAFANA_ARCH="amd64"
elif [[ -f "grafana-${GRAFANA_VERSION}.linux-ppc64le.tar.gz" ]]; then
    print_status "Grafana ppc64le binary already exists, using existing file"
    GRAFANA_DOWNLOADED=true
    GRAFANA_ARCH="ppc64le"
else
    # Try different sources for Power architecture
    GRAFANA_DOWNLOADED=false
    GRAFANA_ARCH=""

    # Try official Grafana ppc64le binary first
    print_status "Attempting to download Grafana ppc64le binary..."
    if command -v wget > /dev/null 2>&1; then
        if wget -q --timeout=30 --tries=3 https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}.linux-ppc64le.tar.gz; then
            if [[ -f "grafana-${GRAFANA_VERSION}.linux-ppc64le.tar.gz" ]]; then
                GRAFANA_DOWNLOADED=true
                GRAFANA_ARCH="ppc64le"
                print_status "Successfully downloaded Grafana ppc64le binary"
            fi
        fi
    elif command -v curl > /dev/null 2>&1; then
        if curl -L --connect-timeout 30 --max-time 300 -o grafana-${GRAFANA_VERSION}.linux-ppc64le.tar.gz https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}.linux-ppc64le.tar.gz; then
            if [[ -f "grafana-${GRAFANA_VERSION}.linux-ppc64le.tar.gz" ]]; then
                GRAFANA_DOWNLOADED=true
                GRAFANA_ARCH="ppc64le"
                print_status "Successfully downloaded Grafana ppc64le binary"
            fi
        fi
    fi

    # If ppc64le not available, try amd64 with emulation
    if [[ "$GRAFANA_DOWNLOADED" == "false" ]]; then
        print_warning "Power-specific Grafana binary not available, trying amd64 with emulation..."
        if command -v wget > /dev/null 2>&1; then
            if wget -q --timeout=30 --tries=3 https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz; then
                if [[ -f "grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz" ]]; then
                    GRAFANA_DOWNLOADED=true
                    GRAFANA_ARCH="amd64"
                    print_status "Successfully downloaded Grafana amd64 binary"
                fi
            fi
        elif command -v curl > /dev/null 2>&1; then
            if curl -L --connect-timeout 30 --max-time 300 -o grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz; then
                if [[ -f "grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz" ]]; then
                    GRAFANA_DOWNLOADED=true
                    GRAFANA_ARCH="amd64"
                    print_status "Successfully downloaded Grafana amd64 binary"
                fi
            fi
        fi
    fi
fi

if [[ "$GRAFANA_DOWNLOADED" == "false" ]]; then
    print_error "Failed to download Grafana binary"
    print_status "Please check network connectivity and try again"
    exit 1
fi

# Extract and install Grafana
print_status "Extracting and installing Grafana ${GRAFANA_ARCH} binary..."
if [[ "$GRAFANA_ARCH" == "ppc64le" ]]; then
    tar -xzf grafana-${GRAFANA_VERSION}.linux-ppc64le.tar.gz
    cd grafana-${GRAFANA_VERSION}
elif [[ "$GRAFANA_ARCH" == "amd64" ]]; then
    tar -xzf grafana-${GRAFANA_VERSION}.linux-amd64.tar.gz
    # Find the extracted directory automatically
    grafana_dir=$(find_extracted_dir "grafana")
    if [[ -n "$grafana_dir" ]]; then
        print_status "Found Grafana directory: $grafana_dir"
        cd "${grafana_dir%/}"
    else
        print_error "Could not find Grafana directory after extraction"
        print_status "Available directories:"
        ls -la | grep grafana || print_status "No grafana directories found"
        exit 1
    fi
fi

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

# Step 4: Configure SELinux and firewall
print_header "Configuring system security..."

# Configure SELinux if enabled
if command -v sestatus > /dev/null 2>&1 && sestatus | grep -q "enabled"; then
    print_status "Configuring SELinux..."
    setsebool -P httpd_can_network_connect 1
fi

# Configure firewall
if command -v firewall-cmd > /dev/null 2>&1; then
    print_status "Configuring firewall..."
    firewall-cmd --permanent --add-port=8086/tcp
    firewall-cmd --permanent --add-port=3000/tcp
    firewall-cmd --reload
fi

# Step 5: Start services
print_header "Starting services..."
print_status "Starting InfluxDB..."
systemctl start influxdb

print_status "Starting Grafana..."
systemctl start grafana-server

# Step 6: Wait for services to be ready
print_header "Waiting for services to be ready..."
print_status "Waiting for InfluxDB to start..."
for i in {1..30}; do
    if curl -s http://localhost:8086/ping > /dev/null 2>&1; then
        print_status "InfluxDB is ready!"
        break
    fi
    if [[ $i -eq 30 ]]; then
        print_error "InfluxDB failed to start within 30 seconds"
        exit 1
    fi
    sleep 1
done

print_status "Waiting for Grafana to start..."
for i in {1..30}; do
    if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
        print_status "Grafana is ready!"
        break
    fi
    if [[ $i -eq 30 ]]; then
        print_error "Grafana failed to start within 30 seconds"
        exit 1
    fi
    sleep 1
done

# Step 7: Create InfluxDB initial setup
print_header "Setting up InfluxDB..."
print_status "Creating InfluxDB organization and admin user..."

# Create a temporary script for InfluxDB setup
cat > /tmp/setup_influxdb.sh << 'EOF'
#!/bin/bash
# Setup InfluxDB organization and admin user
influx setup \
    --username admin \
    --password admin123 \
    --org aixdatagraph \
    --bucket logs \
    --retention 30d \
    --force
EOF

chmod +x /tmp/setup_influxdb.sh
/tmp/setup_influxdb.sh

# Step 8: Create InfluxDB token for Grafana
print_status "Creating InfluxDB API token for Grafana..."
INFLUX_TOKEN=$(influx auth create \
    --org aixdatagraph \
    --description "Grafana Integration Token" \
    --read-bucket logs \
    --write-bucket logs \
    --json | jq -r '.token')

if [[ -z "$INFLUX_TOKEN" || "$INFLUX_TOKEN" == "null" ]]; then
    print_error "Failed to create InfluxDB token"
    exit 1
fi

print_status "InfluxDB token created successfully"

# Step 9: Configure Grafana data source
print_header "Configuring Grafana data source..."
print_status "Adding InfluxDB as data source in Grafana..."

# Wait a bit more for Grafana to be fully ready
sleep 5

# Create data source configuration
mkdir -p /etc/grafana/provisioning/datasources
cat > /etc/grafana/provisioning/datasources/influxdb.yaml << EOF
apiVersion: 1

datasources:
  - name: InfluxDB
    type: influxdb
    access: proxy
    url: http://localhost:8086
    secureJsonData:
      token: $INFLUX_TOKEN
    jsonData:
      version: Flux
      organization: aixdatagraph
      defaultBucket: logs
      tlsSkipVerify: true
    editable: true
EOF

# Set proper permissions
chown grafana:grafana /etc/grafana/provisioning/datasources/influxdb.yaml
chmod 644 /etc/grafana/provisioning/datasources/influxdb.yaml

# Restart Grafana to load the new data source
systemctl restart grafana-server

# Step 10: Create sample dashboard
print_header "Creating sample dashboard..."
mkdir -p /etc/grafana/provisioning/dashboards

cat > /etc/grafana/provisioning/dashboards/dashboard.yaml << EOF
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

chown grafana:grafana /etc/grafana/provisioning/dashboards/dashboard.yaml
chmod 644 /etc/grafana/provisioning/dashboards/dashboard.yaml

# Create a sample dashboard for log visualization
cat > /etc/grafana/provisioning/dashboards/logs_dashboard.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "AIX Logs Dashboard",
    "tags": ["aix", "logs"],
    "style": "dark",
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Log Entries Over Time",
        "type": "timeseries",
        "targets": [
          {
            "query": "from(bucket: \"logs\")\n  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)\n  |> filter(fn: (r) => r[\"_measurement\"] == \"logs\")\n  |> count()",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "palette-classic"
            },
            "custom": {
              "axisLabel": "",
              "axisPlacement": "auto",
              "barAlignment": 0,
              "drawStyle": "line",
              "fillOpacity": 10,
              "gradientMode": "none",
              "hideFrom": {
                "legend": false,
                "tooltip": false,
                "vis": false
              },
              "lineInterpolation": "linear",
              "lineWidth": 1,
              "pointSize": 5,
              "scaleDistribution": {
                "type": "linear"
              },
              "showPoints": "never",
              "spanNulls": false,
              "stacking": {
                "group": "A",
                "mode": "none"
              },
              "thresholdsStyle": {
                "mode": "off"
              }
            },
            "mappings": [],
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {
                  "color": "green",
                  "value": null
                }
              ]
            },
            "unit": "short"
          }
        },
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 0,
          "y": 0
        }
      },
      {
        "id": 2,
        "title": "Log Levels Distribution",
        "type": "piechart",
        "targets": [
          {
            "query": "from(bucket: \"logs\")\n  |> range(start: v.timeRangeStart, stop: v.timeRangeStop)\n  |> filter(fn: (r) => r[\"_measurement\"] == \"logs\")\n  |> group(columns: [\"level\"])\n  |> count()",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {
              "mode": "palette-classic"
            },
            "custom": {
              "hideFrom": {
                "legend": false,
                "tooltip": false,
                "vis": false
              }
            },
            "mappings": []
          }
        },
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 12,
          "y": 0
        }
      }
    ],
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "timepicker": {},
    "templating": {
      "list": []
    },
    "annotations": {
      "list": []
    },
    "refresh": "5s",
    "schemaVersion": 27,
    "version": 0,
    "links": []
  }
}
EOF

chown grafana:grafana /etc/grafana/provisioning/dashboards/logs_dashboard.json
chmod 644 /etc/grafana/provisioning/dashboards/logs_dashboard.json

# Step 11: Create log collection script
print_header "Creating log collection utilities..."
cat > /usr/local/bin/send_logs_to_influxdb.sh << 'EOF'
#!/bin/bash

# Script to send logs to InfluxDB
# Usage: send_logs_to_influxdb.sh <log_file> [measurement_name]

set -e

LOG_FILE="${1:-/var/log/messages}"
MEASUREMENT="${2:-logs}"
INFLUX_URL="http://localhost:8086"
ORG="aixdatagraph"
BUCKET="logs"
TOKEN="your-super-secret-auth-token"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "Error: Log file $LOG_FILE not found"
    exit 1
fi

echo "Sending logs from $LOG_FILE to InfluxDB..."

# Read log file and send to InfluxDB
while IFS= read -r line; do
    if [[ -n "$line" ]]; then
        # Extract timestamp and level (basic parsing)
        timestamp=$(date -u +%s%N)
        level="info"
        
        # Simple level detection
        if echo "$line" | grep -qi "error\|err"; then
            level="error"
        elif echo "$line" | grep -qi "warn"; then
            level="warning"
        elif echo "$line" | grep -qi "debug"; then
            level="debug"
        fi
        
        # Send to InfluxDB using curl
        curl -s -X POST "$INFLUX_URL/api/v2/write?org=$ORG&bucket=$BUCKET" \
            -H "Authorization: Token $TOKEN" \
            -H "Content-Type: text/plain; charset=utf-8" \
            -d "$MEASUREMENT,level=$level,source=$(hostname) message=\"$(echo "$line" | sed 's/"/\\"/g')\" $timestamp"
    fi
done < "$LOG_FILE"

echo "Log collection completed."
EOF

chmod +x /usr/local/bin/send_logs_to_influxdb.sh

# Step 12: Create systemd service for log collection
cat > /etc/systemd/system/log-collector.service << EOF
[Unit]
Description=Log Collector for InfluxDB
After=influxdb.service
Wants=influxdb.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/send_logs_to_influxdb.sh /var/log/messages system_logs
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# Create a timer for periodic log collection
cat > /etc/systemd/system/log-collector.timer << EOF
[Unit]
Description=Run log collector every 5 minutes
Requires=log-collector.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable log-collector.timer

# Step 13: Create README
cat > /opt/aixdatagraph/README_POWER.md << EOF
# AIX Data Graph - Power Native Installation

This installation uses native binaries for InfluxDB and Grafana on IBM Power servers.

## Services
- **InfluxDB 2.7.1**: Time series database for log storage
- **Grafana 10.2.3**: Visualization and dashboard platform

## Access Information
- **Grafana**: http://localhost:3000 (admin/admin)
- **InfluxDB**: http://localhost:8086 (admin/admin123)

## Management Commands
- Check service status: \`systemctl status influxdb grafana-server\`
- Start services: \`systemctl start influxdb grafana-server\`
- Stop services: \`systemctl stop influxdb grafana-server\`
- Restart services: \`systemctl restart influxdb grafana-server\`
- View logs: \`journalctl -u influxdb -f\` or \`journalctl -u grafana-server -f\`

## Data Persistence
- InfluxDB data: /var/lib/influxdb
- Grafana data: /var/lib/grafana
- Configurations: /etc/influxdb and /etc/grafana

## Log Collection
- Automatic: Every 5 minutes via systemd timer
- Manual: /usr/local/bin/send_logs_to_influxdb.sh <log_file>

## Architecture Support
This installation is optimized for IBM Power (ppc64le) architecture with fallback to amd64 emulation if needed.
EOF

mkdir -p /opt/aixdatagraph
chmod 644 /opt/aixdatagraph/README_POWER.md

# Clean up
rm -f /tmp/setup_influxdb.sh
rm -rf /tmp/influxdb2-${INFLUXDB_VERSION}-*
rm -rf /tmp/grafana-${GRAFANA_VERSION}

# Function to verify installation
verify_installation() {
    print_header "Verifying installation..."
    
    local all_good=true
    
    # Check InfluxDB
    if [[ -f "/opt/influxdb/influxd" ]]; then
        print_status "✓ InfluxDB binary installed"
    else
        print_error "✗ InfluxDB binary not found"
        all_good=false
    fi
    
    if systemctl is-active influxdb > /dev/null 2>&1; then
        print_status "✓ InfluxDB service running"
    else
        print_error "✗ InfluxDB service not running"
        all_good=false
    fi
    
    # Check Grafana
    if [[ -f "/usr/share/grafana/grafana-server" ]]; then
        print_status "✓ Grafana binary installed"
    else
        print_error "✗ Grafana binary not found"
        all_good=false
    fi
    
    if systemctl is-active grafana-server > /dev/null 2>&1; then
        print_status "✓ Grafana service running"
    else
        print_error "✗ Grafana service not running"
        all_good=false
    fi
    
    # Check web interfaces
    if curl -s http://localhost:8086/ping > /dev/null 2>&1; then
        print_status "✓ InfluxDB web interface accessible"
    else
        print_error "✗ InfluxDB web interface not accessible"
        all_good=false
    fi
    
    if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
        print_status "✓ Grafana web interface accessible"
    else
        print_error "✗ Grafana web interface not accessible"
        all_good=false
    fi
    
    if [[ "$all_good" == "true" ]]; then
        print_status "✓ All components verified successfully"
    else
        print_warning "⚠ Some components may need attention"
    fi
}

# Final status
print_header "Installation Complete!"
echo ""
print_status "Services are now running:"
echo "- InfluxDB: http://localhost:8086"
echo "- Grafana: http://localhost:3000"
echo ""
print_status "Default credentials:"
echo "- Grafana: admin/admin"
echo "- InfluxDB: admin/admin123"
echo ""
print_status "Documentation: /opt/aixdatagraph/README_POWER.md"
echo ""
print_warning "IMPORTANT: Change default passwords after first login!"
echo ""
print_status "Log collection is configured to run every 5 minutes"
print_status "Manual log collection: /usr/local/bin/send_logs_to_influxdb.sh <log_file>"

# Verify installation
verify_installation

echo ""
print_status "Installation summary:"
echo "- Architecture: $ARCH"
echo "- InfluxDB version: $INFLUXDB_VERSION"
echo "- Grafana version: $GRAFANA_VERSION"
echo "- Installation method: Native (Power optimized)"
echo ""
print_status "For troubleshooting, check:"
echo "- Service logs: journalctl -u influxdb -f"
echo "- Service logs: journalctl -u grafana-server -f"
echo "- Configuration: /etc/influxdb/influxdb.conf"
echo "- Configuration: /etc/grafana/grafana.ini"
