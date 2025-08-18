#!/usr/bin/env python3
"""
Error Report Collector for AIX Data Graph
Collects error reports (errpt) from AIX servers.
"""

import sys
import logging
from typing import Dict, List, Any, Optional
from pathlib import Path

# Add the project root to Python path
sys.path.append(str(Path(__file__).parent.parent))

from utils.ssh_manager import SSHManager
from database.influxdb_manager import InfluxDBManager

class ErrptCollector:
    """Collects error reports from AIX servers"""
    
    def __init__(self, ssh_manager: SSHManager, db_manager: InfluxDBManager):
        """Initialize the error report collector"""
        self.ssh_manager = ssh_manager
        self.db_manager = db_manager
        self.logger = logging.getLogger(__name__)
    
    def collect(self, server_config: Dict[str, Any]) -> Dict[str, Any]:
        """Collect error reports from an AIX server"""
        server_name = server_config['name']
        hostname = server_config['hostname']
        
        self.logger.info(f"Starting error report collection from {server_name} ({hostname})")
        
        try:
            # Collect error report data
            errpt_data = self.ssh_manager.collect_errpt_data(server_config, time_range="1h")
            
            if not errpt_data:
                self.logger.info(f"No error reports found on {server_name}")
                return {
                    'success': True,
                    'records_collected': 0,
                    'error_message': None
                }
            
            # Process and enhance the data
            processed_data = self._process_errpt_data(errpt_data, server_config)
            
            # Write to database
            if self.db_manager.write_errpt_data(server_name, processed_data):
                self.logger.info(f"Successfully collected {len(processed_data)} error reports from {server_name}")
                return {
                    'success': True,
                    'records_collected': len(processed_data),
                    'error_message': None
                }
            else:
                error_msg = f"Failed to write error report data to database for {server_name}"
                self.logger.error(error_msg)
                return {
                    'success': False,
                    'records_collected': 0,
                    'error_message': error_msg
                }
                
        except Exception as e:
            error_msg = f"Error collecting error reports from {server_name}: {str(e)}"
            self.logger.error(error_msg)
            return {
                'success': False,
                'records_collected': 0,
                'error_message': error_msg
            }
    
    def _process_errpt_data(self, errpt_data: List[Dict[str, Any]], 
                           server_config: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Process and enhance error report data"""
        processed_data = []
        
        for entry in errpt_data:
            # Extract severity from error ID if available
            severity = self._extract_severity(entry.get('error_id', ''))
            
            # Create processed entry
            processed_entry = {
                'severity': severity,
                'error_id': entry.get('error_id', ''),
                'resource_name': entry.get('resource_name', ''),
                'description': entry.get('description', ''),
                'resource_type': entry.get('resource_type', ''),
                'resource_class': entry.get('resource_class', ''),
                'sequence_number': entry.get('sequence_number', 0),
                'machine_id': entry.get('machine_id', ''),
                'node_id': entry.get('node_id', ''),
                'class': entry.get('class', ''),
                'type': entry.get('type', ''),
                'resource_id': entry.get('resource_id', ''),
                'logical_resource_id': entry.get('logical_resource_id', ''),
                'location_code': entry.get('location_code', ''),
                'vpd': entry.get('vpd', ''),
                'timestamp': entry.get('timestamp', ''),
                'probable_causes': entry.get('probable_causes', ''),
                'user_causes': entry.get('user_causes', ''),
                'install_causes': entry.get('install_causes', ''),
                'failure_causes': entry.get('failure_causes', ''),
                'recommended_actions': entry.get('recommended_actions', ''),
                'detail_data': entry.get('detail_data', ''),
                'server_name': server_config['name'],
                'hostname': server_config['hostname']
            }
            
            # Clean up empty values
            processed_entry = {k: v for k, v in processed_entry.items() if v}
            
            processed_data.append(processed_entry)
        
        return processed_data
    
    def _extract_severity(self, error_id: str) -> str:
        """Extract severity from error ID"""
        if not error_id:
            return 'UNKNOWN'
        
        # AIX error IDs typically have severity encoded
        # This is a simplified approach - can be enhanced based on specific patterns
        try:
            # Look for severity indicators in the error ID
            if any(sev in error_id.upper() for sev in ['H', 'S', 'M', 'L']):
                for sev in ['H', 'S', 'M', 'L']:
                    if sev in error_id.upper():
                        return sev
            
            # Default severity based on error type
            if any(keyword in error_id.upper() for keyword in ['CRITICAL', 'FATAL', 'PANIC']):
                return 'H'
            elif any(keyword in error_id.upper() for keyword in ['ERROR', 'FAIL']):
                return 'S'
            elif any(keyword in error_id.upper() for keyword in ['WARN', 'WARNING']):
                return 'M'
            else:
                return 'L'
                
        except Exception:
            return 'UNKNOWN'
    
    def collect_historical(self, server_config: Dict[str, Any], 
                          time_range: str = "1d") -> Dict[str, Any]:
        """Collect historical error reports from an AIX server"""
        server_name = server_config['name']
        hostname = server_config['hostname']
        
        self.logger.info(f"Starting historical error report collection from {server_name} ({hostname}) for {time_range}")
        
        try:
            # Collect historical error report data
            errpt_data = self.ssh_manager.collect_errpt_data(server_config, time_range=time_range)
            
            if not errpt_data:
                self.logger.info(f"No historical error reports found on {server_name} for {time_range}")
                return {
                    'success': True,
                    'records_collected': 0,
                    'error_message': None
                }
            
            # Process and enhance the data
            processed_data = self._process_errpt_data(errpt_data, server_config)
            
            # Write to database
            if self.db_manager.write_errpt_data(server_name, processed_data):
                self.logger.info(f"Successfully collected {len(processed_data)} historical error reports from {server_name}")
                return {
                    'success': True,
                    'records_collected': len(processed_data),
                    'error_message': None
                }
            else:
                error_msg = f"Failed to write historical error report data to database for {server_name}"
                self.logger.error(error_msg)
                return {
                    'success': False,
                    'records_collected': 0,
                    'error_message': error_msg
                }
                
        except Exception as e:
            error_msg = f"Error collecting historical error reports from {server_name}: {str(e)}"
            self.logger.error(error_msg)
            return {
                'success': False,
                'records_collected': 0,
                'error_message': error_msg
            }
    
    def get_error_summary(self, server_config: Dict[str, Any], 
                         time_range: str = "1h") -> Dict[str, Any]:
        """Get a summary of error reports for a server"""
        server_name = server_config['name']
        
        try:
            # Query database for error summary
            summary = self.db_manager.query_errpt_summary(server_name, time_range)
            
            # Group by severity
            severity_counts = {}
            total_errors = 0
            
            for entry in summary:
                severity = entry.get('severity', 'UNKNOWN')
                count = entry.get('count', 0)
                severity_counts[severity] = severity_counts.get(severity, 0) + count
                total_errors += count
            
            return {
                'success': True,
                'server_name': server_name,
                'time_range': time_range,
                'total_errors': total_errors,
                'severity_breakdown': severity_counts,
                'summary_data': summary
            }
            
        except Exception as e:
            error_msg = f"Error getting error summary for {server_name}: {str(e)}"
            self.logger.error(error_msg)
            return {
                'success': False,
                'error_message': error_msg
            }
    
    def get_critical_errors(self, server_config: Dict[str, Any], 
                           time_range: str = "1h") -> Dict[str, Any]:
        """Get critical errors for a server"""
        server_name = server_config['name']
        
        try:
            # Query database for critical errors (H and S severity)
            summary = self.db_manager.query_errpt_summary(server_name, time_range)
            
            critical_errors = []
            for entry in summary:
                severity = entry.get('severity', '')
                if severity in ['H', 'S']:
                    critical_errors.append(entry)
            
            return {
                'success': True,
                'server_name': server_name,
                'time_range': time_range,
                'critical_error_count': len(critical_errors),
                'critical_errors': critical_errors
            }
            
        except Exception as e:
            error_msg = f"Error getting critical errors for {server_name}: {str(e)}"
            self.logger.error(error_msg)
            return {
                'success': False,
                'error_message': error_msg
            }
