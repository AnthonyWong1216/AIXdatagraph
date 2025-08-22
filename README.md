# AIX Data Graph - AIX Server Log Collection and Visualization

This project provides a comprehensive solution for collecting AIX server logs (errpt error reports and syslogs) and displaying them in Grafana dashboards on Red Hat Linux 9.

## Features

- **AIX Log Collection**: Automated collection of errpt error reports and syslogs from AIX servers
- **Grafana Visualization**: Real-time dashboards for monitoring AIX server health and errors
- **SSH Key Management**: Automated SSH key generation and distribution to AIX servers
- **Systemd Service**: Runs as a system service for continuous monitoring
- **Docker Support**: Containerized deployment option for easy setup

## Architecture

```
AIX Servers (errpt + syslog) 
    ↓ (SSH)
Log Collector (Python)
    ↓ (InfluxDB)
Grafana Dashboards
```

## Prerequisites

- Red Hat Linux 9 (or compatible)
- Python 3.9+
- Docker and Docker Compose (optional)
- Access to AIX servers via SSH

## Quick Start

### 1. Clone and Setup
```bash
cd AIXdatagraph
chmod +x setup.sh
./setup.sh
```

### 2. Configure AIX Servers
```bash
python3 scripts/ssh_setup.py --servers server1,server2,server3
```

### 3. Start Services
```bash
sudo systemctl start aix-log-collector
sudo systemctl start grafana-server
```

### 4. Access Grafana
Open http://localhost:3000 in your browser
- Username: admin
- Password: admin (change on first login)

## Directory Structure

```
AIXdatagraph/
├── collector/          # Python log collector
├── grafana/           # Grafana configuration and dashboards
├── scripts/           # Setup and utility scripts
├── systemd/           # Systemd service files
├── docker/            # Docker deployment files
├── config/            # Configuration files
└── docs/              # Documentation
```

## Configuration

Edit `config/config.yaml` to customize:
- AIX server list
- Collection intervals
- Log retention policies
- Grafana settings

## Monitoring

The system provides:
- Real-time error report monitoring
- System log analysis
- Historical trend analysis
- Alert notifications
- Custom dashboards

## Troubleshooting

See `docs/troubleshooting.md` for common issues and solutions.

## License

MIT License - see LICENSE file for details.

