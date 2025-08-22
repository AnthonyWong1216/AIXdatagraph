# AIX Data Graph Monitoring Stack

This directory contains scripts to install and configure a complete monitoring stack for log collection and visualization on Red Hat Enterprise Linux 9.

## Overview

The monitoring stack consists of:
- **InfluxDB 2.7.1**: Time series database for storing log data
- **Grafana 10.2.3**: Visualization platform for creating dashboards and alerts

## Installation Scripts

### 1. Power Native Installation (Recommended for IBM Power)
```bash
sudo bash install_power_native.sh
```
This script installs InfluxDB and Grafana natively on IBM Power servers with Power-specific optimizations and fallback support.

### 2. Docker Installation (Alternative for IBM Power)
```bash
sudo bash install_with_docker.sh
```
This script installs InfluxDB and Grafana using Docker containers with platform emulation for Power architecture.

### 3. Complete Native Installation (x86_64)
```bash
sudo bash install_monitoring_stack.sh
```
This script installs both InfluxDB and Grafana natively, configures them to work together, and sets up automatic log collection.

### 4. Individual Native Installations
```bash
# Install InfluxDB only
sudo bash install_influxdb.sh

# Install Grafana only  
sudo bash install_grafana.sh
```

## Prerequisites

- Red Hat Enterprise Linux 9 (or compatible)
- Root/sudo access
- Internet connection for downloading packages
- At least 2GB RAM and 10GB disk space
- **For IBM Power servers**: Docker installation is recommended for better compatibility

## What Gets Installed

### Native Installation
#### InfluxDB
- Installed to `/opt/influxdb/`
- Configuration: `/etc/influxdb/influxdb.conf`
- Data directory: `/var/lib/influxdb/`
- Logs: `/var/log/influxdb/`
- Service: `influxdb.service`
- Port: 8086

#### Grafana
- Installed to `/usr/share/grafana/`
- Configuration: `/etc/grafana/grafana.ini`
- Data directory: `/var/lib/grafana/`
- Logs: `/var/log/grafana/`
- Service: `grafana-server.service`
- Port: 3000

### Docker Installation
#### InfluxDB
- Container: `aixdatagraph_influxdb`
- Data volume: `/opt/aixdatagraph/influxdb/data`
- Configuration: `/opt/aixdatagraph/influxdb/config`
- Port: 8086

#### Grafana
- Container: `aixdatagraph_grafana`
- Data volume: `/opt/aixdatagraph/grafana/data`
- Configuration: `/opt/aixdatagraph/grafana/config`
- Port: 3000

## Default Access

After installation:
- **Grafana**: http://localhost:3000 (admin/admin)
- **InfluxDB**: http://localhost:8086 (admin/admin123)

⚠️ **Important**: Change default passwords after first login!

## Log Collection

### Automatic Collection
The installation includes a systemd timer that collects logs every 5 minutes:
```bash
# Check timer status
systemctl status log-collector.timer

# View collected logs
journalctl -u log-collector.service
```

### Manual Collection
```bash
# Send specific log file to InfluxDB
/usr/local/bin/send_logs_to_influxdb.sh /var/log/messages system_logs

# Send custom log file
/usr/local/bin/send_logs_to_influxdb.sh /path/to/your/logfile custom_logs
```

## Data Organization

- **Organization**: aixdatagraph
- **Bucket**: logs
- **Retention**: 30 days
- **Default Dashboard**: AIX Logs Dashboard

## Useful Commands

### Service Management
```bash
# Check service status
systemctl status influxdb grafana-server

# Start services
systemctl start influxdb grafana-server

# Stop services
systemctl stop influxdb grafana-server

# Restart services
systemctl restart influxdb grafana-server

# Enable auto-start
systemctl enable influxdb grafana-server
```

### Logs and Debugging
```bash
# View InfluxDB logs
journalctl -u influxdb -f

# View Grafana logs
journalctl -u grafana-server -f

# Check InfluxDB health
curl http://localhost:8086/ping

# Check Grafana health
curl http://localhost:3000/api/health
```

### Data Management
```bash
# Access InfluxDB CLI
influx

# List organizations
influx org list

# List buckets
influx bucket list

# Query data
influx query 'from(bucket:"logs") |> range(start: -1h) |> count()'
```

## Configuration Files

### InfluxDB
- Main config: `/etc/influxdb/influxdb.conf`
- Service file: `/etc/systemd/system/influxdb.service`
- Log rotation: `/etc/logrotate.d/influxdb`

### Grafana
- Main config: `/etc/grafana/grafana.ini`
- Service file: `/etc/systemd/system/grafana-server.service`
- Data sources: `/etc/grafana/provisioning/datasources/`
- Dashboards: `/etc/grafana/provisioning/dashboards/`
- Log rotation: `/etc/logrotate.d/grafana`

## Security Considerations

1. **Change default passwords** immediately after installation
2. **Configure firewall** rules for production use
3. **Enable HTTPS** for production deployments
4. **Set up proper authentication** and authorization
5. **Regular backups** of configuration and data

## Troubleshooting

### Common Issues

1. **No matching manifest for linux/ppc64le**
   ```bash
   # Use the Power native installation instead:
   sudo bash install_power_native.sh
   
   # Or try Docker with platform emulation:
   # The Docker script now includes platform: linux/amd64 for Power servers
   ```

2. **Docker Compose command not found**
   ```bash
   # For newer Docker versions, use:
   docker compose up -d
   
   # For older versions, install docker-compose:
   dnf install -y docker-compose
   
   # Or use the management scripts:
   /opt/aixdatagraph/start.sh
   ```

3. **Services won't start**
   ```bash
   # Check logs
   journalctl -u influxdb -n 50
   journalctl -u grafana-server -n 50
   
   # Check ports
   netstat -tlnp | grep -E ':(8086|3000)'
   ```

4. **Permission issues**
   ```bash
   # Fix ownership
   chown -R influxdb:influxdb /var/lib/influxdb /var/log/influxdb
   chown -R grafana:grafana /var/lib/grafana /var/log/grafana
   ```

5. **SELinux issues**
   ```bash
   # Check SELinux status
   sestatus
   
   # Allow network connections
   setsebool -P httpd_can_network_connect 1
   ```

6. **Firewall issues**
   ```bash
   # Open required ports
   firewall-cmd --permanent --add-port=8086/tcp
   firewall-cmd --permanent --add-port=3000/tcp
   firewall-cmd --reload
   ```

### Getting Help

- Check service logs: `journalctl -u <service-name> -f`
- Verify configuration files for syntax errors
- Test connectivity: `curl http://localhost:<port>`
- Check system resources: `top`, `df -h`, `free -h`

## Next Steps

1. **Secure the installation** by changing passwords and enabling HTTPS
2. **Import additional dashboards** for specific use cases
3. **Configure log sources** for your specific environment
4. **Set up alerts** and notifications
5. **Create custom visualizations** for your data
6. **Set up backup and recovery** procedures

## Support

For issues specific to this installation:
1. Check the troubleshooting section above
2. Review service logs for error messages
3. Verify system requirements are met
4. Ensure network connectivity is available

For InfluxDB and Grafana specific issues, refer to their official documentation:
- [InfluxDB Documentation](https://docs.influxdata.com/)
- [Grafana Documentation](https://grafana.com/docs/)
