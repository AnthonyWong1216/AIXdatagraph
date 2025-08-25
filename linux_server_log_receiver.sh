#!/bin/bash

# Linux Server Script to receive and process AIX log data
# Receives syslog and errpt data from AIX clients and stores in InfluxDB
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

# Function to test netcat syntax
test_netcat() {
    log_message "Testing netcat syntax..."
    
    # Test different netcat syntax options
    if timeout 2 nc -l 9999 >/dev/null 2>&1 & then
        NC_SYNTAX="nc -l"
        kill %1 2>/dev/null
        log_message "SUCCESS: Using 'nc -l' syntax"
        return 0
    elif timeout 2 nc -l -p 9999 >/dev/null 2>&1 & then
        NC_SYNTAX="nc -l -p"
        kill %1 2>/dev/null
        log_message "SUCCESS: Using 'nc -l -p' syntax"
        return 0
    elif timeout 2 netcat -l 9999 >/dev/null 2>&1 & then
        NC_SYNTAX="netcat -l"
        kill %1 2>/dev/null
        log_message "SUCCESS: Using 'netcat -l' syntax"
        return 0
    elif timeout 2 netcat -l -p 9999 >/dev/null 2>&1 & then
        NC_SYNTAX="netcat -l -p"
        kill %1 2>/dev/null
        log_message "SUCCESS: Using 'netcat -l -p' syntax"
        return 0
    else
        log_message "ERROR: No working netcat syntax found"
        return 1
    fi
}

# Function to start network listeners
start_listeners() {
    log_message "Starting network listeners for AIX log data..."
    
    # Test netcat syntax first
    if ! test_netcat; then
        log_message "ERROR: Cannot start listeners - netcat not working"
        return 1
    fi
    
    # Start syslog listener in background
    log_message "Starting syslog listener on port $SYSLOG_PORT..."
    (
        while true; do
            $NC_SYNTAX "$SYSLOG_PORT" >> "$LOG_DIR/syslog_raw.log" 2>/dev/null || \
            log_message "WARNING: syslog listener failed"
            sleep 1
        done
    ) &
    SYSLOG_PID=$!
    
    # Start errpt listener in background
    log_message "Starting errpt listener on port $ERRPT_PORT..."
    (
        while true; do
            $NC_SYNTAX "$ERRPT_PORT" >> "$LOG_DIR/errpt_raw.log" 2>/dev/null || \
            log_message "WARNING: errpt listener failed"
            sleep 1
        done
    ) &
    ERRPT_PID=$!
    
    log_message "Listeners started with PIDs: syslog=$SYSLOG_PID, errpt=$ERRPT_PID"
}

# Function to parse and categorize errpt data
parse_errpt_data() {
    local input_file="$1"
    local output_file="$2"
    
    if [ ! -f "$input_file" ] || [ ! -s "$input_file" ]; then
        return
    fi
    
    log_message "Parsing errpt data from $input_file..."
    
    # Extract system information
    local hostname=$(grep "Hostname:" "$input_file" | head -1 | cut -d: -f2 | xargs)
    local ip_address=$(grep "IP Address:" "$input_file" | head -1 | cut -d: -f2 | xargs)
    local collection_time=$(grep "Collection Time:" "$input_file" | head -1 | cut -d: -f2- | xargs)
    
    # Parse error log entries
    local temp_file=$(mktemp)
    
    # Extract error entries (lines between === ERROR LOG ENTRIES === and === ERROR SUMMARY ===)
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
    
    log_message "Parsed errpt data saved to $output_file"
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
    else
        log_message "WARNING: curl not available for InfluxDB insertion"
    fi
}

# Function to process and store errpt data in InfluxDB
process_errpt_for_influxdb() {
    local input_file="$1"
    
    if [ ! -f "$input_file" ] || [ ! -s "$input_file" ]; then
        return
    fi
    
    log_message "Processing errpt data for InfluxDB storage..."
    
    # Extract system information
    local hostname=$(grep "Hostname:" "$input_file" | head -1 | cut -d: -f2 | xargs)
    local ip_address=$(grep "IP Address:" "$input_file" | head -1 | cut -d: -f2 | xargs)
    local collection_time=$(grep "Collection Time:" "$input_file" | head -1 | cut -d: -f2- | xargs)
    
    # Convert collection time to timestamp
    local timestamp=$(date -d "$collection_time" +%s)000000000 2>/dev/null || \
                     $(date +%s)000000000
    
    # Extract error counts
    local hardware_errors=$(grep "Hardware Errors:" "$input_file" | cut -d: -f2 | xargs)
    local software_errors=$(grep "Software Errors:" "$input_file" | cut -d: -f2 | xargs)
    local operator_errors=$(grep "Operator Errors:" "$input_file" | cut -d: -f2 | xargs)
    local unknown_errors=$(grep "Unknown Errors:" "$input_file" | cut -d: -f2 | xargs)
    local total_errors=$(grep "Total Errors:" "$input_file" | cut -d: -f2 | xargs)
    
    # Insert into InfluxDB
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
    
    if [ -n "$total_errors" ] && [ "$total_errors" -ge 0 ]; then
        insert_to_influxdb "errors" "$hostname" "$ip_address" "$timestamp" "$total_errors" "total"
    fi
    
    log_message "Errpt data inserted into InfluxDB for $hostname"
}

