#!/bin/bash

# Docker-based Monitoring Stack Installation for IBM Power (ppc64le)
# This script installs InfluxDB and Grafana using Docker containers

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  AIX Data Graph - Docker Installation${NC}"
echo -e "${BLUE}========================================${NC}"
echo "This script will install:"
echo "- InfluxDB 2.7.1 (Docker container)"
echo "- Grafana 10.2.3 (Docker container)"
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

# Step 1: Install Docker
print_header "Installing Docker..."
print_status "Updating system packages..."
dnf update -y

print_status "Installing Docker dependencies..."
dnf install -y dnf-utils device-mapper-persistent-data lvm2

print_status "Adding Docker repository..."
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

print_status "Installing Docker..."
dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker
print_status "Starting Docker service..."
systemctl start docker
systemctl enable docker

# Add current user to docker group (optional)
if [[ -n "$SUDO_USER" ]]; then
    usermod -aG docker $SUDO_USER
    print_status "Added user $SUDO_USER to docker group"
fi

# Step 2: Create directories for persistent data
print_header "Creating directories for persistent data..."
mkdir -p /opt/aixdatagraph/{influxdb,grafana}
mkdir -p /opt/aixdatagraph/influxdb/{data,config}
mkdir -p /opt/aixdatagraph/grafana/{data,config,provisioning}

# Set proper permissions
chown -R 472:472 /opt/aixdatagraph/grafana
chown -R 1000:1000 /opt/aixdatagraph/influxdb

# Step 3: Create Docker Compose file
print_header "Creating Docker Compose configuration..."

# Check if we're on ppc64le architecture
if [[ "$ARCH" == "ppc64le" ]]; then
    print_warning "Detected ppc64le architecture - using alternative images for Power compatibility"
    
    cat > /opt/aixdatagraph/docker-compose.yml << 'EOF'
services:
  influxdb:
    image: quay.io/influxdb/influxdb:2.7.1
    platform: linux/amd64
    container_name: aixdatagraph_influxdb
    restart: unless-stopped
    ports:
      - "8086:8086"
    environment:
      - DOCKER_INFLUXDB_INIT_MODE=setup
      - DOCKER_INFLUXDB_INIT_USERNAME=admin
      - DOCKER_INFLUXDB_INIT_PASSWORD=admin123
      - DOCKER_INFLUXDB_INIT_ORG=aixdatagraph
      - DOCKER_INFLUXDB_INIT_BUCKET=logs
      - DOCKER_INFLUXDB_INIT_RETENTION=30d
      - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=your-super-secret-auth-token
    volumes:
      - ./influxdb/data:/var/lib/influxdb2
      - ./influxdb/config:/etc/influxdb2
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:10.2.3
    platform: linux/amd64
    container_name: aixdatagraph_grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - ./grafana/data:/var/lib/grafana
      - ./grafana/config/grafana.ini:/etc/grafana/grafana.ini
      - ./grafana/provisioning:/etc/grafana/provisioning
    networks:
      - monitoring
    depends_on:
      - influxdb

networks:
  monitoring:
    driver: bridge
EOF
else
    cat > /opt/aixdatagraph/docker-compose.yml << 'EOF'
services:
  influxdb:
    image: influxdb:2.7.1
    container_name: aixdatagraph_influxdb
    restart: unless-stopped
    ports:
      - "8086:8086"
    environment:
      - DOCKER_INFLUXDB_INIT_MODE=setup
      - DOCKER_INFLUXDB_INIT_USERNAME=admin
      - DOCKER_INFLUXDB_INIT_PASSWORD=admin123
      - DOCKER_INFLUXDB_INIT_ORG=aixdatagraph
      - DOCKER_INFLUXDB_INIT_BUCKET=logs
      - DOCKER_INFLUXDB_INIT_RETENTION=30d
      - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=your-super-secret-auth-token
    volumes:
      - ./influxdb/data:/var/lib/influxdb2
      - ./influxdb/config:/etc/influxdb2
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:10.2.3
    container_name: aixdatagraph_grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - ./grafana/data:/var/lib/grafana
      - ./grafana/config/grafana.ini:/etc/grafana/grafana.ini
      - ./grafana/provisioning:/etc/grafana/provisioning
    networks:
      - monitoring
    depends_on:
      - influxdb

networks:
  monitoring:
    driver: bridge
EOF
fi

# Step 4: Create Grafana configuration
print_header "Creating Grafana configuration..."
cat > /opt/aixdatagraph/grafana/config/grafana.ini << 'EOF'
[paths]
data = /var/lib/grafana
logs = /var/log/grafana
plugins = /var/lib/grafana/plugins
provisioning = /etc/grafana/provisioning

