#!/bin/bash

# AIX Data Graph Setup Script for Red Hat Linux 9
# This script sets up the complete environment for collecting AIX logs and displaying them in Grafana

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
   exit 1
fi

# Check OS version
if ! grep -q "Red Hat Enterprise Linux release 9" /etc/redhat-release 2>/dev/null; then
    print_warning "This script is designed for Red Hat Linux 9. Other versions may work but are not tested."
fi

print_status "Starting AIX Data Graph setup..."

# Update system packages
print_status "Updating system packages..."
sudo dnf update -y

# Install required packages
print_status "Installing required packages..."
sudo dnf install -y python3 python3-pip python3-devel gcc openssl-devel libffi-devel
sudo dnf install -y wget curl git jq

# Install Docker (optional but recommended)
if command -v docker &> /dev/null; then
    print_status "Docker is already installed"
else
    print_status "Installing Docker..."
    sudo dnf install -y docker
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker $USER
    print_warning "Docker installed. You may need to log out and back in for group changes to take effect."
fi

# Create project directories
print_status "Creating project directories..."
mkdir -p collector grafana scripts systemd docker config docs

# Install Python dependencies
print_status "Installing Python dependencies..."
pip3 install --user -r requirements.txt

# Setup SSH keys
print_status "Setting up SSH keys..."
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -C "aix-log-collector"
    print_status "SSH key generated at ~/.ssh/id_rsa"
else
    print_status "SSH key already exists"
fi

# Setup systemd services
print_status "Setting up systemd services..."
sudo cp systemd/aix-log-collector.service /etc/systemd/system/
sudo cp systemd/grafana-server.service /etc/systemd/system/
sudo systemctl daemon-reload

# Enable services
sudo systemctl enable aix-log-collector
sudo systemctl enable grafana-server

# Setup Grafana
print_status "Setting up Grafana..."
if [ -d "docker" ]; then
    cd docker
    if [ -f "docker-compose.yml" ]; then
        print_status "Starting Grafana with Docker Compose..."
        docker compose up -d
    else
        print_warning "Docker Compose file not found, Grafana will need manual setup"
    fi
    cd ..
else
    print_warning "Docker directory not found, Grafana will need manual setup"
fi

# Set permissions
print_status "Setting permissions..."
if ls scripts/*.py 1> /dev/null 2>&1; then
    print_status "Making Python scripts executable..."
    sudo chmod +x scripts/*.py || print_warning "Failed to change permissions for Python scripts"
else
    print_warning "No Python scripts found in the 'scripts' directory"
fi

if ls scripts/*.sh 1> /dev/null 2>&1; then
    print_status "Making shell scripts executable..."
    sudo chmod +x scripts/*.sh || print_warning "Failed to change permissions for shell scripts"
else
    print_warning "No shell scripts found in the 'scripts' directory"
fi

# Create configuration file if it doesn't exist
if [ ! -f "config/config.yaml" ]; then
    print_status "Creating default configuration file..."
    cp config/config.yaml.example config/config.yaml 2>/dev/null || echo "Please create config/config.yaml manually"
fi

print_status "Setup completed successfully!"
print_status ""
print_status "Next steps:"
print_status "1. Edit config/config.yaml with your AIX server details"
print_status "2. Run: python3 scripts/ssh_setup.py --servers your_aix_server1,your_aix_server2"
print_status "3. Start services: sudo systemctl start aix-log-collector"
print_status "4. Access Grafana at http://localhost:3000 (admin/admin)"
print_status ""
print_status "For more information, see README.md and docs/ directory"