# Function to process log files
process_logs() {
    log_message "Processing received log files..."
    
    # Process syslog data
    if [ -f "$LOG_DIR/syslog_raw.log" ] && [ -s "$LOG_DIR/syslog_raw.log" ]; then
        log_message "Processing syslog data..."
        
        # Split syslog data by system
        awk '/=== AIX SYSLOG DATA ===/{filename="'$PROCESSED_DIR'/syslog_" ++count ".txt"} {print > filename}' "$LOG_DIR/syslog_raw.log"
        
        # Process each syslog file
        for file in "$PROCESSED_DIR"/syslog_*.txt; do
            if [ -f "$file" ]; then
                log_message "Processed syslog file: $file"
                # Move to processed directory with timestamp
                mv "$file" "$PROCESSED_DIR/syslog_$(date +%Y%m%d_%H%M%S)_$(basename "$file")"
            fi
        done
        
        # Clear processed data
        > "$LOG_DIR/syslog_raw.log"
    fi
    
    # Process errpt data
    if [ -f "$LOG_DIR/errpt_raw.log" ] && [ -s "$LOG_DIR/errpt_raw.log" ]; then
        log_message "Processing errpt data..."
        
        # Split errpt data by system
        awk '/=== AIX ERROR LOG DATA ===/{filename="'$PROCESSED_DIR'/errpt_" ++count ".txt"} {print > filename}' "$LOG_DIR/errpt_raw.log"
        
        # Process each errpt file
        for file in "$PROCESSED_DIR"/errpt_*.txt; do
            if [ -f "$file" ]; then
                # Parse and categorize
                parse_errpt_data "$file" "${file%.txt}_parsed.txt"
                
                # Store in InfluxDB
                process_errpt_for_influxdb "${file%.txt}_parsed.txt"
                
                log_message "Processed errpt file: $file"
                # Move to processed directory with timestamp
                mv "$file" "$PROCESSED_DIR/errpt_$(date +%Y%m%d_%H%M%S)_$(basename "$file")"
                mv "${file%.txt}_parsed.txt" "$PROCESSED_DIR/errpt_$(date +%Y%m%d_%H%M%S)_$(basename "${file%.txt}_parsed.txt")"
            fi
        done
        
        # Clear processed data
        > "$LOG_DIR/errpt_raw.log"
    fi
}

# Function to check InfluxDB connectivity
check_influxdb() {
    log_message "Checking InfluxDB connectivity..."
    
    if command -v curl >/dev/null 2>&1; then
        if curl -s "http://${INFLUXDB_HOST}:${INFLUXDB_PORT}/ping" >/dev/null 2>&1; then
            log_message "SUCCESS: InfluxDB is accessible"
            return 0
        else
            log_message "ERROR: Cannot connect to InfluxDB at ${INFLUXDB_HOST}:${INFLUXDB_PORT}"
            return 1
        fi
    else
        log_message "WARNING: curl not available, cannot test InfluxDB connectivity"
        return 1
    fi
}

# Function to create systemd service
create_systemd_service() {
    log_message "Creating systemd service for log receiver..."
    
    cat > /etc/systemd/system/aix-log-receiver.service << EOF
[Unit]
Description=AIX Log Receiver Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=$(readlink -f "$0")
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable aix-log-receiver.service
    
    log_message "Systemd service created and enabled"
    log_message "To start: systemctl start aix-log-receiver.service"
    log_message "To stop: systemctl stop aix-log-receiver.service"
    log_message "To check status: systemctl status aix-log-receiver.service"
}

# Function to show statistics
show_statistics() {
    log_message "=== LOG RECEIVER STATISTICS ==="
    echo "Processed syslog files: $(ls -1 "$PROCESSED_DIR"/syslog_*.txt 2>/dev/null | wc -l)"
    echo "Processed errpt files: $(ls -1 "$PROCESSED_DIR"/errpt_*.txt 2>/dev/null | wc -l)"
    echo "Total processed files: $(ls -1 "$PROCESSED_DIR"/*.txt 2>/dev/null | wc -l)"
    echo ""
    echo "Recent syslog files:"
    ls -lt "$PROCESSED_DIR"/syslog_*.txt 2>/dev/null | head -5 || echo "No syslog files found"
    echo ""
    echo "Recent errpt files:"
    ls -lt "$PROCESSED_DIR"/errpt_*.txt 2>/dev/null | head -5 || echo "No errpt files found"
}

# Main execution
main() {
    log_message "Starting AIX log receiver service..."
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_message "ERROR: This script must be run as root for port binding"
        exit 1
    fi
    
    # Check InfluxDB connectivity
    if ! check_influxdb; then
        log_message "WARNING: InfluxDB not available, data will not be stored in database"
    fi
    
    # Start listeners
    start_listeners
    
    # Main processing loop
    log_message "Entering main processing loop..."
    while true; do
        # Process logs every 30 seconds
        process_logs
        
        # Show statistics every 5 minutes
        if [ $(( $(date +%s) % 300 )) -eq 0 ]; then
            show_statistics
        fi
        
        sleep 30
    done
}

# Handle script arguments
case "${1:-}" in
    "install")
        create_systemd_service
        ;;
    "stats")
        show_statistics
        ;;
    "process")
        process_logs
        ;;
    *)
        main "$@"
        ;;
esac
