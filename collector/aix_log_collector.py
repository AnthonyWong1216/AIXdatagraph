#!/usr/bin/env python3
"""
AIX Log Collector
Collects error reports (errpt) and system logs from AIX servers via SSH
and stores them in InfluxDB for visualization in Grafana.
"""

import os
import sys
import time
import logging
import yaml
import json
import schedule
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from dataclasses import dataclass
from pathlib import Path

import paramiko
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import SYNCHRONOUS
import structlog

# Add the project root to Python path
sys.path.append(str(Path(__file__).parent.parent))

from config.config_loader import ConfigLoader
from collectors.errpt_collector import ErrptCollector
from collectors.syslog_collector import SyslogCollector
from database.influxdb_manager import InfluxDBManager
from utils.ssh_manager import SSHManager
from utils.logger import setup_logging

@dataclass
class CollectionResult:
    """Result of a log collection operation"""
    server_name: str
    collection_type: str
    success: bool
    records_collected: int
    error_message: Optional[str] = None
    execution_time: float = 0.0

class AIXLogCollector:
    """Main class for collecting AIX server logs"""
    
    def __init__(self, config_path: str = "config/config.yaml"):
        """Initialize the AIX log collector"""
        self.config = ConfigLoader(config_path).load()
        self.logger = setup_logging(self.config['logging'])
        self.ssh_manager = SSHManager(self.config['ssh'])
        self.db_manager = InfluxDBManager(self.config['database'])
        
        # Initialize collectors
        self.errpt_collector = ErrptCollector(self.ssh_manager, self.db_manager)
        self.syslog_collector = SyslogCollector(self.ssh_manager, self.db_manager)
        
        # Statistics
        self.stats = {
            'total_collections': 0,
            'successful_collections': 0,
            'failed_collections': 0,
            'total_records': 0,
            'last_collection': None
        }
        
        self.logger.info("AIX Log Collector initialized", config_path=config_path)
    
    def collect_from_server(self, server_config: Dict[str, Any]) -> List[CollectionResult]:
        """Collect logs from a single AIX server"""
        results = []
        server_name = server_config['name']
        hostname = server_config['hostname']
        
        self.logger.info("Starting collection from server", server=server_name, hostname=hostname)
        
        try:
            # Test SSH connection
            if not self.ssh_manager.test_connection(server_config):
                error_msg = f"SSH connection failed to {hostname}"
                self.logger.error(error_msg, server=server_name)
                results.append(CollectionResult(
                    server_name=server_name,
                    collection_type="connection_test",
                    success=False,
                    records_collected=0,
                    error_message=error_msg
                ))
                return results
            
            # Collect error reports
            if self.config['collection']['errpt']['enabled']:
                start_time = time.time()
                try:
                    errpt_result = self.errpt_collector.collect(server_config)
                    execution_time = time.time() - start_time
                    
                    results.append(CollectionResult(
                        server_name=server_name,
                        collection_type="errpt",
                        success=errpt_result['success'],
                        records_collected=errpt_result['records_collected'],
                        error_message=errpt_result.get('error_message'),
                        execution_time=execution_time
                    ))
                    
                    if errpt_result['success']:
                        self.stats['total_records'] += errpt_result['records_collected']
                        self.logger.info("Error report collection successful", 
                                       server=server_name, 
                                       records=errpt_result['records_collected'])
                    else:
                        self.logger.error("Error report collection failed", 
                                        server=server_name, 
                                        error=errpt_result.get('error_message'))
                        
                except Exception as e:
                    self.logger.error("Exception during error report collection", 
                                    server=server_name, error=str(e))
                    results.append(CollectionResult(
                        server_name=server_name,
                        collection_type="errpt",
                        success=False,
                        records_collected=0,
                        error_message=str(e)
                    ))
            
            # Collect system logs
            if self.config['collection']['syslog']['enabled']:
                start_time = time.time()
                try:
                    syslog_result = self.syslog_collector.collect(server_config)
                    execution_time = time.time() - start_time
                    
                    results.append(CollectionResult(
                        server_name=server_name,
                        collection_type="syslog",
                        success=syslog_result['success'],
                        records_collected=syslog_result['records_collected'],
                        error_message=syslog_result.get('error_message'),
                        execution_time=execution_time
                    ))
                    
                    if syslog_result['success']:
                        self.stats['total_records'] += syslog_result['records_collected']
                        self.logger.info("System log collection successful", 
                                       server=server_name, 
                                       records=syslog_result['records_collected'])
                    else:
                        self.logger.error("System log collection failed", 
                                        server=server_name, 
                                        error=syslog_result.get('error_message'))
                        
                except Exception as e:
                    self.logger.error("Exception during system log collection", 
                                    server=server_name, error=str(e))
                    results.append(CollectionResult(
                        server_name=server_name,
                        collection_type="syslog",
                        success=False,
                        records_collected=0,
                        error_message=str(e)
                    ))
                    
        except Exception as e:
            self.logger.error("Unexpected error during collection", 
                            server=server_name, error=str(e))
            results.append(CollectionResult(
                server_name=server_name,
                collection_type="general",
                success=False,
                records_collected=0,
                error_message=str(e)
            ))
        
        return results
    
    def collect_all_servers(self) -> List[CollectionResult]:
        """Collect logs from all configured AIX servers"""
        all_results = []
        start_time = time.time()
        
        self.logger.info("Starting collection from all servers", 
                        server_count=len(self.config['aix_servers']))
        
        for server_config in self.config['aix_servers']:
            try:
                results = self.collect_from_server(server_config)
                all_results.extend(results)
                
                # Update statistics
                for result in results:
                    self.stats['total_collections'] += 1
                    if result.success:
                        self.stats['successful_collections'] += 1
                    else:
                        self.stats['failed_collections'] += 1
                        
            except Exception as e:
                self.logger.error("Failed to collect from server", 
                                server=server_config.get('name', 'unknown'), 
                                error=str(e))
                all_results.append(CollectionResult(
                    server_name=server_config.get('name', 'unknown'),
                    collection_type="general",
                    success=False,
                    records_collected=0,
                    error_message=str(e)
                ))
                self.stats['failed_collections'] += 1
        
        total_time = time.time() - start_time
        self.stats['last_collection'] = datetime.now()
        
        self.logger.info("Collection completed", 
                        total_time=total_time,
                        total_results=len(all_results),
                        successful=self.stats['successful_collections'],
                        failed=self.stats['failed_collections'])
        
        return all_results
    
    def run_scheduled_collection(self):
        """Run the scheduled collection process"""
        self.logger.info("Running scheduled collection")
        try:
            results = self.collect_all_servers()
            
            # Log summary
            successful = sum(1 for r in results if r.success)
            total_records = sum(r.records_collected for r in results if r.success)
            
            self.logger.info("Scheduled collection completed", 
                            successful=successful,
                            total=len(results),
                            total_records=total_records)
                            
        except Exception as e:
            self.logger.error("Scheduled collection failed", error=str(e))
    
    def start_scheduler(self):
        """Start the scheduled collection process"""
        self.logger.info("Starting scheduled collection")
        
        # Schedule error report collection
        errpt_interval = self.config['collection']['errpt_interval']
        schedule.every(errpt_interval).seconds.do(self.run_scheduled_collection)
        
        # Schedule system log collection (more frequent)
        syslog_interval = self.config['collection']['syslog_interval']
        schedule.every(syslog_interval).seconds.do(self.run_scheduled_collection)
        
        self.logger.info("Scheduler started", 
                        errpt_interval=errpt_interval,
                        syslog_interval=syslog_interval)
        
        try:
            while True:
                schedule.run_pending()
                time.sleep(1)
        except KeyboardInterrupt:
            self.logger.info("Scheduler stopped by user")
        except Exception as e:
            self.logger.error("Scheduler error", error=str(e))
    
    def get_stats(self) -> Dict[str, Any]:
        """Get current collection statistics"""
        return self.stats.copy()

def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description="AIX Log Collector")
    parser.add_argument("--config", "-c", default="config/config.yaml", 
                       help="Configuration file path")
    parser.add_argument("--once", action="store_true", 
                       help="Run collection once and exit")
    parser.add_argument("--daemon", action="store_true", 
                       help="Run as daemon with scheduler")
    
    args = parser.parse_args()
    
    try:
        collector = AIXLogCollector(args.config)
        
        if args.once:
            # Run collection once
            results = collector.collect_all_servers()
            print(f"Collection completed: {len(results)} results")
            for result in results:
                status = "SUCCESS" if result.success else "FAILED"
                print(f"  {result.server_name} ({result.collection_type}): {status}")
        else:
            # Run with scheduler
            collector.start_scheduler()
            
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()