[server]
protocol = http
http_addr = 0.0.0.0
http_port = 3000
domain = localhost
root_url = %(protocol)s://%(domain)s:%(http_port)s/
serve_from_sub_path = false

[database]
type = sqlite3
path = /var/lib/grafana/grafana.db

[security]
admin_user = admin
admin_password = admin
secret_key = your-super-secret-key-here

[users]
allow_sign_up = false
allow_org_create = false
auto_assign_org = true
auto_assign_org_role = Viewer

[auth.anonymous]
enabled = false

[log]
mode = console file
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

# Step 5: Create data source provisioning
print_header "Creating data source provisioning..."
mkdir -p /opt/aixdatagraph/grafana/provisioning/datasources
cat > /opt/aixdatagraph/grafana/provisioning/datasources/influxdb.yaml << 'EOF'
apiVersion: 1

datasources:
  - name: InfluxDB
    type: influxdb
    access: proxy
    url: http://influxdb:8086
    secureJsonData:
      token: your-super-secret-auth-token
    jsonData:
      version: Flux
      organization: aixdatagraph
      defaultBucket: logs
      tlsSkipVerify: true
    editable: true
EOF

# Step 6: Create dashboard provisioning
print_header "Creating dashboard provisioning..."
mkdir -p /opt/aixdatagraph/grafana/provisioning/dashboards
cat > /opt/aixdatagraph/grafana/provisioning/dashboards/dashboard.yaml << 'EOF'
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

# Create a sample dashboard
cat > /opt/aixdatagraph/grafana/provisioning/dashboards/logs_dashboard.json << 'EOF'
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

# Step 7: Configure firewall
print_header "Configuring firewall..."
if command -v firewall-cmd > /dev/null 2>&1; then
    firewall-cmd --permanent --add-port=8086/tcp
    firewall-cmd --permanent --add-port=3000/tcp
    firewall-cmd --reload
    print_status "Firewall configured"
fi

# Step 8: Start the services
print_header "Starting monitoring stack..."
cd /opt/aixdatagraph

print_status "Starting containers..."
# Use docker compose (newer syntax) or fallback to docker-compose
if command -v docker > /dev/null 2>&1 && docker compose version > /dev/null 2>&1; then
    docker compose up -d
elif command -v docker-compose > /dev/null 2>&1; then
    docker-compose up -d
else
    print_error "Neither 'docker compose' nor 'docker-compose' is available"
    print_status "Installing docker-compose..."
    dnf install -y docker-compose
    docker-compose up -d
fi

# Step 9: Wait for services to be ready
print_header "Waiting for services to be ready..."
print_status "Waiting for InfluxDB to start..."
for i in {1..60}; do
    if curl -s http://localhost:8086/ping > /dev/null 2>&1; then
        print_status "InfluxDB is ready!"
        break
    fi
    if [[ $i -eq 60 ]]; then
        print_error "InfluxDB failed to start within 60 seconds"
        exit 1
    fi
    sleep 1
done

print_status "Waiting for Grafana to start..."
for i in {1..60}; do
    if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
        print_status "Grafana is ready!"
        break
    fi
    if [[ $i -eq 60 ]]; then
        print_error "Grafana failed to start within 60 seconds"
        exit 1
    fi
    sleep 1
done

# Step 10: Create log collection script
print_header "Creating log collection utilities..."
cat > /usr/local/bin/send_logs_to_influxdb_docker.sh << 'EOF'
#!/bin/bash

# Script to send logs to InfluxDB (Docker version)
# Usage: send_logs_to_influxdb_docker.sh <log_file> [measurement_name]

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

chmod +x /usr/local/bin/send_logs_to_influxdb_docker.sh

# Step 11: Create systemd service for log collection
cat > /etc/systemd/system/log-collector-docker.service << 'EOF'
[Unit]
Description=Log Collector for InfluxDB (Docker)
After=docker.service
Wants=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/send_logs_to_influxdb_docker.sh /var/log/messages system_logs
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# Create a timer for periodic log collection
cat > /etc/systemd/system/log-collector-docker.timer << 'EOF'
[Unit]
Description=Run log collector every 5 minutes (Docker)
Requires=log-collector-docker.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable log-collector-docker.timer

# Step 12: Create management scripts
print_header "Creating management scripts..."
cat > /opt/aixdatagraph/start.sh << 'EOF'
#!/bin/bash
cd /opt/aixdatagraph
# Use docker compose (newer syntax) or fallback to docker-compose
if command -v docker > /dev/null 2>&1 && docker compose version > /dev/null 2>&1; then
    docker compose up -d
elif command -v docker-compose > /dev/null 2>&1; then
    docker-compose up -d
else
    echo "Error: Neither 'docker compose' nor 'docker-compose' is available"
    exit 1
