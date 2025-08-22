#!/usr/bin/env python3
"""
SSH Setup Script for AIX Data Graph
This script helps set up SSH keys and connections to AIX servers for automated log collection.
"""

import os
import sys
import argparse
import subprocess
import getpass
from pathlib import Path
from typing import List, Dict, Optional

def run_command(command: List[str], capture_output: bool = True) -> Dict[str, any]:
    """Run a shell command and return the result"""
    try:
        result = subprocess.run(
            command,
            capture_output=capture_output,
            text=True,
            check=True
        )
        return {
            'success': True,
            'stdout': result.stdout,
            'stderr': result.stderr,
            'returncode': result.returncode
        }
    except subprocess.CalledProcessError as e:
        return {
            'success': False,
            'stdout': e.stdout,
            'stderr': e.stderr,
            'returncode': e.returncode
        }
    except FileNotFoundError:
        return {
            'success': False,
            'stdout': '',
            'stderr': 'Command not found',
            'returncode': -1
        }

def check_ssh_key_exists() -> bool:
    """Check if SSH key already exists"""
    private_key = Path.home() / '.ssh' / 'id_rsa'
    public_key = Path.home() / '.ssh' / 'id_rsa.pub'
    return private_key.exists() and public_key.exists()

def generate_ssh_key() -> bool:
    """Generate a new SSH key pair"""
    print("Generating new SSH key pair...")
    
    # Create .ssh directory if it doesn't exist
    ssh_dir = Path.home() / '.ssh'
    ssh_dir.mkdir(mode=0o700, exist_ok=True)
    
    # Generate key
    result = run_command([
        'ssh-keygen', '-t', 'rsa', '-b', '4096', 
        '-f', str(ssh_dir / 'id_rsa'), 
        '-N', '', '-C', 'aix-log-collector'
    ])
    
    if result['success']:
        print("✓ SSH key generated successfully")
        return True
    else:
        print(f"✗ Failed to generate SSH key: {result['stderr']}")
        return False

def get_public_key() -> Optional[str]:
    """Get the public key content"""
    public_key_path = Path.home() / '.ssh' / 'id_rsa.pub'
    
    if not public_key_path.exists():
        return None
    
    try:
        return public_key_path.read_text().strip()
    except Exception as e:
        print(f"Error reading public key: {e}")
        return None

def test_ssh_connection(hostname: str, username: str, port: int = 22) -> bool:
    """Test SSH connection to a server"""
    print(f"Testing SSH connection to {username}@{hostname}:{port}...")
    
    result = run_command([
        'ssh', '-o', 'ConnectTimeout=10', '-o', 'StrictHostKeyChecking=no',
        '-p', str(port), f'{username}@{hostname}', 'echo "SSH connection successful"'
    ])
    
    if result['success']:
        print(f"✓ SSH connection to {hostname} successful")
        return True
    else:
        print(f"✗ SSH connection to {hostname} failed: {result['stderr']}")
        return False

def copy_ssh_key_to_server(hostname: str, username: str, password: str, port: int = 22) -> bool:
    """Copy SSH public key to a server using ssh-copy-id"""
    print(f"Copying SSH key to {username}@{hostname}:{port}...")
    
    # Use sshpass if available, otherwise prompt for password
    if run_command(['which', 'sshpass'])['success']:
        # Use sshpass for automated key copying
        result = run_command([
            'sshpass', '-p', password, 'ssh-copy-id', 
            '-o', 'StrictHostKeyChecking=no',
            '-p', str(port), f'{username}@{hostname}'
        ])
    else:
        # Manual key copying
        public_key = get_public_key()
        if not public_key:
            print("✗ Could not read public key")
            return False
        
        # Create the command to add the key
        add_key_cmd = f"mkdir -p ~/.ssh && echo '{public_key}' >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
        
        # Use expect-like approach with subprocess
        try:
            # This is a simplified approach - in production, you might want to use pexpect
            result = run_command([
                'ssh', '-o', 'StrictHostKeyChecking=no', '-p', str(port),
                f'{username}@{hostname}', add_key_cmd
            ])
        except Exception as e:
            print(f"✗ Failed to copy key: {e}")
            return False
    
    if result['success']:
        print(f"✓ SSH key copied to {hostname} successfully")
        return True
    else:
        print(f"✗ Failed to copy SSH key to {hostname}: {result['stderr']}")
        return False

def setup_server_connection(server_info: Dict[str, str]) -> bool:
    """Set up SSH connection for a single server"""
    hostname = server_info['hostname']
    username = server_info.get('username', 'root')
    port = int(server_info.get('port', 22))
    
    print(f"\n{'='*50}")
    print(f"Setting up connection to: {hostname}")
    print(f"{'='*50}")
    
    # Test if we can already connect without password
    if test_ssh_connection(hostname, username, port):
        print(f"✓ SSH key authentication already working for {hostname}")
        return True
    
    # Prompt for password
    print(f"SSH key authentication not working for {hostname}")
    password = getpass.getpass(f"Enter password for {username}@{hostname}: ")
    
    if not password:
        print("✗ No password provided, skipping server")
        return False
    
    # Copy SSH key to server
    if copy_ssh_key_to_server(hostname, username, password, port):
        # Test connection again
        if test_ssh_connection(hostname, username, port):
            print(f"✓ SSH setup completed successfully for {hostname}")
            return True
        else:
            print(f"✗ SSH key copied but connection still fails for {hostname}")
            return False
    else:
        print(f"✗ Failed to set up SSH for {hostname}")
        return False

