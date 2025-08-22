#!/bin/bash

# AIX Data Graph Installation Script for Red Hat Linux 9
# This script performs a complete installation of the AIX log collection and monitoring system

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
   exit 1
fi

# Check OS version
if ! grep -q "Red Hat Enterprise Linux release 9" /etc/redhat-release 2>/dev/null; then
    print_warning "This script is designed for Red Hat Linux 9. Other versions may work but are not tested."
fi

print_header "AIX Data Graph - Complete Installation"
print_status "Starting installation process..."

# Update system packages
print_header "System Package Update"
print_status "Updating system packages..."
sudo dnf update -y

# Install required packages
print_header "Installing Required Packages"
print_status "Installing system packages..."
sudo dnf install -y python3 python3-pip python3-devel gcc gcc-c++ \
    openssl-devel libffi-devel wget curl git jq unzip \
    python3-wheel python3-numpy python3-pandas \
    make automake patch zlib-devel bzip2-devel readline-devel sqlite-devel \
    xz-devel libuuid-devel gdbm-devel libnsl2-devel

# Upgrade pip to latest version
print_status "Upgrading pip..."
python3 -m pip install --user --upgrade pip setuptools wheel

# Install Python dependencies
print_status "Installing Python packages..."
python3 -m pip install --user pandas numpy bcrypt --no-cache-dir

# Install remaining requirements
print_status "Installing remaining Python packages..."
python3 -m pip install --user -r requirements.txt --no-cache-dir

# Install Docker/Podman
print_header "Installing Container Runtime"
if command -v docker &> /dev/null; then
    print_status "Docker/Podman is already installed"
else
    print_status "Installing Podman and Docker compatibility layer..."
    sudo dnf install -y podman podman-docker container-tools
    
    # Enable podman.socket for rootless containers
    systemctl --user enable podman.socket
    systemctl --user start podman.socket
    
    # Create Docker compatibility symlink
    sudo ln -s /usr/bin/podman /usr/bin/docker 2>/dev/null || true
    
    print_status "Container runtime installed successfully"
    print_warning "You may need to log out and back in for group changes to take effect."
fi

# Install Docker Compose functionality
if ! command -v docker-compose &> /dev/null; then
    print_status "Installing Docker Compose support..."
    sudo dnf install -y docker-compose-plugin || {
        print_warning "docker-compose-plugin not found, installing podman-compose..."
        sudo dnf install -y podman-compose
    }
fi

# Create nodocker file to suppress emulation message
sudo mkdir -p /etc/containers
echo "" | sudo tee /etc/containers/nodocker >/dev/null

# Create project directories with proper permissions
print_header "Creating Project Structure"
print_status "Creating project directories..."

# Define project directories
PROJECT_DIRS=(
    "collector"
    "grafana"
    "scripts"
    "systemd"
    "docker"
    "config"
    "docs"
    "logs"
)

# Create directories with proper permissions
for dir in "${PROJECT_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        sudo mkdir -p "$dir"
        sudo chown $USER:$USER "$dir"
        print_status "Created directory: $dir"
    else
        print_status "Directory already exists: $dir"
    fi
done

# Setup SSH keys
print_header "SSH Key Setup"
print_status "Setting up SSH keys..."
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "aix-log-collector"
    print_status "SSH key generated at ~/.ssh/id_rsa"
else
    print_status "SSH key already exists"
fi

# Create system users
print_header "Creating System Users"
print_status "Creating system users for services..."

# Create aix-collector user
if ! id "aix-collector" &>/dev/null; then
    sudo useradd -r -s /bin/false -d /opt/aixdatagraph aix-collector
    print_status "Created aix-collector user"
else
    print_status "aix-collector user already exists"
fi

# Create grafana user
if ! id "grafana" &>/dev/null; then
    sudo useradd -r -s /bin/false -d /var/lib/grafana grafana
    print_status "Created grafana user"
else
    print_status "grafana user already exists"
fi

# Setup directories and permissions
print_header "Setting Up Directories and Permissions"
print_status "Setting up directories and permissions..."

# Create log directories
sudo mkdir -p /var/log/aix-log-collector
sudo mkdir -p /var/log/grafana

# Create application directory
sudo mkdir -p /opt/aixdatagraph
sudo cp -r * /opt/aixdatagraph/
sudo chown -R aix-collector:aix-collector /opt/aixdatagraph
sudo chown -R grafana:grafana /var/log/grafana
sudo chown -R aix-collector:aix-collector /var/log/aix-log-collector

