[![ENGINYRING](https://cdn.enginyring.com/img/logo_dark.png)](https://www.enginyring.com)
# LibreNMS Automated Installer Script
 
A bash script for fully automated installation of LibreNMS (master branch) on Ubuntu and Debian systems with integrated validation fixes.

## Features

- Semi-unattended installation with minimal user input
- Supports both Apache and Nginx web servers
- Works with MariaDB or MySQL database engines
- Configures PHP 8.2+ with all required extensions
- Sets up RRDcached with optimal performance settings
- Properly configures Python wrapper for multi-threaded polling
- Configures proper permissions, ACLs, and system users
- Installs global `lnms` command with bash completion
- Web-based admin user creation through LibreNMS installer
- Includes post-installation fix script for common validation issues
- All credentials stored in a secure log file

## Requirements

- A fresh installation of Ubuntu (22.04+) or Debian (11+)
- Root access
- Internet connectivity

## Usage

1. Download the script using curl or wget:
```bash
# Option 1: Using curl
curl -o librenms-installer.sh https://raw.githubusercontent.com/ENGINYRING/LibreNMS-AutoInstaller/main/librenms-installer.sh

# Option 2: Using wget
wget https://raw.githubusercontent.com/ENGINYRING/LibreNMS-AutoInstaller/main/librenms-installer.sh
```

2. Make the script executable:
```bash
chmod +x librenms-installer.sh
```

3. Run the script as root:
```bash
sudo ./librenms-installer.sh
```

## Installation Process

The script will prompt you for the following information:

1. **Web Server Selection**:
   - Apache HTTPD (recommended for beginners)
   - Nginx (better performance for larger installations)

2. **Database Engine**:
   - MariaDB (default)
   - MySQL

3. **PHP Version**:
   - Defaults to PHP 8.2 (minimum supported)
   - Will validate and correct if you enter a version below 8.2

4. **SNMP Community String**:
   - Default: "public"
   - Consider changing for security in production environments

The script handles the rest automatically:
- Creates and configures the database
- Sets up the web server with proper configuration
- Configures RRDcached for optimal performance
- Sets up Python dependencies and cron jobs
- Enables web-based setup for admin account creation

## Post-Installation

After successful installation:

1. All credentials will be saved to `/root/librenms.txt`
2. Visit your LibreNMS installation at `http://your-server-ip/` to complete the web-based setup
3. Follow the web interface prompts to create your admin account
4. If any validation issues are present, run the included fix script:
   ```bash
   bash /root/librenms-post-install-fix.sh
   ```

## Key Configuration Details

The script sets up various components with optimized settings:

- **RRDcached**: Configured with proper socket permissions for LibreNMS access
- **Python Wrapper**: Set up with 16 threads for efficient device polling
- **File Permissions**: Implements ACLs for key directories to ensure proper operation
- **Global Command**: Adds the `lnms` command to your PATH with tab completion
- **Database**: Optimized for LibreNMS operation with correct character sets
- **Web Server**: Configured for optimal performance with PHP-FPM

## Customization

You can modify the script to suit your needs. Common modifications include:

- Changing the default timezone (currently UTC)
- Adding additional SNMP configuration
- Modifying database settings for performance
- Adding custom LibreNMS configuration options

## Troubleshooting

If you encounter issues:

1. Run the included post-installation fix script:
   ```bash
   bash /root/librenms-post-install-fix.sh
   ```

2. Check the installation credentials in `/root/librenms.txt`

3. Run the validation script manually:
   ```bash
   cd /opt/librenms
   sudo -u librenms php validate.php
   ```

4. Check service status:
   ```bash
   systemctl status apache2|nginx
   systemctl status mysql|mariadb
   systemctl status snmpd
   systemctl status rrdcached
   ```

5. Verify the `.env` file contains `INSTALL=true` to enable the web installer

6. Check for file permission issues:
   ```bash
   sudo chown -R librenms:librenms /opt/librenms
   sudo setfacl -d -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/
   sudo chmod -R ug=rwX /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/
   ```

## Common Validation Issues and Fixes

The script includes fixes for common validation issues:

1. **Python wrapper cron entry missing**:
   - Automatically adds the correct cron job for multi-threaded polling

2. **File ownership problems**:
   - Sets up correct ownership and permissions for all files

3. **RRDcached socket issues**:
   - Configures socket permissions properly for LibreNMS access

4. **Git modifications**:
   - The post-install script can run `github-remove` to clean modifications

## Adding Your First Device

After installation, you can add your first device through the web interface or with:

```bash
cd /opt/librenms
./addhost.php hostname community v2c
```

## About LibreNMS

LibreNMS is a powerful, auto-discovering network monitoring system built on top of a variety of open source software including PHP, MySQL, SNMP, and RRDtool. It supports a wide range of hardware and operating systems.

For more information, visit: [LibreNMS Documentation](https://docs.librenms.org/)

## License

This script is released under the MIT License. See the LICENSE file for details.

## Author

Created by [ENGINYRING](https://github.com/ENGINYRING)
