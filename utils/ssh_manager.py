#!/usr/bin/env python3
"""
SSH Manager for AIX Data Graph
Handles SSH connections to AIX servers for log collection.
"""

import os
import sys
import logging
import time
from typing import Dict, List, Any, Optional, Tuple
from pathlib import Path
from datetime import datetime

import paramiko
from paramiko.ssh_exception import SSHException, AuthenticationException, NoValidConnectionsError

# Add the project root to Python path
sys.path.append(str(Path(__file__).parent.parent))

class SSHManager:
    """Manages SSH connections to AIX servers"""
    
    def __init__(self, config: Dict[str, Any]):
        """Initialize SSH manager with configuration"""
        self.config = config
        self.logger = logging.getLogger(__name__)
        
        # SSH configuration
        self.private_key_path = os.path.expanduser(config.get('private_key_path', '~/.ssh/id_rsa'))
        self.timeout = config.get('timeout', 30)
        self.retry_attempts = config.get('retry_attempts', 3)
        self.retry_delay = config.get('retry_delay', 5)
        
        # Connection pool
        self.connections = {}
        self.max_connections = config.get('max_concurrent_connections', 10)
        
        # Load private key
        self.private_key = self._load_private_key()
        
        self.logger.info("SSH Manager initialized")
    
    def _load_private_key(self) -> Optional[paramiko.RSAKey]:
        """Load SSH private key"""
        try:
            if os.path.exists(self.private_key_path):
                return paramiko.RSAKey.from_private_key_file(self.private_key_path)
            else:
                self.logger.warning(f"Private key not found: {self.private_key_path}")
                return None
        except Exception as e:
            self.logger.error(f"Failed to load private key: {e}")
            return None
    
    def _get_connection_key(self, server_config: Dict[str, Any]) -> str:
        """Generate a unique key for connection caching"""
        return f"{server_config['hostname']}:{server_config.get('port', 22)}:{server_config['username']}"
    
    def _create_connection(self, server_config: Dict[str, Any]) -> Optional[paramiko.SSHClient]:
        """Create a new SSH connection to an AIX server"""
        try:
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            
            # Connection parameters
            hostname = server_config['hostname']
            username = server_config['username']
            port = server_config.get('port', 22)
            
            # Connect with private key authentication
            if self.private_key:
                client.connect(
                    hostname=hostname,
                    port=port,
                    username=username,
                    pkey=self.private_key,
                    timeout=self.timeout,
                    banner_timeout=self.timeout,
                    auth_timeout=self.timeout
                )
            else:
                # Fallback to password authentication (not recommended for production)
                self.logger.warning("No private key available, connection may fail")
                client.connect(
                    hostname=hostname,
                    port=port,
                    username=username,
                    timeout=self.timeout,
                    banner_timeout=self.timeout,
                    auth_timeout=self.timeout
                )
            
            self.logger.info(f"SSH connection established to {hostname}:{port}")
            return client
            
        except AuthenticationException as e:
            self.logger.error(f"Authentication failed for {server_config['hostname']}: {e}")
            return None
        except NoValidConnectionsError as e:
            self.logger.error(f"No valid connections to {server_config['hostname']}: {e}")
            return None
        except SSHException as e:
            self.logger.error(f"SSH error connecting to {server_config['hostname']}: {e}")
            return None
        except Exception as e:
            self.logger.error(f"Unexpected error connecting to {server_config['hostname']}: {e}")
            return None
    
    def get_connection(self, server_config: Dict[str, Any]) -> Optional[paramiko.SSHClient]:
        """Get an SSH connection to an AIX server (reuse existing or create new)"""
        connection_key = self._get_connection_key(server_config)
        
        # Check if we have an existing connection
        if connection_key in self.connections:
            client = self.connections[connection_key]
            try:
                # Test if connection is still alive
                client.exec_command('echo "test"', timeout=5)
                return client
            except:
                # Connection is dead, remove it
                self.logger.debug(f"Removing dead connection to {server_config['hostname']}")
                del self.connections[connection_key]
        
        # Check connection pool size
        if len(self.connections) >= self.max_connections:
            # Close oldest connection
            oldest_key = next(iter(self.connections))
            oldest_client = self.connections[oldest_key]
            try:
                oldest_client.close()
            except:
                pass
            del self.connections[oldest_key]
            self.logger.debug("Closed oldest connection to make room for new one")
        
        # Create new connection
        client = self._create_connection(server_config)
        if client:
            self.connections[connection_key] = client
        
        return client
    
    def execute_command(self, server_config: Dict[str, Any], command: str, 
                       timeout: Optional[int] = None) -> Tuple[bool, str, str]:
        """Execute a command on an AIX server via SSH"""
        client = None
        try:
            client = self.get_connection(server_config)
            if not client:
                return False, "", f"Failed to establish SSH connection to {server_config['hostname']}"
            
            # Execute command
            cmd_timeout = timeout or self.timeout
            stdin, stdout, stderr = client.exec_command(command, timeout=cmd_timeout)
            
            # Get output
            stdout_str = stdout.read().decode('utf-8', errors='ignore').strip()
            stderr_str = stderr.read().decode('utf-8', errors='ignore').strip()
            
            # Wait for command to complete
            exit_status = stdout.channel.recv_exit_status()
            
            success = exit_status == 0
            if not success:
                self.logger.warning(f"Command failed on {server_config['hostname']} with exit code {exit_status}")
                self.logger.debug(f"Command: {command}")
                self.logger.debug(f"Stderr: {stderr_str}")
            
            return success, stdout_str, stderr_str
            
        except Exception as e:
            error_msg = f"Error executing command on {server_config['hostname']}: {e}"
            self.logger.error(error_msg)
            return False, "", error_msg
    
    def test_connection(self, server_config: Dict[str, Any]) -> bool:
        """Test SSH connection to an AIX server"""
        try:
            success, stdout, stderr = self.execute_command(
                server_config, 
                'echo "SSH connection test successful"',
                timeout=10
            )
            return success
        except Exception as e:
            self.logger.error(f"Connection test failed for {server_config['hostname']}: {e}")
            return False
    
    def collect_errpt_data(self, server_config: Dict[str, Any], 
                          time_range: str = "1h") -> List[Dict[str, Any]]:
        """Collect error report data from AIX server"""
        errpt_data = []
        
        try:
            # Build errpt command based on time range
            if time_range == "1h":
                cmd = "errpt -a -s $(date -d '1 hour ago' +%m%d%H%M%y)"
            elif time_range == "1d":
                cmd = "errpt -a -s $(date -d '1 day ago' +%m%d%H%M%y)"
            elif time_range == "1w":
                cmd = "errpt -a -s $(date -d '1 week ago' +%m%d%H%M%y)"
            else:
                cmd = "errpt -a"
            
            success, stdout, stderr = self.execute_command(server_config, cmd)
            
            if not success:
                self.logger.error(f"Failed to collect errpt data from {server_config['hostname']}: {stderr}")
                return errpt_data
            
            # Parse errpt output
            lines = stdout.split('\n')
            current_entry = {}
            
            for line in lines:
                line = line.strip()
                if not line:
                    if current_entry:
                        errpt_data.append(current_entry.copy())
                        current_entry = {}
                    continue
                
                # Parse different parts of errpt output
                if 'IDENTIFIER:' in line:
                    parts = line.split('IDENTIFIER:')
                    if len(parts) == 2:
                        current_entry['error_id'] = parts[1].strip()
                elif 'Timestamp:' in line:
                    parts = line.split('Timestamp:')
                    if len(parts) == 2:
                        current_entry['timestamp'] = parts[1].strip()
                elif 'Sequence Number:' in line:
                    parts = line.split('Sequence Number:')
                    if len(parts) == 2:
                        current_entry['sequence_number'] = parts[1].strip()
                elif 'Machine Id:' in line:
                    parts = line.split('Machine Id:')
                    if len(parts) == 2:
                        current_entry['machine_id'] = parts[1].strip()
                elif 'Node Id:' in line:
                    parts = line.split('Node Id:')
                    if len(parts) == 2:
                        current_entry['node_id'] = parts[1].strip()
                elif 'Class:' in line:
                    parts = line.split('Class:')
                    if len(parts) == 2:
                        current_entry['class'] = parts[1].strip()
                elif 'Type:' in line:
                    parts = line.split('Type:')
                    if len(parts) == 2:
                        current_entry['type'] = parts[1].strip()
                elif 'Resource Name:' in line:
                    parts = line.split('Resource Name:')
                    if len(parts) == 2:
                        current_entry['resource_name'] = parts[1].strip()
                elif 'Resource Class:' in line:
                    parts = line.split('Resource Class:')
                    if len(parts) == 2:
                        current_entry['resource_class'] = parts[1].strip()
                elif 'Resource Type:' in line:
                    parts = line.split('Resource Type:')
                    if len(parts) == 2:
                        current_entry['resource_type'] = parts[1].strip()
                elif 'Location:' in line:
                    parts = line.split('Location:')
                    if len(parts) == 2:
                        current_entry['location_code'] = parts[1].strip()
                elif 'VPD:' in line:
                    parts = line.split('VPD:')
                    if len(parts) == 2:
                        current_entry['vpd'] = parts[1].strip()
                elif 'Description:' in line:
                    parts = line.split('Description:')
                    if len(parts) == 2:
                        current_entry['description'] = parts[1].strip()
                elif 'Probable Causes:' in line:
                    parts = line.split('Probable Causes:')
                    if len(parts) == 2:
                        current_entry['probable_causes'] = parts[1].strip()
                elif 'User Causes:' in line:
                    parts = line.split('User Causes:')
                    if len(parts) == 2:
                        current_entry['user_causes'] = parts[1].strip()
                elif 'Install Causes:' in line:
                    parts = line.split('Install Causes:')
                    if len(parts) == 2:
                        current_entry['install_causes'] = parts[1].strip()
                elif 'Failure Causes:' in line:
                    parts = line.split('Failure Causes:')
                    if len(parts) == 2:
                        current_entry['failure_causes'] = parts[1].strip()
                elif 'Recommended Actions:' in line:
                    parts = line.split('Recommended Actions:')
                    if len(parts) == 2:
                        current_entry['recommended_actions'] = parts[1].strip()
                elif 'Detail Data:' in line:
                    parts = line.split('Detail Data:')
                    if len(parts) == 2:
                        current_entry['detail_data'] = parts[1].strip()
            
            # Add the last entry if exists
            if current_entry:
                errpt_data.append(current_entry)
            
            self.logger.info(f"Collected {len(errpt_data)} error report entries from {server_config['hostname']}")
            
        except Exception as e:
            self.logger.error(f"Error collecting errpt data from {server_config['hostname']}: {e}")
        
        return errpt_data
    
    def collect_syslog_data(self, server_config: Dict[str, Any], 
                           log_files: List[str] = None) -> List[Dict[str, Any]]:
        """Collect system log data from AIX server"""
        syslog_data = []
        
        if not log_files:
            log_files = [
                "/var/adm/ras/errlog",
                "/var/adm/ras/conslog",
                "/var/adm/messages"
            ]
        
        try:
            for log_file in log_files:
                # Check if file exists and is readable
                success, stdout, stderr = self.execute_command(
                    server_config,
                    f"test -r {log_file} && echo 'exists' || echo 'not_exists'"
                )
                
                if not success or 'not_exists' in stdout:
                    self.logger.debug(f"Log file {log_file} not accessible on {server_config['hostname']}")
                    continue
                
                # Get last 100 lines of the log file
                success, stdout, stderr = self.execute_command(
                    server_config,
                    f"tail -100 {log_file}"
                )
                
                if not success:
                    self.logger.warning(f"Failed to read log file {log_file} from {server_config['hostname']}")
                    continue
                
                # Parse log entries
                lines = stdout.split('\n')
                for line in lines:
                    line = line.strip()
                    if not line:
                        continue
                    
                    # Basic parsing - can be enhanced based on specific log formats
                    entry = {
                        'source': log_file,
                        'message': line,
                        'timestamp': datetime.now().isoformat(),
                        'facility': 'UNKNOWN',
                        'priority': 'UNKNOWN',
                        'process_id': '',
                        'hostname': server_config['hostname']
                    }
                    
                    # Try to extract timestamp if present
                    if line.startswith('[') and ']' in line:
                        timestamp_part = line[1:line.find(']')]
                        try:
                            # Parse AIX timestamp format
                            entry['timestamp'] = timestamp_part
                        except:
                            pass
                    
                    syslog_data.append(entry)
            
            self.logger.info(f"Collected {len(syslog_data)} system log entries from {server_config['hostname']}")
            
        except Exception as e:
            self.logger.error(f"Error collecting syslog data from {server_config['hostname']}: {e}")
        
        return syslog_data
    
    def close_all_connections(self):
        """Close all SSH connections"""
        for connection_key, client in self.connections.items():
            try:
                client.close()
                self.logger.debug(f"Closed connection: {connection_key}")
            except Exception as e:
                self.logger.warning(f"Error closing connection {connection_key}: {e}")
        
        self.connections.clear()
        self.logger.info("All SSH connections closed")
    
    def __enter__(self):
        """Context manager entry"""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.close_all_connections()