# Set proper permissions
sudo chmod 755 /opt/aixdatagraph
sudo chmod 644 /opt/aixdatagraph/config/*.yaml
sudo chmod 755 /opt/aixdatagraph/scripts/*.py
sudo chmod 755 /opt/aixdatagraph/collector/*.py

# Setup systemd services
print_header "Setting Up Systemd Services"
print_status "Setting up systemd services..."

# Copy service files
sudo cp systemd/aix-log-collector.service /etc/systemd/system/
sudo cp systemd/grafana-server.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable services
sudo systemctl enable aix-log-collector
sudo systemctl enable grafana-server

# Setup Grafana and InfluxDB
print_header "Setting Up Grafana and InfluxDB"
print_status "Setting up Grafana and InfluxDB with Docker..."

# Start Docker services
cd docker
        if [ -f "docker-compose.yml" ]; then
            print_status "Starting Grafana and InfluxDB..."
            docker compose up -d
            print_status "Waiting for services to be ready..."
            sleep 30
            if docker compose ps | grep -q "Up"; then
                print_status "Docker services started successfully"
            else
                print_warning "Some Docker services may not be running properly"
            fi
        else
            print_warning "Docker Compose file not found, Grafana will need manual setup"
fi
cd ..

# Setup InfluxDB
print_header "Setting Up InfluxDB"
print_status "Setting up InfluxDB database..."

# Wait for InfluxDB to be ready
print_status "Waiting for InfluxDB to be ready..."
sleep 10

# Create InfluxDB organization and bucket (if not already created by Docker)
if command -v curl &> /dev/null; then
    print_status "Setting up InfluxDB organization and bucket..."
    
    # Create organization
    curl -X POST "http://localhost:8086/api/v2/orgs" \
        -H "Authorization: Token aix-token-1234567890abcdef" \
        -H "Content-Type: application/json" \
        -d '{"name":"aix-monitoring"}' 2>/dev/null || true
    
    # Get organization ID
    ORG_ID=$(curl -s "http://localhost:8086/api/v2/orgs" \
        -H "Authorization: Token aix-token-1234567890abcdef" \
        -H "Content-Type: application/json" | jq -r '.orgs[] | select(.name=="aix-monitoring") | .id')
    
    if [ "$ORG_ID" != "null" ] && [ -n "$ORG_ID" ]; then
        # Create bucket
        curl -X POST "http://localhost:8086/api/v2/buckets" \
            -H "Authorization: Token aix-token-1234567890abcdef" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"aix-logs\",\"orgID\":\"$ORG_ID\",\"retentionRules\":[{\"type\":\"expire\",\"everySeconds\":2592000}]}" 2>/dev/null || true
        
        print_status "InfluxDB setup completed"
    else
        print_warning "Could not get InfluxDB organization ID"
    fi
else
    print_warning "curl not available, InfluxDB setup skipped"
fi

# Update configuration file
print_header "Updating Configuration"
print_status "Updating configuration with InfluxDB token..."

# Update config file with the token
if [ -f "config/config.yaml" ]; then
    # Backup original config
    cp config/config.yaml config/config.yaml.backup
    
    # Update InfluxDB token
    sed -i 's/your-influxdb-token/aix-token-1234567890abcdef/g' config/config.yaml
    
    print_status "Configuration updated with InfluxDB token"
else
    print_warning "Configuration file not found, please update manually"
fi

# Test SSH connection
print_header "Testing SSH Setup"
print_status "Testing SSH key setup..."

# Display public key
if [ -f ~/.ssh/id_rsa.pub ]; then
    print_status "Your SSH public key:"
    echo "=========================================="
    cat ~/.ssh/id_rsa.pub
    echo "=========================================="
    print_status "Copy this key to your AIX servers' ~/.ssh/authorized_keys file"
else
    print_error "SSH public key not found"
fi

# Create startup script
print_header "Creating Startup Scripts"
print_status "Creating startup and management scripts..."

cat > start_services.sh << 'EOF'
#!/bin/bash
# AIX Data Graph Service Startup Script

echo "Starting AIX Data Graph services..."

# Start Docker services
cd docker
if command -v docker-compose &> /dev/null; then
    docker-compose up -d
else
    docker compose up -d
        docker compose up -d
# Stop systemd services
sudo systemctl stop aix-log-collector
        docker compose ps
echo ""
echo "Service URLs:"
echo "- Grafana: http://localhost:3000"
echo "- InfluxDB: http://localhost:8086"
EOF
chmod +x status.sh

echo "Next Steps:"
echo "==========="
echo ""
echo "1. Copy your SSH public key to AIX servers:"
cat > start_services.sh << 'EOF'
#!/bin/bash
# AIX Data Graph Service Startup Script

echo ""

# Start Docker services
cd docker
docker compose up -d
cd ..

# Start systemd services
sudo systemctl start aix-log-collector
sudo systemctl start grafana-server

echo "3. Start the services:"
echo "   ./start_services.sh"
EOF

chmod +x start_services.sh

# Create stop script
cat > stop_services.sh << 'EOF'
#!/bin/bash
# AIX Data Graph Service Stop Script

echo ""

# Stop systemd services
sudo systemctl stop aix-log-collector
sudo systemctl stop grafana-server

# Stop Docker services
cd docker
docker compose down
cd ..

echo "4. Test SSH connections to AIX servers:"
EOF

chmod +x stop_services.sh

# Create status script
cat > status.sh << 'EOF'
#!/bin/bash
# AIX Data Graph Service Status Script

echo "   python3 scripts/ssh_setup.py --servers your-aix-server1,your-aix-server2 --test-only"
echo ""

echo "5. Access Grafana at: http://localhost:3000"
echo "   Username: admin"
echo "   Password: admin"
echo ""
echo "6. Run the log collector:"

echo "   python3 collector/aix_log_collector.py --once"
echo ""
echo "7. Check service status:"
echo "   ./status.sh"
echo ""
  
echo "8. View logs:"
echo "   sudo journalctl -u aix-log-collector -f"
echo "   sudo journalctl -u grafana-server -f"
echo ""
EOF

chmod +x status.sh

print_status "Installation completed successfully!"
print_status "For more information, see README.md and docs/ directory"
