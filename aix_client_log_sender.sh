#!/bin/bash

# AIX Client Script to send syslog and errpt data to Linux server
# Run on AIX systems to collect and send log data
# Date: August 25, 2025

# Exit on any error
set -e

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Configuration
SERVER_IP="192.168.1.100"  # Change this to your Linux server IP
SERVER_PORT="514"           # Default syslog port
ERRPT_PORT="515"            # Custom port for errpt data
LOG_DIR="/tmp/aix_logs"
TEMP_DIR="/tmp/aix_temp"

# Create temporary directories
mkdir -p "$LOG_DIR"
mkdir -p "$TEMP_DIR"

# Function to get AIX system information
get_system_info() {
    log_message "Collecting system information..."
    
    # Get hostname
    HOSTNAME=$(hostname)
    
    # Get AIX version
    AIX_VERSION=$(oslevel -s 2>/dev/null || echo "Unknown")
    
    # Get system model
    SYSTEM_MODEL=$(uname -M 2>/dev/null || echo "Unknown")
    
    # Get IP address
    IP_ADDRESS=$(ifconfig -a | grep "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}' || echo "Unknown")
    
    log_message "System: $HOSTNAME ($IP_ADDRESS) - AIX $AIX_VERSION on $SYSTEM_MODEL"
}

# Function to collect and send syslog data
collect_syslog() {
    log_message "Collecting syslog data..."
    
    # Create syslog data with system info header
    cat > "$TEMP_DIR/syslog_data.txt" << EOF
=== AIX SYSLOG DATA ===
Hostname: $HOSTNAME
IP Address: $IP_ADDRESS
AIX Version: $AIX_VERSION
System Model: $SYSTEM_MODEL
Collection Time: $(date '+%Y-%m-%d %H:%M:%S')
=== SYSLOG ENTRIES ===
EOF
    
    # Collect recent syslog entries (last 1000 lines)
    if [ -f "/var/adm/syslog" ]; then
        tail -1000 /var/adm/syslog >> "$TEMP_DIR/syslog_data.txt" 2>/dev/null || true
    fi
    
    # Collect from other common log locations
    for logfile in /var/adm/messages /var/adm/ras/errlog /var/adm/ras/trcfile; do
        if [ -f "$logfile" ]; then
            echo "=== $logfile ===" >> "$TEMP_DIR/syslog_data.txt"
            tail -500 "$logfile" >> "$TEMP_DIR/syslog_data.txt" 2>/dev/null || true
        fi
    done
    
    # Send syslog data to server
    if [ -s "$TEMP_DIR/syslog_data.txt" ]; then
        log_message "Sending syslog data to $SERVER_IP:$SERVER_PORT..."
        cat "$TEMP_DIR/syslog_data.txt" | nc "$SERVER_IP" "$SERVER_PORT" 2>/dev/null || \
        cat "$TEMP_DIR/syslog_data.txt" | telnet "$SERVER_IP" "$SERVER_PORT" 2>/dev/null || \
        log_message "WARNING: Could not send syslog data (nc/telnet not available)"
    else
        log_message "No syslog data to send"
    fi
}

# Function to collect and categorize errpt data
collect_errpt() {
    log_message "Collecting errpt (error log) data..."
    
    # Create errpt data with system info header
    cat > "$TEMP_DIR/errpt_data.txt" << EOF
=== AIX ERROR LOG DATA ===
Hostname: $HOSTNAME
IP Address: $IP_ADDRESS
AIX Version: $AIX_VERSION
System Model: $SYSTEM_MODEL
Collection Time: $(date '+%Y-%m-%d %H:%M:%S')
=== ERROR LOG ENTRIES ===
EOF
    
    # Collect error log entries
    if command -v errpt >/dev/null 2>&1; then
        # Get recent error log entries
        errpt -a >> "$TEMP_DIR/errpt_data.txt" 2>/dev/null || true
        
        # Also get error summary by type
        echo "=== ERROR SUMMARY BY TYPE ===" >> "$TEMP_DIR/errpt_data.txt"
        errpt -d H,S,O,U | head -50 >> "$TEMP_DIR/errpt_data.txt" 2>/dev/null || true
    else
        log_message "WARNING: errpt command not available"
    fi
    
    # Send errpt data to server
    if [ -s "$TEMP_DIR/errpt_data.txt" ]; then
        log_message "Sending errpt data to $SERVER_IP:$ERRPT_PORT..."
        cat "$TEMP_DIR/errpt_data.txt" | nc "$SERVER_IP" "$ERRPT_PORT" 2>/dev/null || \
        cat "$TEMP_DIR/errpt_data.txt" | telnet "$SERVER_IP" "$ERRPT_PORT" 2>/dev/null || \
        log_message "WARNING: Could not send errpt data (nc/telnet not available)"
    else
        log_message "No errpt data to send"
    fi
}

# Function to collect system performance data
collect_performance() {
    log_message "Collecting system performance data..."
    
    cat > "$TEMP_DIR/performance_data.txt" << EOF
=== AIX PERFORMANCE DATA ===
Hostname: $HOSTNAME
IP Address: $IP_ADDRESS
Collection Time: $(date '+%Y-%m-%d %H:%M:%S')
=== PERFORMANCE METRICS ===
EOF
    
    # CPU usage
    echo "=== CPU USAGE ===" >> "$TEMP_DIR/performance_data.txt"
    vmstat 1 3 | tail -3 >> "$TEMP_DIR/performance_data.txt" 2>/dev/null || true
    
    # Memory usage
    echo "=== MEMORY USAGE ===" >> "$TEMP_DIR/performance_data.txt"
    svmon -G | head -10 >> "$TEMP_DIR/performance_data.txt" 2>/dev/null || true
    
    # Disk usage
    echo "=== DISK USAGE ===" >> "$TEMP_DIR/performance_data.txt"
    df -k | head -10 >> "$TEMP_DIR/performance_data.txt" 2>/dev/null || true
    
    # Network interfaces
    echo "=== NETWORK INTERFACES ===" >> "$TEMP_DIR/performance_data.txt"
    netstat -i | head -10 >> "$TEMP_DIR/performance_data.txt" 2>/dev/null || true
    
    # Send performance data
    if [ -s "$TEMP_DIR/performance_data.txt" ]; then
        log_message "Sending performance data to $SERVER_IP:$SERVER_PORT..."
        cat "$TEMP_DIR/performance_data.txt" | nc "$SERVER_IP" "$SERVER_PORT" 2>/dev/null || \
        cat "$TEMP_DIR/performance_data.txt" | telnet "$SERVER_IP" "$SERVER_PORT" 2>/dev/null || \
        log_message "WARNING: Could not send performance data"
    fi
}

# Function to test connectivity
test_connectivity() {
    log_message "Testing connectivity to server $SERVER_IP..."
    
    # Test basic connectivity
    if ping -c 1 "$SERVER_IP" >/dev/null 2>&1; then
        log_message "SUCCESS: Server $SERVER_IP is reachable"
        return 0
    else
        log_message "ERROR: Cannot reach server $SERVER_IP"
        return 1
    fi
}

# Function to create cron job for automated collection
setup_automation() {
    log_message "Setting up automated collection..."
    
    # Create a simple script for cron
    cat > "$LOG_DIR/collect_logs.sh" << 'EOF'
#!/bin/bash
# Automated log collection script
cd /tmp/aix_logs
./aix_client_log_sender.sh >> collect.log 2>&1
EOF
    
    chmod +x "$LOG_DIR/collect_logs.sh"
    
    log_message "To set up automated collection, add to crontab:"
    log_message "crontab -e"
    log_message "Add line: 0 */6 * * * /tmp/aix_logs/collect_logs.sh"
    log_message "This will collect logs every 6 hours"
}

# Main execution
main() {
    log_message "Starting AIX log collection and transmission..."
    
    # Get system information
    get_system_info
    
    # Test connectivity
    if ! test_connectivity; then
        log_message "ERROR: Cannot connect to server. Exiting."
        exit 1
    fi
    
    # Collect and send data
    collect_syslog
    collect_errpt
    collect_performance
    
    # Clean up temporary files
    rm -rf "$TEMP_DIR"
    
    log_message "Log collection and transmission completed."
    
    # Offer to set up automation
    echo ""
    echo "=== AUTOMATION SETUP ==="
    echo "Would you like to set up automated log collection? (y/n)"
    read -r response
    if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
        setup_automation
    fi
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_message "WARNING: This script should be run as root for complete access to system logs"
fi

# Run main function
main "$@"
