#!/bin/bash

# Linux Server rsyslog Configuration Script
# Configures rsyslog to receive AIX logs and process them
# Date: August 25, 2025

# Exit on any error
set -e

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Configuration
SYSLOG_PORT="514"
ERRPT_PORT="515"
LOG_DIR="/var/log/aix_logs"
PROCESSED_DIR="/var/log/aix_processed"
INFLUXDB_HOST="localhost"
INFLUXDB_PORT="8086"
INFLUXDB_DB="NewDB"

# Create necessary directories
mkdir -p "$LOG_DIR"
mkdir -p "$PROCESSED_DIR"

# Function to check if rsyslog is installed
check_rsyslog() {
    if ! command -v rsyslogd >/dev/null 2>&1; then
        log_message "ERROR: rsyslog is not installed. Installing rsyslog..."
        if command -v dnf >/dev/null 2>&1; then
            dnf install -y rsyslog
        elif command -v yum >/dev/null 2>&1; then
            yum install -y rsyslog
        elif command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y rsyslog
        else
            log_message "ERROR: Cannot install rsyslog. Please install it manually."
            exit 1
        fi
    fi
    log_message "SUCCESS: rsyslog is available"
}

# Function to configure rsyslog
configure_rsyslog() {
    log_message "Configuring rsyslog to receive AIX logs..."
    
    # Backup original rsyslog config
    cp /etc/rsyslog.conf /etc/rsyslog.conf.backup.$(date +%Y%m%d_%H%M%S)
    
    # Create rsyslog configuration for AIX logs
    cat > /etc/rsyslog.d/aix-logs.conf << EOF
# AIX Log Collection Configuration
# Listen on UDP port 514 for syslog data
module(load="imudp")
input(type="imudp" port="$SYSLOG_PORT")

# Listen on TCP port 514 for syslog data
module(load="imtcp")
input(type="imtcp" port="$SYSLOG_PORT")

# Listen on TCP port 515 for errpt data
input(type="imtcp" port="$ERRPT_PORT")

# Filter AIX syslog messages and save to file
if \$msg contains "=== AIX SYSLOG DATA ===" then {
    action(type="omfile" file="$LOG_DIR/syslog_raw.log")
    stop
}

# Filter AIX errpt messages and save to file
if \$msg contains "=== AIX ERROR LOG DATA ===" then {
    action(type="omfile" file="$LOG_DIR/errpt_raw.log")
    stop
}

# Filter AIX performance messages and save to file
if \$msg contains "=== AIX PERFORMANCE DATA ===" then {
    action(type="omfile" file="$LOG_DIR/performance_raw.log")
    stop
}

# Log all other messages normally
EOF
    
    log_message "rsyslog configuration created at /etc/rsyslog.d/aix-logs.conf"
}

# Function to configure firewall
configure_firewall() {
    log_message "Configuring firewall for AIX log collection..."
    
    # Check if firewalld is running
    if systemctl is-active --quiet firewalld; then
        log_message "Configuring firewalld..."
        
        # Add ports to firewall
        firewall-cmd --add-port="$SYSLOG_PORT"/udp --permanent
        firewall-cmd --add-port="$SYSLOG_PORT"/tcp --permanent
        firewall-cmd --add-port="$ERRPT_PORT"/tcp --permanent
        
        # Reload firewall
        firewall-cmd --reload
        
        log_message "Firewall configured: UDP/TCP port $SYSLOG_PORT, TCP port $ERRPT_PORT"
        
    elif command -v iptables >/dev/null 2>&1; then
        log_message "Configuring iptables..."
        
        # Add iptables rules
        iptables -A INPUT -p udp --dport "$SYSLOG_PORT" -j ACCEPT
        iptables -A INPUT -p tcp --dport "$SYSLOG_PORT" -j ACCEPT
        iptables -A INPUT -p tcp --dport "$ERRPT_PORT" -j ACCEPT
        
        # Save iptables rules
        if command -v iptables-save >/dev/null 2>&1; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || \
            iptables-save > /etc/sysconfig/iptables 2>/dev/null || \
            log_message "WARNING: Could not save iptables rules"
        fi
        
        log_message "iptables configured: UDP/TCP port $SYSLOG_PORT, TCP port $ERRPT_PORT"
        
    else
        log_message "WARNING: No firewall detected. Please configure manually:"
        log_message "  - Allow UDP/TCP port $SYSLOG_PORT"
        log_message "  - Allow TCP port $ERRPT_PORT"
    fi
}

# Function to create log processing script
create_processor_script() {
    log_message "Creating log processing script..."
    
    cat > /usr/local/bin/process_aix_logs.sh << 'EOF'
#!/bin/bash

# AIX Log Processing Script
# Processes received AIX logs and stores in InfluxDB
# Date: August 25, 2025

LOG_DIR="/var/log/aix_logs"
PROCESSED_DIR="/var/log/aix_processed"
INFLUXDB_HOST="localhost"
INFLUXDB_PORT="8086"
INFLUXDB_DB="NewDB"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/aix_processor.log
}

