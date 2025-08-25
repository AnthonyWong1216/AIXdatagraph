# AIX Log Collection System

This system allows AIX clients to send syslog and errpt (error log) data to a Linux server, which processes and stores the data in InfluxDB for visualization in Grafana.

## Overview

- **AIX Client Script**: Collects and sends system logs and error reports
- **Linux Server Script**: Receives, processes, and stores data in InfluxDB
- **No Additional Packages Required**: Uses only built-in system tools

## Files

1. `aix_client_log_sender.sh` - AIX client script
2. `linux_server_rsyslog_config.sh` - Linux server rsyslog configuration script
3. `install_grafana_influxdb.sh` - Grafana/InfluxDB installation script

## Prerequisites

### AIX Client Requirements
- AIX system with basic shell tools
- Network connectivity to Linux server
- `nc` (netcat) or `telnet` for data transmission
- Root access (recommended for complete log access)

### Linux Server Requirements
- Linux system with basic shell tools
- `rsyslog` (usually pre-installed)
- `curl` for InfluxDB communication
- Root access for port binding
- InfluxDB running (from the installation script)

## Configuration

### AIX Client Configuration

Edit `aix_client_log_sender.sh` and modify these variables:

```bash
SERVER_IP="192.168.1.100"  # Change to your Linux server IP
SERVER_PORT="514"           # Default syslog port
ERRPT_PORT="515"            # Custom port for errpt data
```

### Linux Server Configuration

Edit `linux_server_log_receiver.sh` and modify these variables:

```bash
SYSLOG_PORT="514"           # Port for receiving syslog data
ERRPT_PORT="515"            # Port for receiving errpt data
INFLUXDB_HOST="localhost"   # InfluxDB host
INFLUXDB_PORT="8086"        # InfluxDB port
INFLUXDB_DB="NewDB"         # InfluxDB database name
```

## Installation and Setup

### Step 1: Install Grafana and InfluxDB (Linux Server)

```bash
# Run the installation script
sudo ./install_grafana_influxdb.sh
```

This will:
- Install InfluxDB and Grafana
- Create the "NewDB" database
- Configure Grafana datasource
- Set up firewall rules

### Step 2: Configure rsyslog for AIX Log Reception (Linux Server)

```bash
# Make script executable
chmod +x linux_server_rsyslog_config.sh

# Run the configuration script
sudo ./linux_server_rsyslog_config.sh
```

This will:
- Install rsyslog if not present
- Configure rsyslog to listen on ports 514 (UDP/TCP) and 515 (TCP)
- Set up firewall rules automatically
- Create log processing scripts
- Set up systemd timers for automatic processing

### Step 3: Configure AIX Client

```bash
# Copy script to AIX system
scp aix_client_log_sender.sh aix_host:/tmp/

# On AIX system, make executable
chmod +x /tmp/aix_client_log_sender.sh

# Edit server IP address
vi /tmp/aix_client_log_sender.sh
```

### Step 4: Run AIX Client

```bash
# Run manually
sudo /tmp/aix_client_log_sender.sh

# Or set up automated collection
# The script will offer to create a cron job
```

## Data Flow

1. **AIX Client** collects:
   - System logs (`/var/adm/syslog`, `/var/adm/messages`)
   - Error reports (`errpt -a`)
   - Performance data (`vmstat`, `svmon`, `df`)

2. **Data Transmission**:
   - Syslog data sent to port 514
   - Errpt data sent to port 515
   - Uses `nc` (netcat) or `telnet`

3. **Linux Server** processes:
   - rsyslog receives data on specified ports
   - Filters and saves AIX-specific messages
   - Background processor categorizes errpt data
   - Stores error counts in InfluxDB
   - Saves raw logs to files

4. **InfluxDB Storage**:
   - Error counts by category (hardware, software, operator, unknown)
   - Timestamped data for each AIX system
   - Queryable via Grafana

## Data Structure in InfluxDB

### Measurement: `aix_errors`
- **Tags**: `hostname`, `ip`, `category`
- **Fields**: `value` (error count)
- **Categories**: hardware, software, operator, unknown, total

### Example Queries

```sql
-- Get all error counts for a specific host
SELECT * FROM aix_errors WHERE hostname='aix_hostname'

-- Get hardware errors by time
SELECT value FROM aix_errors WHERE category='hardware' AND time > now() - 1h

-- Get total errors by host
SELECT sum(value) FROM aix_errors WHERE category='total' GROUP BY hostname
```

## Grafana Dashboard

Access Grafana at `http://your_server:3000`
- Username: `admin`
- Password: `P@ssw0rd`

### Sample Dashboard Queries

1. **Error Trends Over Time**:
   ```sql
   SELECT mean(value) FROM aix_errors WHERE category='total' GROUP BY time(5m), hostname
   ```

2. **Error Distribution by Category**:
   ```sql
   SELECT sum(value) FROM aix_errors WHERE time > now() - 1h GROUP BY category
   ```

3. **Top Error Sources**:
   ```sql
   SELECT sum(value) FROM aix_errors WHERE time > now() - 24h GROUP BY hostname ORDER BY sum DESC LIMIT 10
   ```

## Monitoring and Maintenance

### Check Server Status
```bash
# Check rsyslog status
sudo systemctl status rsyslog

# Check log processor status
sudo systemctl status aix-log-processor.timer

# View rsyslog logs
sudo journalctl -u rsyslog -f

# View processor logs
sudo tail -f /var/log/aix_processor.log
```

### Check AIX Client
```bash
# Test connectivity
ping linux_server_ip

# Test port connectivity
nc -zv linux_server_ip 514
nc -zv linux_server_ip 515
```

### View Processed Data
```bash
# View processed log files
ls -la /var/log/aix_processed/

# View recent syslog files
tail -f /var/log/aix_processed/syslog_*.txt

# View recent errpt files
tail -f /var/log/aix_processed/errpt_*.txt
```

## Troubleshooting

### Common Issues

1. **Connection Refused**:
   - Check firewall settings
   - Verify server IP address
   - Ensure ports are open

2. **No Data in InfluxDB**:
   - Check InfluxDB service status
   - Verify database "NewDB" exists
   - Check curl availability

3. **Permission Denied**:
   - Run scripts as root
   - Check file permissions
   - Verify directory access

4. **No Logs Received**:
   - Check network connectivity
   - Verify listener is running
   - Check AIX client configuration

### Debug Commands

```bash
# Test InfluxDB connection
curl http://localhost:8086/ping

# Check database
influx -execute "SHOW DATABASES"

# Test data insertion
echo "aix_errors,hostname=test,ip=192.168.1.1,category=hardware value=5 $(date +%s)000000000" | \
curl -X POST "http://localhost:8086/write?db=NewDB" --data-binary @-
```

## Security Considerations

1. **Network Security**: Use VPN or firewall rules to restrict access
2. **Authentication**: Consider adding authentication to data transmission
3. **Data Retention**: Implement log rotation and cleanup
4. **Access Control**: Restrict access to log files and scripts

## Automation

### AIX Client Automation
The script can set up cron jobs for automated collection:
```bash
# Add to crontab for collection every 6 hours
0 */6 * * * /tmp/aix_logs/collect_logs.sh
```

### Linux Server Automation
The server script runs as a systemd service and automatically:
- Starts on boot
- Restarts on failure
- Processes logs every 30 seconds
- Shows statistics every 5 minutes

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review log files for error messages
3. Verify network connectivity
4. Test individual components
