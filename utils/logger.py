#!/usr/bin/env python3
"""
Logger Utility for AIX Data Graph
Handles structured logging configuration and setup.
"""

import os
import sys
import logging
import logging.handlers
from pathlib import Path
from typing import Dict, Any

import structlog

def setup_logging(config: Dict[str, Any]) -> structlog.BoundLogger:
    """Setup structured logging for the application"""
    
    # Create log directory if it doesn't exist
    log_file = config.get('file', '/var/log/aix-log-collector/collector.log')
    log_dir = Path(log_file).parent
    log_dir.mkdir(parents=True, exist_ok=True)
    
    # Configure standard logging
    log_level = getattr(logging, config.get('level', 'INFO').upper())
    log_format = config.get('format', 'json')
    
    # Create formatter
    if log_format == 'json':
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
    else:
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
    
    # Setup file handler with rotation
    file_handler = logging.handlers.RotatingFileHandler(
        log_file,
        maxBytes=config.get('max_size_mb', 100) * 1024 * 1024,
        backupCount=config.get('backup_count', 5)
    )
    file_handler.setLevel(log_level)
    file_handler.setFormatter(formatter)
    
    # Setup console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(log_level)
    console_handler.setFormatter(formatter)
    
    # Setup root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(log_level)
    root_logger.addHandler(file_handler)
    root_logger.addHandler(console_handler)
    
    # Configure structlog
    structlog.configure(
        processors=[
            structlog.stdlib.filter_by_level,
            structlog.stdlib.add_logger_name,
            structlog.stdlib.add_log_level,
            structlog.stdlib.PositionalArgumentsFormatter(),
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.UnicodeDecoder(),
            structlog.processors.JSONRenderer() if log_format == 'json' else structlog.dev.ConsoleRenderer()
        ],
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )
    
    # Create and return the main logger
    logger = structlog.get_logger('aix-log-collector')
    
    # Log initial setup
    logger.info("Logging system initialized", 
                log_file=str(log_file),
                log_level=config.get('level', 'INFO'),
                log_format=log_format)
    
    return logger

def get_logger(name: str) -> structlog.BoundLogger:
    """Get a logger instance by name"""
    return structlog.get_logger(name)

def setup_child_logger(parent_logger: structlog.BoundLogger, name: str) -> structlog.BoundLogger:
    """Setup a child logger with the same configuration as parent"""
    return parent_logger.bind(logger_name=name)