# Function to insert data into InfluxDB
insert_to_influxdb() {
    local data_type="$1"
    local hostname="$2"
    local ip_address="$3"
    local timestamp="$4"
    local value="$5"
    local category="$6"
    
    # Create InfluxDB line protocol format
    local measurement="aix_${data_type}"
    local tags="hostname=${hostname},ip=${ip_address}"
    if [ -n "$category" ]; then
        tags="${tags},category=${category}"
    fi
    
    local line="${measurement},${tags} value=${value} ${timestamp}"
    
    # Insert into InfluxDB
    if command -v curl >/dev/null 2>&1; then
        echo "$line" | curl -s -X POST "http://${INFLUXDB_HOST}:${INFLUXDB_PORT}/write?db=${INFLUXDB_DB}" \
            --data-binary @- >/dev/null 2>&1 || true
    fi
}

# Function to parse and categorize errpt data
parse_errpt_data() {
    local input_file="$1"
    local output_file="$2"
    
    if [ ! -f "$input_file" ] || [ ! -s "$input_file" ]; then
        return
    fi
    
    log_message "Parsing errpt data from $input_file"
    
    # Extract system information
    local hostname=$(grep "Hostname:" "$input_file" | head -1 | cut -d: -f2 | xargs)
    local ip_address=$(grep "IP Address:" "$input_file" | head -1 | cut -d: -f2 | xargs)
    local collection_time=$(grep "Collection Time:" "$input_file" | head -1 | cut -d: -f2- | xargs)
    
    # Parse error log entries
    local temp_file=$(mktemp)
    
    # Extract error entries
    awk '/=== ERROR LOG ENTRIES ===/,/=== ERROR SUMMARY BY TYPE ===/' "$input_file" | \
    grep -v "===" | grep -v "^$" > "$temp_file"
    
    # Categorize errors by type
    local hardware_errors=0
    local software_errors=0
    local operator_errors=0
    local unknown_errors=0
    
    while IFS= read -r line; do
        if [[ "$line" =~ [Hh]ardware ]]; then
            ((hardware_errors++))
        elif [[ "$line" =~ [Ss]oftware ]]; then
            ((software_errors++))
        elif [[ "$line" =~ [Oo]perator ]]; then
            ((operator_errors++))
        else
            ((unknown_errors++))
        fi
    done < "$temp_file"
    
    # Create categorized output
    cat > "$output_file" << EOF
=== PARSED ERRPT DATA ===
Hostname: $hostname
IP Address: $ip_address
Collection Time: $collection_time
Parse Time: $(date '+%Y-%m-%d %H:%M:%S')

=== ERROR CATEGORIES ===
Hardware Errors: $hardware_errors
Software Errors: $software_errors
Operator Errors: $operator_errors
Unknown Errors: $unknown_errors
Total Errors: $((hardware_errors + software_errors + operator_errors + unknown_errors))

=== ERROR DETAILS ===
$(cat "$temp_file")
EOF
    
    rm -f "$temp_file"
    
    # Store in InfluxDB
    local timestamp=$(date -d "$collection_time" +%s)000000000 2>/dev/null || $(date +%s)000000000
    
    if [ -n "$hardware_errors" ] && [ "$hardware_errors" -ge 0 ]; then
        insert_to_influxdb "errors" "$hostname" "$ip_address" "$timestamp" "$hardware_errors" "hardware"
    fi
    
    if [ -n "$software_errors" ] && [ "$software_errors" -ge 0 ]; then
        insert_to_influxdb "errors" "$hostname" "$ip_address" "$timestamp" "$software_errors" "software"
    fi
    
    if [ -n "$operator_errors" ] && [ "$operator_errors" -ge 0 ]; then
        insert_to_influxdb "errors" "$hostname" "$ip_address" "$timestamp" "$operator_errors" "operator"
    fi
    
    if [ -n "$unknown_errors" ] && [ "$unknown_errors" -ge 0 ]; then
        insert_to_influxdb "errors" "$hostname" "$ip_address" "$timestamp" "$unknown_errors" "unknown"
    fi
    
    local total_errors=$((hardware_errors + software_errors + operator_errors + unknown_errors))
    if [ "$total_errors" -ge 0 ]; then
        insert_to_influxdb "errors" "$hostname" "$ip_address" "$timestamp" "$total_errors" "total"
    fi
    
    log_message "Errpt data processed and stored in InfluxDB for $hostname"
}