fi
echo "Monitoring stack started"
EOF

cat > /opt/aixdatagraph/stop.sh << 'EOF'
#!/bin/bash
cd /opt/aixdatagraph
# Use docker compose (newer syntax) or fallback to docker-compose
if command -v docker > /dev/null 2>&1 && docker compose version > /dev/null 2>&1; then
    docker compose down
elif command -v docker-compose > /dev/null 2>&1; then
    docker-compose down
else
    echo "Error: Neither 'docker compose' nor 'docker-compose' is available"
    exit 1
fi
echo "Monitoring stack stopped"
EOF

cat > /opt/aixdatagraph/restart.sh << 'EOF'
#!/bin/bash
cd /opt/aixdatagraph
# Use docker compose (newer syntax) or fallback to docker-compose
if command -v docker > /dev/null 2>&1 && docker compose version > /dev/null 2>&1; then
    docker compose restart
elif command -v docker-compose > /dev/null 2>&1; then
    docker-compose restart
else
    echo "Error: Neither 'docker compose' nor 'docker-compose' is available"
    exit 1
fi
echo "Monitoring stack restarted"
EOF

cat > /opt/aixdatagraph/status.sh << 'EOF'
#!/bin/bash
cd /opt/aixdatagraph
# Use docker compose (newer syntax) or fallback to docker-compose
if command -v docker > /dev/null 2>&1 && docker compose version > /dev/null 2>&1; then
    docker compose ps
elif command -v docker-compose > /dev/null 2>&1; then
    docker-compose ps
else
    echo "Error: Neither 'docker compose' nor 'docker-compose' is available"
    exit 1
fi
echo ""
echo "Service URLs:"
echo "- InfluxDB: http://localhost:8086"
echo "- Grafana: http://localhost:3000"
EOF

cat > /opt/aixdatagraph/logs.sh << 'EOF'
#!/bin/bash
cd /opt/aixdatagraph
# Use docker compose (newer syntax) or fallback to docker-compose
if command -v docker > /dev/null 2>&1 && docker compose version > /dev/null 2>&1; then
    docker compose logs -f
elif command -v docker-compose > /dev/null 2>&1; then
    docker-compose logs -f
else
    echo "Error: Neither 'docker compose' nor 'docker-compose' is available"
    exit 1
fi
EOF

chmod +x /opt/aixdatagraph/*.sh

# Step 13: Create README
cat > /opt/aixdatagraph/README_DOCKER.md << 'EOF'
# AIX Data Graph - Docker Installation

This installation uses Docker containers for InfluxDB and Grafana.

## Services
- **InfluxDB 2.7.1**: Time series database for log storage
- **Grafana 10.2.3**: Visualization and dashboard platform

## Access Information
- **Grafana**: http://localhost:3000 (admin/admin)
- **InfluxDB**: http://localhost:8086 (admin/admin123)

## Management Commands
- Start services: `/opt/aixdatagraph/start.sh`
- Stop services: `/opt/aixdatagraph/stop.sh`
- Restart services: `/opt/aixdatagraph/restart.sh`
- Check status: `/opt/aixdatagraph/status.sh`
- View logs: `/opt/aixdatagraph/logs.sh`

## Data Persistence
- InfluxDB data: `/opt/aixdatagraph/influxdb/data`
- Grafana data: `/opt/aixdatagraph/grafana/data`
- Configurations: `/opt/aixdatagraph/grafana/config`

## Log Collection
- Automatic: Every 5 minutes via systemd timer
- Manual: `/usr/local/bin/send_logs_to_influxdb_docker.sh <log_file>`

## Docker Commands
```bash
# View running containers
docker ps

# View container logs
docker logs aixdatagraph_influxdb
docker logs aixdatagraph_grafana

# Access container shell
docker exec -it aixdatagraph_influxdb /bin/bash
docker exec -it aixdatagraph_grafana /bin/bash
```

## Troubleshooting
1. Check container status: `docker ps -a`
2. View container logs: `docker logs <container_name>`
3. Restart containers: `docker-compose restart`
4. Rebuild containers: `docker-compose up -d --build`
EOF

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
print_status "Management scripts:"
echo "- Start: /opt/aixdatagraph/start.sh"
echo "- Stop: /opt/aixdatagraph/stop.sh"
echo "- Status: /opt/aixdatagraph/status.sh"
echo "- Logs: /opt/aixdatagraph/logs.sh"
echo ""
print_status "Documentation: /opt/aixdatagraph/README_DOCKER.md"
echo ""
print_warning "IMPORTANT: Change default passwords after first login!"
echo ""
print_status "Log collection is configured to run every 5 minutes"
print_status "Manual log collection: /usr/local/bin/send_logs_to_influxdb_docker.sh <log_file>"
