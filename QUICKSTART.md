# AIX Data Graph - Quick Start Guide

This guide will get you up and running with AIX Data Graph in under 10 minutes.

## Prerequisites

- Red Hat Linux 9 (or compatible)
- Python 3.9+
- Docker and Docker Compose
- Access to AIX servers via SSH

## Quick Installation

### 1. Clone and Setup

```bash
# Clone the repository
git clone <your-repo-url>
cd AIXdatagraph

# Make scripts executable
chmod +x *.sh

# Run the installation script
./install.sh
```

### 2. Configure AIX Servers

Edit `config/config.yaml` and update the AIX server list:

```yaml
aix_servers:
  - name: "my-aix-server"
    hostname: "192.168.1.100"
    username: "root"
    port: 22
    description: "My AIX Server"
```

### 3. Setup SSH Keys

```bash
# Copy your SSH key to AIX servers
ssh-copy-id -i ~/.ssh/id_rsa.pub root@192.168.1.100

# Test the connection
python3 scripts/ssh_setup.py --servers 192.168.1.100 --test-only
```

### 4. Start Services

```bash
# Start all services
./start_services.sh

# Check status
./status.sh
```

### 5. Access Grafana

Open your browser and go to: http://localhost:3000
- Username: `admin`
- Password: `admin`

## First Run

### Test Log Collection

```bash
# Run collection once
python3 collector/aix_log_collector.py --once

# Run as daemon
python3 collector/aix_log_collector.py --daemon
```

### View Dashboards

1. In Grafana, go to Dashboards
2. Look for "AIX Server Overview"
3. The dashboard will show:
   - Error reports by server
   - System log entries
   - Error severity breakdown
   - Collection success rates

## Configuration

### Key Configuration Files

- `config/config.yaml` - Main configuration
- `docker/docker-compose.yml` - Docker services
- `systemd/` - System service definitions

### Important Settings

```yaml
# Collection intervals (in seconds)
collection:
  errpt_interval: 300      # 5 minutes
  syslog_interval: 60      # 1 minute

# Database settings
database:
  influxdb:
    url: "http://localhost:8086"
    bucket: "aix-logs"
    retention_policy: "30d"
```

## Monitoring

### Service Status

```bash
# Check all services
./status.sh

# Check specific service
sudo systemctl status aix-log-collector
sudo systemctl status grafana-server

# View logs
sudo journalctl -u aix-log-collector -f
```

### Docker Services

```bash
cd docker
docker-compose ps
docker-compose logs -f
```

## Troubleshooting

### Common Issues

1. **SSH Connection Failed**
   ```bash
   # Test SSH manually
   ssh root@your-aix-server
   
   # Check SSH key permissions
   chmod 600 ~/.ssh/id_rsa
   chmod 644 ~/.ssh/id_rsa.pub
   ```

2. **InfluxDB Connection Failed**
   ```bash
   # Check if InfluxDB is running
   curl http://localhost:8086/health
   
   # Restart Docker services
   cd docker && docker-compose restart
   ```

3. **Grafana Not Accessible**
   ```bash
   # Check Grafana service
   sudo systemctl status grafana-server
   
   # Check Docker container
   docker ps | grep grafana
   ```

### Log Locations

- Application logs: `/var/log/aix-log-collector/`
- System logs: `sudo journalctl -u aix-log-collector`
- Docker logs: `docker-compose logs`

## Next Steps

1. **Customize Dashboards**: Modify Grafana dashboards in `grafana/dashboards/`
2. **Add More Servers**: Update `config/config.yaml` with additional AIX servers
3. **Set Up Alerts**: Configure alerting in Grafana
4. **Backup Data**: Set up InfluxDB backup procedures
5. **Scale Up**: Add more collectors for larger environments

## Support

- Check the main README.md for detailed documentation
- Review logs for error messages
- Check service status with provided scripts
- Ensure all prerequisites are met

## Quick Commands Reference

```bash
# Start everything
./start_services.sh

# Stop everything
./stop_services.sh

# Check status
./status.sh

# Test collection
python3 collector/aix_log_collector.py --once

# Run daemon
python3 collector/aix_log_collector.py --daemon

# Test SSH connections
python3 scripts/ssh_setup.py --servers server1,server2 --test-only

# View logs
sudo journalctl -u aix-log-collector -f
sudo journalctl -u grafana-server -f
```

That's it! You should now have a fully functional AIX log collection and monitoring system running.