def create_aix_test_script(server_info: Dict[str, str]) -> str:
    """Create a test script to verify AIX server connectivity"""
    hostname = server_info['hostname']
    username = server_info.get('username', 'root')
    port = server_info.get('port', 22)
    
    script_content = f"""#!/bin/bash
# AIX Server Test Script for {hostname}
# This script tests basic AIX commands and connectivity

echo "Testing AIX server: {hostname}"
echo "Timestamp: $(date)"
echo ""

# Test basic connectivity
echo "1. Testing SSH connection..."
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p {port} {username}@{hostname} "echo 'SSH connection successful'"

if [ $? -eq 0 ]; then
    echo "✓ SSH connection working"
else
    echo "✗ SSH connection failed"
    exit 1
fi

# Test AIX-specific commands
echo ""
echo "2. Testing AIX commands..."

# Test errpt command
echo "Testing errpt command..."
ssh -o StrictHostKeyChecking=no -p {port} {username}@{hostname} "errpt -a | head -5"

# Test system information
echo ""
echo "Testing system information..."
ssh -o StrictHostKeyChecking=no -p {port} {username}@{hostname} "uname -a; oslevel -s"

# Test log file access
echo ""
echo "Testing log file access..."
ssh -o StrictHostKeyChecking=no -p {port} {username}@{hostname} "ls -la /var/adm/ras/ | head -5"

echo ""
echo "✓ AIX server test completed successfully"
"""
    
    script_path = f"test_aix_{hostname.replace('.', '_').replace('-', '_')}.sh"
    with open(script_path, 'w') as f:
        f.write(script_content)
    
    os.chmod(script_path, 0o755)
    return script_path

def main():
    """Main function"""
    parser = argparse.ArgumentParser(
        description="SSH Setup Script for AIX Data Graph",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Setup SSH for specific servers
  python3 ssh_setup.py --servers server1.example.com,server2.example.com
  
  # Setup SSH with custom usernames
  python3 ssh_setup.py --servers server1:user1,server2:user2
  
  # Setup SSH with custom ports
  python3 ssh_setup.py --servers server1:user1:2222,server2:user2:2222
        """
    )
    
    parser.add_argument(
        '--servers', '-s',
        required=True,
        help='Comma-separated list of servers (format: hostname[:username][:port])'
    )
    
    parser.add_argument(
        '--generate-key', '-g',
        action='store_true',
        help='Generate new SSH key even if one exists'
    )
    
    parser.add_argument(
        '--test-only', '-t',
        action='store_true',
        help='Only test existing connections, don\'t setup new ones'
    )
    
    args = parser.parse_args()
    
    print("AIX Data Graph - SSH Setup Script")
    print("=" * 50)
    
    # Parse server list
    servers = []
    for server_str in args.servers.split(','):
        parts = server_str.strip().split(':')
        if len(parts) == 1:
            servers.append({'hostname': parts[0], 'username': 'root', 'port': 22})
        elif len(parts) == 2:
            servers.append({'hostname': parts[0], 'username': parts[1], 'port': 22})
        elif len(parts) == 3:
            servers.append({'hostname': parts[0], 'username': parts[1], 'port': int(parts[2])})
        else:
            print(f"✗ Invalid server format: {server_str}")
            sys.exit(1)
    
    print(f"Found {len(servers)} server(s) to configure")
    
    # Check/generate SSH key
    if not check_ssh_key_exists() or args.generate_key:
        if not generate_ssh_key():
            print("✗ Failed to generate SSH key")
            sys.exit(1)
    else:
        print("✓ SSH key already exists")
    
    # Display public key
    public_key = get_public_key()
    if public_key:
        print(f"\nPublic key: {public_key[:50]}...")
    
    # Setup each server
    successful_setups = 0
    
    for server_info in servers:
        if args.test_only:
            # Only test existing connections
            if test_ssh_connection(server_info['hostname'], server_info['username'], server_info['port']):
                successful_setups += 1
                # Create test script
                test_script = create_aix_test_script(server_info)
                print(f"✓ Created test script: {test_script}")
        else:
            # Setup new connections
            if setup_server_connection(server_info):
                successful_setups += 1
                # Create test script
                test_script = create_aix_test_script(server_info)
                print(f"✓ Created test script: {test_script}")
    
    # Summary
    print(f"\n{'='*50}")
    print("Setup Summary")
    print(f"{'='*50}")
    print(f"Total servers: {len(servers)}")
    print(f"Successful setups: {successful_setups}")
    print(f"Failed setups: {len(servers) - successful_setups}")
    
    if successful_setups > 0:
        print(f"\n✓ Successfully configured {successful_setups} server(s)")
        print("You can now run the AIX log collector with:")
        print("  python3 collector/aix_log_collector.py --once")
        print("  python3 collector/aix_log_collector.py --daemon")
    else:
        print("\n✗ No servers were configured successfully")
        sys.exit(1)

if __name__ == "__main__":
    main()

