#!/usr/bin/env python3
"""
System Log Collector for AIX Data Graph
Collects system logs from AIX servers.
"""

import sys
import logging
import re
from typing import Dict, List, Any, Optional
from pathlib import Path
from datetime import datetime

# Add the project root to Python path
sys.path.append(str(Path(__file__).parent.parent))

from utils.ssh_manager import SSHManager
from database.influxdb_manager import InfluxDBManager

class SyslogCollector:
    """Collects system logs from AIX servers"""
    
    def __init__(self, ssh_manager: SSHManager, db_manager: InfluxDBManager):
        """Initialize the system log collector"""
        self.ssh_manager = ssh_manager
        self.db_manager = db_manager
        self.logger = logging.getLogger(__name__)
        
        # Common log patterns for AIX
        self.log_patterns = {
            'aix_timestamp': r'\[(\d{2}/\d{2}/\d{4}-\d{2}:\d{2}:\d{2}:\d{3})\]',
            'aix_process': r'(\w+)\[(\d+)\]',
            'aix_facility': r'(\w+):\s*',
            'aix_priority': r'(\w+):\s*',
            'error_keywords': ['error', 'fail', 'critical', 'warning', 'panic', 'fatal'],
            'warning_keywords': ['warn', 'warning', 'notice', 'info']
        }
    
    def collect(self, server_config: Dict[str, Any]) -> Dict[str, Any]:
        """Collect system logs from an AIX server"""
        server_name = server_config['name']
        hostname = server_config['hostname']
        
        self.logger.info(f"Starting system log collection from {server_name} ({hostname})")
        
        try:
            # Collect system log data
            syslog_data = self.ssh_manager.collect_syslog_data(server_config)
            
            if not syslog_data:
                self.logger.info(f"No system logs found on {server_name}")
                return {
                    'success': True,
                    'records_collected': 0,
                    'error_message': None
                }
            
            # Process and enhance the data
            processed_data = self._process_syslog_data(syslog_data, server_config)
            
            # Write to database
            if self.db_manager.write_syslog_data(server_name, processed_data):
                self.logger.info(f"Successfully collected {len(processed_data)} system log entries from {server_name}")
                return {
                    'success': True,
                    'records_collected': len(processed_data),
                    'error_message': None
                }
            else:
                error_msg = f"Failed to write system log data to database for {server_name}"
                self.logger.error(error_msg)
                return {
                    'success': False,
                    'records_collected': 0,
                    'error_message': error_msg
                }
                
        except Exception as e:
            error_msg = f"Error collecting system logs from {server_name}: {str(e)}"
            self.logger.error(error_msg)
            return {
                'success': False,
                'records_collected': 0,
                'error_message': error_msg
            }
    
    def _process_syslog_data(self, syslog_data: List[Dict[str, Any]], 
                            server_config: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Process and enhance system log data"""
        processed_data = []
        
        for entry in syslog_data:
            # Parse the log message
            parsed_entry = self._parse_log_message(entry['message'], entry['source'])
            
            # Create processed entry
            processed_entry = {
                'source': entry['source'],
                'message': entry['message'],
                'timestamp': entry['timestamp'],
                'facility': parsed_entry.get('facility', 'UNKNOWN'),
                'priority': parsed_entry.get('priority', 'UNKNOWN'),
                'process_id': parsed_entry.get('process_id', ''),
                'hostname': server_config['hostname'],
                'server_name': server_config['name'],
                'log_level': parsed_entry.get('log_level', 'INFO'),
                'component': parsed_entry.get('component', ''),
                'error_type': parsed_entry.get('error_type', ''),
                'raw_message': entry['message']
            }
            
            # Clean up empty values
            processed_entry = {k: v for k, v in processed_entry.items() if v}
            
            processed_data.append(processed_entry)
        
        return processed_data
    
    def _parse_log_message(self, message: str, source: str) -> Dict[str, Any]:
        """Parse a log message to extract structured information"""
        parsed = {}
        
        try:
            # Extract AIX timestamp if present
            timestamp_match = re.search(self.log_patterns['aix_timestamp'], message)
            if timestamp_match:
                parsed['timestamp'] = timestamp_match.group(1)
            
            # Extract process information
            process_match = re.search(self.log_patterns['aix_process'], message)
            if process_match:
                parsed['process_name'] = process_match.group(1)
                parsed['process_id'] = process_match.group(2)
            
            # Determine facility based on source file
            parsed['facility'] = self._determine_facility(source, message)
            
            # Determine priority/severity
            parsed['priority'] = self._determine_priority(message)
            
            # Determine log level
            parsed['log_level'] = self._determine_log_level(message)
            
            # Extract component information
            parsed['component'] = self._extract_component(message, source)
            
            # Determine error type
            parsed['error_type'] = self._determine_error_type(message)
            
        except Exception as e:
            self.logger.debug(f"Error parsing log message: {e}")
        
        return parsed
    
    def _determine_facility(self, source: str, message: str) -> str:
        """Determine the facility based on source file and message content"""
        source_lower = source.lower()
        message_lower = message.lower()
        
        # Map source files to facilities
        if 'errlog' in source_lower:
            return 'SYSTEM'
        elif 'conslog' in source_lower:
            return 'CONSOLE'
        elif 'messages' in source_lower:
            return 'SYSLOG'
        elif 'authlog' in source_lower:
            return 'AUTH'
        elif 'mail' in source_lower:
            return 'MAIL'
        elif 'cron' in source_lower:
            return 'CRON'
        elif 'daemon' in source_lower:
            return 'DAEMON'
        elif 'kern' in source_lower:
            return 'KERNEL'
        elif 'user' in source_lower:
            return 'USER'
        elif 'local' in source_lower:
            return 'LOCAL'
        
        # Try to determine from message content
        if any(keyword in message_lower for keyword in ['kernel', 'driver', 'module']):
            return 'KERNEL'
        elif any(keyword in message_lower for keyword in ['auth', 'login', 'password', 'su']):
            return 'AUTH'
        elif any(keyword in message_lower for keyword in ['mail', 'smtp', 'pop', 'imap']):
            return 'MAIL'
        elif any(keyword in message_lower for keyword in ['cron', 'at', 'batch']):
            return 'CRON'
        elif any(keyword in message_lower for keyword in ['daemon', 'service', 'inetd']):
            return 'DAEMON'
        
        return 'UNKNOWN'
    
    def _determine_priority(self, message: str) -> str:
        """Determine the priority/severity of a log message"""
        message_lower = message.lower()
        
        # Check for critical/emergency keywords
        if any(keyword in message_lower for keyword in ['panic', 'fatal', 'emerg', 'emergency']):
            return 'EMERG'
        elif any(keyword in message_lower for keyword in ['alert', 'critical', 'crit']):
            return 'ALERT'
        elif any(keyword in message_lower for keyword in ['error', 'err', 'fail', 'failure']):
            return 'ERR'
        elif any(keyword in message_lower for keyword in ['warn', 'warning']):
            return 'WARNING'
        elif any(keyword in message_lower for keyword in ['notice', 'note']):
            return 'NOTICE'
        elif any(keyword in message_lower for keyword in ['info', 'information']):
            return 'INFO'
        elif any(keyword in message_lower for keyword in ['debug', 'trace']):
            return 'DEBUG'
        
        return 'UNKNOWN'
    
    def _determine_log_level(self, message: str) -> str:
        """Determine the log level of a message"""
        message_lower = message.lower()
        
        # Map priority to log level
        priority = self._determine_priority(message)
        
        priority_to_level = {
            'EMERG': 'CRITICAL',
            'ALERT': 'CRITICAL',
            'ERR': 'ERROR',
            'WARNING': 'WARNING',
            'NOTICE': 'INFO',
            'INFO': 'INFO',
            'DEBUG': 'DEBUG'
        }
        
        return priority_to_level.get(priority, 'INFO')
    
    def _extract_component(self, message: str, source: str) -> str:
        """Extract the component/system from the log message"""
        message_lower = message.lower()
        source_lower = source.lower()
        
        # Common AIX components
        aix_components = [
            'hacmp', 'vios', 'lpar', 'aix', 'power', 'ibm',
            'network', 'disk', 'memory', 'cpu', 'filesystem',
            'security', 'user', 'group', 'process', 'service'
        ]
        
        for component in aix_components:
            if component in message_lower:
                return component.upper()
        
        # Try to extract from process name if available
        process_match = re.search(self.log_patterns['aix_process'], message)
        if process_match:
            process_name = process_match.group(1).lower()
            for component in aix_components:
                if component in process_name:
                    return component.upper()
        
        return 'SYSTEM'
    
    def _determine_error_type(self, message: str) -> str:
        """Determine the type of error from the message"""
        message_lower = message.lower()
        
        # Common error types
        if any(keyword in message_lower for keyword in ['timeout', 'timed out']):
            return 'TIMEOUT'
        elif any(keyword in message_lower for keyword in ['connection refused', 'connection failed']):
            return 'CONNECTION_ERROR'
        elif any(keyword in message_lower for keyword in ['permission denied', 'access denied']):
            return 'PERMISSION_ERROR'
        elif any(keyword in message_lower for keyword in ['file not found', 'no such file']):
            return 'FILE_ERROR'
        elif any(keyword in message_lower for keyword in ['out of memory', 'memory full']):
            return 'MEMORY_ERROR'
        elif any(keyword in message_lower for keyword in ['disk full', 'no space']):
            return 'DISK_ERROR'
        elif any(keyword in message_lower for keyword in ['network unreachable', 'host unreachable']):
            return 'NETWORK_ERROR'
        elif any(keyword in message_lower for keyword in ['service not available', 'service down']):
            return 'SERVICE_ERROR'
        
        return 'GENERAL'
    
    def collect_from_specific_file(self, server_config: Dict[str, Any], 
                                 log_file: str, lines: int = 100) -> Dict[str, Any]:
        """Collect logs from a specific file on an AIX server"""
        server_name = server_config['name']
        hostname = server_config['hostname']
        
        self.logger.info(f"Collecting {lines} lines from {log_file} on {server_name} ({hostname})")
        
        try:
            # Check if file exists and is readable
            success, stdout, stderr = self.ssh_manager.execute_command(
                server_config,
                f"test -r {log_file} && echo 'exists' || echo 'not_exists'"
            )
            
            if not success or 'not_exists' in stdout:
                return {
                    'success': False,
                    'records_collected': 0,
                    'error_message': f"Log file {log_file} not accessible on {server_name}"
                }
            
            # Get specified number of lines
            success, stdout, stderr = self.ssh_manager.execute_command(
                server_config,
                f"tail -{lines} {log_file}"
            )
            
            if not success:
                return {
                    'success': False,
                    'records_collected': 0,
                    'error_message': f"Failed to read log file {log_file} from {server_name}"
                }
            
            # Parse log entries
            lines_data = stdout.split('\n')
            syslog_data = []
            
            for line in lines_data:
                line = line.strip()
                if not line:
                    continue
                
                entry = {
                    'source': log_file,
                    'message': line,
                    'timestamp': datetime.now().isoformat(),
                    'facility': 'UNKNOWN',
                    'priority': 'UNKNOWN',
                    'process_id': '',
                    'hostname': hostname
                }
                
                syslog_data.append(entry)
            
            # Process and enhance the data
            processed_data = self._process_syslog_data(syslog_data, server_config)
            
            # Write to database
            if self.db_manager.write_syslog_data(server_name, processed_data):
                self.logger.info(f"Successfully collected {len(processed_data)} log entries from {log_file} on {server_name}")
                return {
                    'success': True,
                    'records_collected': len(processed_data),
                    'error_message': None
                }
            else:
                error_msg = f"Failed to write log data to database for {server_name}"
                self.logger.error(error_msg)
                return {
                    'success': False,
                    'records_collected': 0,
                    'error_message': error_msg
                }
                
        except Exception as e:
            error_msg = f"Error collecting logs from {log_file} on {server_name}: {str(e)}"
            self.logger.error(error_msg)
            return {
                'success': False,
                'records_collected': 0,
                'error_message': error_msg
            }
    
    def get_log_summary(self, server_config: Dict[str, Any], 
                       time_range: str = "1h") -> Dict[str, Any]:
        """Get a summary of system logs for a server"""
        server_name = server_config['name']
        
        try:
            # Query database for log summary
            summary = self.db_manager.query_syslog_summary(server_name, time_range)
            
            # Group by facility and priority
            facility_counts = {}
            priority_counts = {}
            total_logs = 0
            
            for entry in summary:
                facility = entry.get('facility', 'UNKNOWN')
                priority = entry.get('priority', 'UNKNOWN')
                count = entry.get('count', 0)
                
                facility_counts[facility] = facility_counts.get(facility, 0) + count
                priority_counts[priority] = priority_counts.get(priority, 0) + count
                total_logs += count
            
            return {
                'success': True,
                'server_name': server_name,
                'time_range': time_range,
                'total_logs': total_logs,
                'facility_breakdown': facility_counts,
                'priority_breakdown': priority_counts,
                'summary_data': summary
            }
            
        except Exception as e:
            error_msg = f"Error getting log summary for {server_name}: {str(e)}"
            self.logger.error(error_msg)
            return {
                'success': False,
                'error_message': error_msg
            }
    
    def search_logs(self, server_config: Dict[str, Any], 
                   search_term: str, time_range: str = "1h") -> Dict[str, Any]:
        """Search for specific terms in system logs"""
        server_name = server_config['name']
        
        try:
            # Query database for logs containing search term
            summary = self.db_manager.query_syslog_summary(server_name, time_range)
            
            # Filter by search term (this would need to be implemented in the database layer)
            # For now, return the summary and let the application filter
            return {
                'success': True,
                'server_name': server_name,
                'search_term': search_term,
                'time_range': time_range,
                'results': summary
            }
            
        except Exception as e:
            error_msg = f"Error searching logs for {server_name}: {str(e)}"
            self.logger.error(error_msg)
            return {
                'success': False,
                'error_message': error_msg
            }
