#!/usr/bin/env python3
"""
Configuration Loader for AIX Data Graph
Handles loading and validation of configuration files.
"""

import os
import sys
import yaml
import logging
from pathlib import Path
from typing import Dict, Any, Optional, List

class ConfigLoader:
    """Loads and validates configuration for AIX Data Graph"""
    
    def __init__(self, config_path: str = "config/config.yaml"):
        """Initialize configuration loader"""
        self.config_path = config_path
        self.logger = logging.getLogger(__name__)
        self.config = None
    
    def load(self) -> Dict[str, Any]:
        """Load configuration from file"""
        if self.config is not None:
            return self.config
        
        try:
            # Resolve config path
            config_file = Path(self.config_path)
            if not config_file.is_absolute():
                # Try relative to current working directory
                config_file = Path.cwd() / config_file
                if not config_file.exists():
                    # Try relative to script location
                    script_dir = Path(__file__).parent.parent
                    config_file = script_dir / self.config_path
            
            if not config_file.exists():
                raise FileNotFoundError(f"Configuration file not found: {self.config_path}")
            
            self.logger.info(f"Loading configuration from: {config_file}")
            
            # Load YAML configuration
            with open(config_file, 'r', encoding='utf-8') as f:
                self.config = yaml.safe_load(f)
            
            # Validate configuration
            self._validate_config()
            
            # Set default values
            self._set_defaults()
            
            self.logger.info("Configuration loaded successfully")
            return self.config
            
        except Exception as e:
            self.logger.error(f"Failed to load configuration: {e}")
            raise
    
    def _validate_config(self):
        """Validate configuration structure and required fields"""
        if not isinstance(self.config, dict):
            raise ValueError("Configuration must be a dictionary")
        
        # Check required sections
        required_sections = ['aix_servers', 'ssh', 'collection', 'database']
        for section in required_sections:
            if section not in self.config:
                raise ValueError(f"Missing required configuration section: {section}")
        
        # Validate AIX servers
        if not isinstance(self.config['aix_servers'], list):
            raise ValueError("aix_servers must be a list")
        
        for i, server in enumerate(self.config['aix_servers']):
            if not isinstance(server, dict):
                raise ValueError(f"Server {i} must be a dictionary")
            
            required_server_fields = ['name', 'hostname', 'username']
            for field in required_server_fields:
                if field not in server:
                    raise ValueError(f"Server {i} missing required field: {field}")
        
        # Validate SSH configuration
        ssh_config = self.config['ssh']
        if not isinstance(ssh_config, dict):
            raise ValueError("ssh must be a dictionary")
        
        if 'private_key_path' not in ssh_config:
            raise ValueError("ssh.private_key_path is required")
        
        # Validate collection configuration
        collection_config = self.config['collection']
        if not isinstance(collection_config, dict):
            raise ValueError("collection must be a dictionary")
        
        # Validate database configuration
        db_config = self.config['database']
        if not isinstance(db_config, dict):
            raise ValueError("database must be a dictionary")
        
        if db_config.get('type') == 'influxdb':
            influx_config = db_config.get('influxdb', {})
            required_influx_fields = ['url', 'token', 'org', 'bucket']
            for field in required_influx_fields:
                if field not in influx_config:
                    raise ValueError(f"database.influxdb.{field} is required")
    
    def _set_defaults(self):
        """Set default values for optional configuration fields"""
        # SSH defaults
        ssh_config = self.config['ssh']
        ssh_config.setdefault('timeout', 30)
        ssh_config.setdefault('retry_attempts', 3)
        ssh_config.setdefault('retry_delay', 5)
        ssh_config.setdefault('max_concurrent_connections', 10)
        
        # Collection defaults
        collection_config = self.config['collection']
        collection_config.setdefault('errpt_interval', 300)
        collection_config.setdefault('syslog_interval', 60)
        collection_config.setdefault('max_log_age_days', 30)
        collection_config.setdefault('max_log_size_mb', 1000)
        
        # Error report defaults
        if 'errpt' not in collection_config:
            collection_config['errpt'] = {}
        errpt_config = collection_config['errpt']
        errpt_config.setdefault('enabled', True)
        errpt_config.setdefault('commands', [
            "errpt -a -s $(date -d '1 hour ago' +%m%d%H%M%y)",
            "errpt -a -s $(date -d '1 day ago' +%m%d%H%M%y)"
        ])
        errpt_config.setdefault('severity_levels', ['H', 'S', 'M', 'L'])
        
        # System log defaults
        if 'syslog' not in collection_config:
            collection_config['syslog'] = {}
        syslog_config = collection_config['syslog']
        syslog_config.setdefault('enabled', True)
        syslog_config.setdefault('log_files', [
            "/var/adm/ras/errlog",
            "/var/adm/ras/conslog",
            "/var/adm/messages"
        ])
        syslog_config.setdefault('keywords', ['error', 'fail', 'critical', 'warning'])
        
        # Database defaults
        db_config = self.config['database']
        if db_config.get('type') == 'influxdb':
            influx_config = db_config['influxdb']
            influx_config.setdefault('retention_policy', '30d')
        
        # Grafana defaults
        if 'grafana' not in self.config:
            self.config['grafana'] = {}
        grafana_config = self.config['grafana']
        grafana_config.setdefault('url', 'http://localhost:3000')
        grafana_config.setdefault('username', 'admin')
        grafana_config.setdefault('password', 'admin')
        grafana_config.setdefault('api_key', '')
        
        if 'dashboards' not in grafana_config:
            grafana_config['dashboards'] = {}
        dashboards_config = grafana_config['dashboards']
        dashboards_config.setdefault('auto_create', True)
        dashboards_config.setdefault('refresh_interval', '30s')
        dashboards_config.setdefault('default_time_range', '1h')
        
        # Logging defaults
        if 'logging' not in self.config:
            self.config['logging'] = {}
        logging_config = self.config['logging']
        logging_config.setdefault('level', 'INFO')
        logging_config.setdefault('format', 'json')
        logging_config.setdefault('file', '/var/log/aix-log-collector/collector.log')
        logging_config.setdefault('max_size_mb', 100)
        logging_config.setdefault('backup_count', 5)
        
        # Monitoring defaults
        if 'monitoring' not in self.config:
            self.config['monitoring'] = {}
        monitoring_config = self.config['monitoring']
        monitoring_config.setdefault('enabled', True)
        monitoring_config.setdefault('port', 9090)
        monitoring_config.setdefault('metrics_path', '/metrics')
        
        # Alerting defaults
        if 'alerts' not in self.config:
            self.config['alerts'] = {}
        alerts_config = self.config['alerts']
        alerts_config.setdefault('enabled', True)
        
        if 'email' not in alerts_config:
            alerts_config['email'] = {}
        email_config = alerts_config['email']
        email_config.setdefault('smtp_server', 'smtp.company.com')
        email_config.setdefault('smtp_port', 587)
        email_config.setdefault('username', 'alerts@company.com')
        email_config.setdefault('password', '')
        email_config.setdefault('recipients', ['admin@company.com'])
        
        if 'thresholds' not in alerts_config:
            alerts_config['thresholds'] = {}
        thresholds_config = alerts_config['thresholds']
        thresholds_config.setdefault('error_count_critical', 10)
        thresholds_config.setdefault('error_count_warning', 5)
        thresholds_config.setdefault('disk_usage_critical', 90)
        thresholds_config.setdefault('disk_usage_warning', 80)
        
        # Performance defaults
        if 'performance' not in self.config:
            self.config['performance'] = {}
        performance_config = self.config['performance']
        performance_config.setdefault('max_concurrent_connections', 10)
        performance_config.setdefault('connection_pool_size', 20)
        performance_config.setdefault('batch_size', 1000)
        performance_config.setdefault('flush_interval', 10)
    
    def get_server_config(self, server_name: str) -> Optional[Dict[str, Any]]:
        """Get configuration for a specific server by name"""
        if not self.config:
            self.load()
        
        for server in self.config['aix_servers']:
            if server['name'] == server_name:
                return server
        
        return None
    
    def get_servers_by_hostname(self, hostname: str) -> List[Dict[str, Any]]:
        """Get all servers with a specific hostname"""
        if not self.config:
            self.load()
        
        return [server for server in self.config['aix_servers'] 
                if server['hostname'] == hostname]
    
    def reload(self) -> Dict[str, Any]:
        """Reload configuration from file"""
        self.config = None
        return self.load()
    
    def validate_server_connection(self, server_name: str) -> bool:
        """Validate that a server configuration is complete and valid"""
        server_config = self.get_server_config(server_name)
        if not server_config:
            return False
        
        # Check required fields
        required_fields = ['name', 'hostname', 'username']
        for field in required_fields:
            if not server_config.get(field):
                return False
        
        # Check if hostname is resolvable (optional)
        try:
            import socket
            socket.gethostbyname(server_config['hostname'])
        except socket.gaierror:
            self.logger.warning(f"Hostname {server_config['hostname']} may not be resolvable")
        
        return True
    
    def get_collection_interval(self, collection_type: str) -> int:
        """Get collection interval for a specific type"""
        if not self.config:
            self.load()
        
        if collection_type == 'errpt':
            return self.config['collection']['errpt_interval']
        elif collection_type == 'syslog':
            return self.config['collection']['syslog_interval']
        else:
            raise ValueError(f"Unknown collection type: {collection_type}")
    
    def is_collection_enabled(self, collection_type: str) -> bool:
        """Check if a collection type is enabled"""
        if not self.config:
            self.load()
        
        if collection_type == 'errpt':
            return self.config['collection']['errpt']['enabled']
        elif collection_type == 'syslog':
            return self.config['collection']['syslog']['enabled']
        else:
            return False