# Function to process log files
process_logs() {
    # Process syslog data
    if [ -f "$LOG_DIR/syslog_raw.log" ] && [ -s "$LOG_DIR/syslog_raw.log" ]; then
        log_message "Processing syslog data"
        
        # Split syslog data by system
        awk '/=== AIX SYSLOG DATA ===/{filename="'$PROCESSED_DIR'/syslog_" ++count "_" strftime("%Y%m%d_%H%M%S") ".txt"} {print > filename}' "$LOG_DIR/syslog_raw.log"
        
        # Clear processed data
        > "$LOG_DIR/syslog_raw.log"
    fi
    
    # Process errpt data
    if [ -f "$LOG_DIR/errpt_raw.log" ] && [ -s "$LOG_DIR/errpt_raw.log" ]; then
        log_message "Processing errpt data"
        
        # Split errpt data by system
        awk '/=== AIX ERROR LOG DATA ===/{filename="'$PROCESSED_DIR'/errpt_" ++count "_" strftime("%Y%m%d_%H%M%S") ".txt"} {print > filename}' "$LOG_DIR/errpt_raw.log"
        
        # Process each errpt file
        for file in "$PROCESSED_DIR"/errpt_*.txt; do
            if [ -f "$file" ]; then
                parse_errpt_data "$file" "${file%.txt}_parsed.txt"
            fi
        done
        
        # Clear processed data
        > "$LOG_DIR/errpt_raw.log"
    fi
    
    # Process performance data
    if [ -f "$LOG_DIR/performance_raw.log" ] && [ -s "$LOG_DIR/performance_raw.log" ]; then
        log_message "Processing performance data"
        
        # Split performance data by system
        awk '/=== AIX PERFORMANCE DATA ===/{filename="'$PROCESSED_DIR'/performance_" ++count "_" strftime("%Y%m%d_%H%M%S") ".txt"} {print > filename}' "$LOG_DIR/performance_raw.log"
        
        # Clear processed data
        > "$LOG_DIR/performance_raw.log"
    fi
}

# Main processing
process_logs
EOF
    
    chmod +x /usr/local/bin/process_aix_logs.sh
    log_message "Log processing script created at /usr/local/bin/process_aix_logs.sh"
}

# Function to create systemd service for log processing
create_processor_service() {
    log_message "Creating systemd service for log processing..."
    
    cat > /etc/systemd/system/aix-log-processor.service << EOF
[Unit]
Description=AIX Log Processor Service
After=rsyslog.service
Requires=rsyslog.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/process_aix_logs.sh
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    # Create timer for periodic processing
    cat > /etc/systemd/system/aix-log-processor.timer << EOF
[Unit]
Description=Run AIX Log Processor every 30 seconds
Requires=aix-log-processor.service

[Timer]
OnBootSec=30
OnUnitActiveSec=30
Unit=aix-log-processor.service

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    systemctl enable aix-log-processor.timer
    systemctl start aix-log-processor.timer
    
    log_message "Systemd timer created and enabled for log processing every 30 seconds"
}

# Function to restart rsyslog
restart_rsyslog() {
    log_message "Restarting rsyslog service..."
    
    if systemctl is-active --quiet rsyslog; then
        systemctl restart rsyslog
        log_message "rsyslog restarted successfully"
    else
        systemctl start rsyslog
        systemctl enable rsyslog
        log_message "rsyslog started and enabled"
    fi
}

# Function to test configuration
test_configuration() {
    log_message "Testing configuration..."
    
    # Test rsyslog is listening
    if netstat -tuln | grep -q ":$SYSLOG_PORT "; then
        log_message "SUCCESS: rsyslog is listening on port $SYSLOG_PORT"
    else
        log_message "ERROR: rsyslog is not listening on port $SYSLOG_PORT"
    fi
    
    if netstat -tuln | grep -q ":$ERRPT_PORT "; then
        log_message "SUCCESS: rsyslog is listening on port $ERRPT_PORT"
    else
        log_message "ERROR: rsyslog is not listening on port $ERRPT_PORT"
    fi
    
    # Test firewall
    if firewall-cmd --list-ports 2>/dev/null | grep -q "$SYSLOG_PORT"; then
        log_message "SUCCESS: Firewall allows port $SYSLOG_PORT"
    else
        log_message "WARNING: Firewall may not allow port $SYSLOG_PORT"
    fi
}

# Main execution
main() {
    log_message "Starting rsyslog configuration for AIX log collection..."
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_message "ERROR: This script must be run as root"
        exit 1
    fi
    
    # Check and install rsyslog if needed
    check_rsyslog
    
    # Configure rsyslog
    configure_rsyslog
    
    # Configure firewall
    configure_firewall
    
    # Create processing script
    create_processor_script
    
    # Create systemd service
    create_processor_service
    
    # Restart rsyslog
    restart_rsyslog
    
    # Test configuration
    test_configuration
    
    log_message "Configuration completed successfully!"
    echo ""
    echo "=== CONFIGURATION SUMMARY ==="
    echo "rsyslog configured to receive AIX logs on:"
    echo "  - UDP/TCP port $SYSLOG_PORT (syslog)"
    echo "  - TCP port $ERRPT_PORT (errpt)"
    echo ""
    echo "Log files location:"
    echo "  - Raw logs: $LOG_DIR/"
    echo "  - Processed logs: $PROCESSED_DIR/"
    echo ""
    echo "Services:"
    echo "  - rsyslog: systemctl status rsyslog"
    echo "  - log processor: systemctl status aix-log-processor.timer"
    echo ""
    echo "To test from AIX client:"
    echo "  echo '=== AIX SYSLOG DATA ===' | nc your_server_ip $SYSLOG_PORT"
    echo "  echo '=== AIX ERROR LOG DATA ===' | nc your_server_ip $ERRPT_PORT"
}

# Run main function
main "$@"
