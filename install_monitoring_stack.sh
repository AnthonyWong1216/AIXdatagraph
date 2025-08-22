#!/bin/bash

# Complete Monitoring Stack Installation Script for RHEL 9
# Installs InfluxDB + Grafana for log collection and visualization

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  AIX Data Graph Monitoring Stack Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo "This script will install:"
echo "- InfluxDB 2.7.1 (Time series database for logs)"
echo "- Grafana 10.2.3 (Visualization and dashboards)"
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

# Get current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Step 1: Install InfluxDB
print_header "Installing InfluxDB..."
if [[ -f "$SCRIPT_DIR/install_influxdb.sh" ]]; then
    bash "$SCRIPT_DIR/install_influxdb.sh"
else
    print_error "install_influxdb.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Step 2: Install Grafana
print_header "Installing Grafana..."
if [[ -f "$SCRIPT_DIR/install_grafana.sh" ]]; then
    bash "$SCRIPT_DIR/install_grafana.sh"
else
    print_error "install_grafana.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Step 3: Start services
print_header "Starting services..."
print_status "Starting InfluxDB..."
systemctl start influxdb
systemctl enable influxdb

print_status "Starting Grafana..."
systemctl start grafana-server
systemctl enable grafana-server

# Step 4: Wait for services to be ready
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

# Step 5: Create InfluxDB initial setup
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

# Step 6: Create InfluxDB token for Grafana
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

# Step 7: Configure Grafana data source
print_header "Configuring Grafana data source..."
print_status "Adding InfluxDB as data source in Grafana..."

# Wait a bit more for Grafana to be fully ready
sleep 5

# Create data source configuration
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

# Step 8: Create sample dashboard
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

# Step 9: Create log collection script
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
TOKEN="admin123"  # This should be the admin token or a dedicated token

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

# Step 10: Create systemd service for log collection
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

# Step 11: Create README
cat > /opt/aixdatagraph/README.md << EOF
# AIX Data Graph Monitoring Stack

This installation includes:

## Services
- **InfluxDB 2.7.1**: Time series database for log storage
- **Grafana 10.2.3**: Visualization and dashboard platform

## Access Information
- **Grafana**: http://localhost:3000 (admin/admin)
- **InfluxDB**: http://localhost:8086 (admin/admin123)

## Configuration Files
- InfluxDB config: /etc/influxdb/influxdb.conf
- Grafana config: /etc/grafana/grafana.ini
- Data sources: /etc/grafana/provisioning/datasources/
- Dashboards: /etc/grafana/provisioning/dashboards/

## Useful Commands
- Check service status: \`systemctl status influxdb grafana-server\`
- View logs: \`journalctl -u influxdb -f\` or \`journalctl -u grafana-server -f\`
- Manual log collection: \`/usr/local/bin/send_logs_to_influxdb.sh <log_file>\`
- Restart services: \`systemctl restart influxdb grafana-server\`

## Data Organization
- **Organization**: aixdatagraph
- **Bucket**: logs
- **Retention**: 30 days

## Next Steps
1. Access Grafana and change default passwords
2. Import additional dashboards
3. Configure log sources
4. Set up alerts and notifications
EOF

mkdir -p /opt/aixdatagraph
chmod 644 /opt/aixdatagraph/README.md

# Clean up
rm -f /tmp/setup_influxdb.sh

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
print_status "Documentation: /opt/aixdatagraph/README.md"
echo ""
print_warning "IMPORTANT: Change default passwords after first login!"
echo ""
print_status "Log collection is configured to run every 5 minutes"
print_status "Manual log collection: /usr/local/bin/send_logs_to_influxdb.sh <log_file>"
