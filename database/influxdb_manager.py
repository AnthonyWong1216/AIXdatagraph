#!/usr/bin/env python3
"""
InfluxDB Manager for AIX Data Graph
Handles database operations for storing AIX log data in InfluxDB.
"""

import os
import sys
import logging
from datetime import datetime
from typing import Dict, List, Any, Optional
from pathlib import Path

from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import SYNCHRONOUS
from influxdb_client.client.query_api import QueryApi

# Add the project root to Python path
sys.path.append(str(Path(__file__).parent.parent))

class InfluxDBManager:
    """Manages InfluxDB operations for AIX log data"""
    
    def __init__(self, config: Dict[str, Any]):
        """Initialize InfluxDB manager with configuration"""
        self.config = config
        self.logger = logging.getLogger(__name__)
        
        # InfluxDB connection parameters
        self.url = config['influxdb']['url']
        self.token = config['influxdb']['token']
        self.org = config['influxdb']['org']
        self.bucket = config['influxdb']['bucket']
        
        # Initialize client
        self.client = None
        self.write_api = None
        self.query_api = None
        
        # Performance settings
        self.batch_size = config.get('performance', {}).get('batch_size', 1000)
        self.flush_interval = config.get('performance', {}).get('flush_interval', 10)
        
        # Initialize connection
        self._connect()
    
    def _connect(self):
        """Establish connection to InfluxDB"""
        try:
            self.client = InfluxDBClient(
                url=self.url,
                token=self.token,
                org=self.org,
                timeout=30_000
            )
            
            # Test connection
            health = self.client.health()
            if health.status == 'pass':
                self.logger.info("InfluxDB connection established successfully")
            else:
                self.logger.warning(f"InfluxDB health check: {health.status}")
            
            # Initialize APIs
            self.write_api = self.client.write_api(write_options=SYNCHRONOUS)
            self.query_api = self.client.query_api()
            
        except Exception as e:
            self.logger.error(f"Failed to connect to InfluxDB: {e}")
            raise
    
    def write_errpt_data(self, server_name: str, errpt_data: List[Dict[str, Any]]) -> bool:
        """Write error report data to InfluxDB"""
        try:
            points = []
            
            for entry in errpt_data:
                point = Point("errpt") \
                    .tag("server_name", server_name) \
                    .tag("severity", entry.get('severity', 'UNKNOWN')) \
                    .tag("error_id", entry.get('error_id', '')) \
                    .tag("resource_name", entry.get('resource_name', '')) \
                    .field("count", 1) \
                    .field("description", entry.get('description', '')) \
                    .field("resource_type", entry.get('resource_type', '')) \
                    .field("resource_class", entry.get('resource_class', '')) \
                    .field("sequence_number", entry.get('sequence_number', 0)) \
                    .field("machine_id", entry.get('machine_id', '')) \
                    .field("node_id", entry.get('node_id', '')) \
                    .field("class", entry.get('class', '')) \
                    .field("type", entry.get('type', '')) \
                    .field("resource_id", entry.get('resource_id', '')) \
                    .field("logical_resource_id", entry.get('logical_resource_id', '')) \
                    .field("location_code", entry.get('location_code', '')) \
                    .field("vpd", entry.get('vpd', '')) \
                    .time(datetime.now())
                
                points.append(point)
            
            if points:
                self.write_api.write(bucket=self.bucket, record=points)
                self.logger.info(f"Written {len(points)} error report entries for {server_name}")
                return True
            
        except Exception as e:
            self.logger.error(f"Failed to write error report data for {server_name}: {e}")
            return False
        
        return True
    
    def write_syslog_data(self, server_name: str, syslog_data: List[Dict[str, Any]]) -> bool:
        """Write system log data to InfluxDB"""
        try:
            points = []
            
            for entry in syslog_data:
                point = Point("syslog") \
                    .tag("server_name", server_name) \
                    .tag("facility", entry.get('facility', 'UNKNOWN')) \
                    .tag("priority", entry.get('priority', 'UNKNOWN')) \
                    .tag("source", entry.get('source', '')) \
                    .field("count", 1) \
                    .field("message", entry.get('message', '')) \
                    .field("timestamp", entry.get('timestamp', '')) \
                    .field("process_id", entry.get('process_id', '')) \
                    .field("hostname", entry.get('hostname', '')) \
                    .time(datetime.now())
                
                points.append(point)
            
            if points:
                self.write_api.write(bucket=self.bucket, record=points)
                self.logger.info(f"Written {len(points)} system log entries for {server_name}")
                return True
            
        except Exception as e:
            self.logger.error(f"Failed to write system log data for {server_name}: {e}")
            return False
        
        return True
    
    def write_collection_stats(self, server_name: str, stats: Dict[str, Any]) -> bool:
        """Write collection statistics to InfluxDB"""
        try:
            point = Point("collection_stats") \
                .tag("server_name", server_name) \
                .field("success", 1 if stats.get('success', False) else 0) \
                .field("records_collected", stats.get('records_collected', 0)) \
                .field("execution_time", stats.get('execution_time', 0.0)) \
                .field("success_rate", stats.get('success_rate', 0.0)) \
                .field("error_count", stats.get('error_count', 0)) \
                .time(datetime.now())
            
            self.write_api.write(bucket=self.bucket, record=point)
            self.logger.debug(f"Written collection stats for {server_name}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to write collection stats for {server_name}: {e}")
            return False
    
    def query_errpt_summary(self, server_name: Optional[str] = None, 
                           time_range: str = "1h") -> List[Dict[str, Any]]:
        """Query error report summary data"""
        try:
            query = f'''
            from(bucket: "{self.bucket}")
                |> range(start: -{time_range})
                |> filter(fn: (r) => r["_measurement"] == "errpt")
                |> filter(fn: (r) => r["_field"] == "count")
            '''
            
            if server_name:
                query += f'|> filter(fn: (r) => r["server_name"] == "{server_name}")'
            
            query += '''
                |> group(columns: ["server_name", "severity"])
                |> sum()
                |> yield(name: "summary")
            '''
            
            result = self.query_api.query(query)
            
            summary = []
            for table in result:
                for record in table.records:
                    summary.append({
                        'server_name': record.values.get('server_name', ''),
                        'severity': record.values.get('severity', ''),
                        'count': record.get_value(),
                        'timestamp': record.get_time()
                    })
            
            return summary
            
        except Exception as e:
            self.logger.error(f"Failed to query error report summary: {e}")
            return []
    
    def query_syslog_summary(self, server_name: Optional[str] = None, 
                            time_range: str = "1h") -> List[Dict[str, Any]]:
        """Query system log summary data"""
        try:
            query = f'''
            from(bucket: "{self.bucket}")
                |> range(start: -{time_range})
                |> filter(fn: (r) => r["_measurement"] == "syslog")
                |> filter(fn: (r) => r["_field"] == "count")
            '''
            
            if server_name:
                query += f'|> filter(fn: (r) => r["server_name"] == "{server_name}")'
            
            query += '''
                |> group(columns: ["server_name", "facility"])
                |> sum()
                |> yield(name: "summary")
            '''
            
            result = self.query_api.query(query)
            
            summary = []
            for table in result:
                for record in table.records:
                    summary.append({
                        'server_name': record.values.get('server_name', ''),
                        'facility': record.values.get('facility', ''),
                        'count': record.get_value(),
                        'timestamp': record.get_time()
                    })
            
            return summary
            
        except Exception as e:
            self.logger.error(f"Failed to query system log summary: {e}")
            return []
    
    def get_server_list(self) -> List[str]:
        """Get list of servers with data in the database"""
        try:
            query = f'''
            from(bucket: "{self.bucket}")
                |> range(start: -30d)
                |> filter(fn: (r) => r["_measurement"] == "errpt" or r["_measurement"] == "syslog")
                |> group(columns: ["server_name"])
                |> distinct(column: "server_name")
                |> yield(name: "servers")
            '''
            
            result = self.query_api.query(query)
            
            servers = []
            for table in result:
                for record in table.records:
                    server_name = record.values.get('server_name', '')
                    if server_name and server_name not in servers:
                        servers.append(server_name)
            
            return servers
            
        except Exception as e:
            self.logger.error(f"Failed to get server list: {e}")
            return []
    
    def cleanup_old_data(self, retention_days: int = 30) -> bool:
        """Clean up old data based on retention policy"""
        try:
            # Note: InfluxDB handles retention automatically via bucket policies
            # This method is for manual cleanup if needed
            self.logger.info(f"Data retention is handled automatically by InfluxDB bucket policy")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to cleanup old data: {e}")
            return False
    
    def close(self):
        """Close InfluxDB connection"""
        try:
            if self.write_api:
                self.write_api.close()
            if self.client:
                self.client.close()
            self.logger.info("InfluxDB connection closed")
        except Exception as e:
            self.logger.error(f"Error closing InfluxDB connection: {e}")
    
    def __enter__(self):
        """Context manager entry"""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit"""
        self.close()
