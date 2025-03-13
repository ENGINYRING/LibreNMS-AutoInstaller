#!/usr/bin/env bash
# LibreNMS Automated Installer for Ubuntu/Debian
# This script installs LibreNMS (master) with minimal user input.
# It cleans any existing LibreNMS installation and resets MySQL/MariaDB state.
# All generated passwords and important info are saved to /root/librenms.txt.
# Author: ENGINYRING

set -euo pipefail

LOGFILE="/root/librenms.txt"
> "$LOGFILE"  # truncate log file if exists

echo "### LibreNMS Installation Log - $(date) ###" >> "$LOGFILE"

# 1. Prompt for Web Server choice
echo "Select web server: [1] Apache HTTPD, [2] Nginx"
read -r web_choice
if [[ "$web_choice" == "2" || "$web_choice" =~ ^[Nn] ]]; then
    WEBSERVER="nginx"
else
    WEBSERVER="apache"
fi
echo "Web Server: $WEBSERVER" | tee -a "$LOGFILE"

# 2. Prompt for Database choice
echo "Select database server: [1] MariaDB, [2] MySQL"
read -r db_choice
if [[ "$db_choice" == "2" || "$db_choice" =~ ^[Mm][Yy][Ss][Qq][Ll] ]]; then
    DBENGINE="mysql"
else
    DBENGINE="mariadb"
fi
echo "Database Server: $DBENGINE" | tee -a "$LOGFILE"

# 3. Determine PHP version
default_php_ver="8.2"   # default to 8.2 (minimum supported)
echo "Enter PHP version to install (leave blank for default $default_php_ver):"
read -r php_ver_input
if [[ -z "$php_ver_input" ]]; then
    PHP_VER="$default_php_ver"
else
    PHP_VER="$php_ver_input"
fi

# Ensure PHP version is >= 8.2
php_main_ver="${PHP_VER%%.*}"
php_sub_ver="${PHP_VER#*.}"
if (( php_main_ver < 8 || (php_main_ver == 8 && php_sub_ver < 2) )); then
    echo "PHP $PHP_VER is below the minimum required 8.2. Defaulting to 8.2."
    PHP_VER="8.2"
fi
echo "PHP version: $PHP_VER" | tee -a "$LOGFILE"

# 4. System update and base packages
echo "Updating system packages..."
apt-get update -qq
apt-get install -y software-properties-common curl gnupg apt-transport-https git acl unzip composer

# 5. Add PHP repository (Ondrej PPA for Ubuntu or SURY for Debian) if needed
. /etc/os-release
if [[ "$ID" == "ubuntu" ]]; then
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
elif [[ "$ID" == "debian" ]]; then
    curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/sury-php.gpg
    echo "deb https://packages.sury.org/php/ ${VERSION_CODENAME} main" > /etc/apt/sources.list.d/sury-php.list
fi
apt-get update -qq

# ---- Pre-cleanup: Remove any existing LibreNMS installation and reset DB state ----
echo "Cleaning previous LibreNMS installation..."

# Ensure MySQL/MariaDB is running before trying to interact with it
systemctl start mysql || systemctl start mariadb

# Reset MySQL/MariaDB state for LibreNMS - ensure we cleanly remove any existing databases/users
echo "Resetting MySQL/MariaDB state for LibreNMS..."
mysql -u root <<EOF || true
DROP DATABASE IF EXISTS librenms;
DROP USER IF EXISTS 'librenms'@'localhost';
FLUSH PRIVILEGES;
EOF

# Remove existing LibreNMS directory
if [ -d /opt/librenms ]; then
    rm -rf /opt/librenms
    echo "Removed /opt/librenms directory." | tee -a "$LOGFILE"
fi

# Remove existing web server configurations
if [[ "$WEBSERVER" == "apache" ]]; then
    if [ -f /etc/apache2/sites-available/librenms.conf ]; then
        a2dissite librenms.conf
        rm -f /etc/apache2/sites-available/librenms.conf
        systemctl reload apache2 || true
    fi
elif [[ "$WEBSERVER" == "nginx" ]]; then
    if [ -f /etc/nginx/conf.d/librenms.conf ]; then
        rm -f /etc/nginx/conf.d/librenms.conf
        systemctl reload nginx || true
    fi
fi

# Clean up rrdcached setup
if [ -f /etc/default/rrdcached ]; then
    systemctl stop rrdcached || true
    # Clear any problematic journal files
    rm -rf /var/lib/rrdcached/journal/* 2>/dev/null || true
fi

# Remove existing cron and logrotate files
rm -f /etc/cron.d/librenms /etc/logrotate.d/librenms
# ------------------------------------------------------------------------------------

# 6. Set debconf to pre-answer MySQL/MariaDB root password prompts
DB_ROOT_PASS=$(openssl rand -base64 16 | tr -d "=+/")
if [[ "$DBENGINE" == "mysql" ]]; then
    echo "mysql-server mysql-server/root_password password $DB_ROOT_PASS" | debconf-set-selections
    echo "mysql-server mysql-server/root_password_again password $DB_ROOT_PASS" | debconf-set-selections
else
    echo "mariadb-server mariadb-server/root_password password $DB_ROOT_PASS" | debconf-set-selections
    echo "mariadb-server mariadb-server/root_password_again password $DB_ROOT_PASS" | debconf-set-selections
fi
echo "Database root password: $DB_ROOT_PASS" >> "$LOGFILE"

# 7. Install dependencies
echo "Installing required packages (this may take a while)..."
if [[ "$WEBSERVER" == "apache" ]]; then
    apt-get install -y \
      ${DBENGINE}-server ${DBENGINE}-client \
      apache2 libapache2-mod-php$PHP_VER \
      php$PHP_VER php$PHP_VER-cli php$PHP_VER-fpm php$PHP_VER-curl php$PHP_VER-gd \
      php$PHP_VER-mysql php$PHP_VER-snmp php$PHP_VER-mbstring php$PHP_VER-xml php$PHP_VER-zip php$PHP_VER-gmp \
      php$PHP_VER-common \
      fping graphviz imagemagick mtr-tiny nmap rrdtool snmp snmpd whois \
      python3-pymysql python3-dotenv python3-redis python3-psutil python3-systemd python3-pip
elif [[ "$WEBSERVER" == "nginx" ]]; then
    apt-get install -y \
      ${DBENGINE}-server ${DBENGINE}-client \
      nginx-full php$PHP_VER-fpm \
      php$PHP_VER php$PHP_VER-cli php$PHP_VER-curl php$PHP_VER-gd \
      php$PHP_VER-mysql php$PHP_VER-snmp php$PHP_VER-mbstring php$PHP_VER-xml php$PHP_VER-zip php$PHP_VER-gmp \
      php$PHP_VER-common \
      fping graphviz imagemagick mtr-tiny nmap rrdtool snmp snmpd whois \
      python3-pymysql python3-dotenv python3-redis python3-psutil python3-systemd python3-pip
fi

# Ensure rrdcached is installed
apt-get install -y rrdcached

# 8. Add librenms user
useradd -r -M -d /opt/librenms -s "$(which bash)" librenms || true
echo "Created user 'librenms' for installation." | tee -a "$LOGFILE"
usermod -aG librenms www-data

# 9. Clone LibreNMS code
echo "Downloading LibreNMS..."
git clone https://github.com/librenms/librenms.git /opt/librenms
cd /opt/librenms
git checkout master || true
chown -R librenms:librenms /opt/librenms
# Make sure the rrd directory exists with correct permissions
mkdir -p /opt/librenms/rrd
chown -R librenms:librenms /opt/librenms/rrd
chmod 775 /opt/librenms/rrd
setfacl -R -m g:librenms:rwx /opt/librenms/rrd || true
setfacl -d -m g:librenms:rwx /opt/librenms/rrd || true

# Make sure logs directory exists with proper permissions
mkdir -p /opt/librenms/logs
chown -R librenms:librenms /opt/librenms/logs
chmod 775 /opt/librenms/logs
setfacl -R -m g:librenms:rwx /opt/librenms/logs || true
setfacl -d -m g:librenms:rwx /opt/librenms/logs || true

# 9a. Install Composer dependencies
echo "Installing LibreNMS dependencies via Composer..."
sudo -u librenms bash -c 'cd /opt/librenms && ./scripts/composer_wrapper.php install --no-dev'

# Check and fix Python dependencies
echo "Checking and installing Python dependencies..."
python3 -m pip install --upgrade pip
pip3 install -r /opt/librenms/requirements.txt

# Fix common missing packages
apt-get install -y \
    acl \
    graphviz \
    imagemagick \
    mtr-tiny \
    nmap \
    python3-mysqldb \
    python3-dotenv \
    python3-redis \
    python3-pymysql \
    python3-setuptools \
    rrdtool \
    snmp \
    snmpd \
    whois \
    python3-pip \
    python3-memcache


# 10. Database setup: start service and create DB and user
echo "Configuring database..."
# Make sure the database service is started
systemctl start mysql || systemctl start mariadb
systemctl enable mysql || systemctl enable mariadb

# Generate a secure password for the LibreNMS database user
LNMS_DB_PASS=$(openssl rand -base64 12 | tr -d "=+/")

# Ensure the user is dropped if it exists, then create the database and user
mysql -u root -p"$DB_ROOT_PASS" <<EOF
DROP USER IF EXISTS 'librenms'@'localhost';
DROP DATABASE IF EXISTS librenms;
CREATE DATABASE librenms CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'librenms'@'localhost' IDENTIFIED BY '$LNMS_DB_PASS';
GRANT ALL PRIVILEGES ON librenms.* TO 'librenms'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "LibreNMS DB password: $LNMS_DB_PASS" >> "$LOGFILE"

# Verify the credentials work
if ! mysql -u librenms -p"$LNMS_DB_PASS" -e "SELECT 1" librenms >/dev/null 2>&1; then
    echo "ERROR: Database credentials verification failed" | tee -a "$LOGFILE"
    echo "Installation cannot continue. Please check MySQL/MariaDB configuration."
    exit 1
else
    echo "Database setup successful." | tee -a "$LOGFILE"
fi
echo "LibreNMS DB password: $LNMS_DB_PASS" >> "$LOGFILE"

# MySQL config tuning
MYSQL_CNF="/etc/mysql/my.cnf"
if [ -f /etc/mysql/mariadb.conf.d/50-server.cnf ]; then
    MYSQL_CNF="/etc/mysql/mariadb.conf.d/50-server.cnf"
fi
sed -i -r -e '/\[mysqld\]/a innodb_file_per_table=1\nsql-mode=""\nlower_case_table_names=0' "$MYSQL_CNF" || true
systemctl restart mysql || systemctl restart mariadb

# 11. Configure PHP (timezone and modules)
if [[ -f /etc/php/$PHP_VER/apache2/php.ini ]]; then
    sed -i "s/;date.timezone =.*/date.timezone = UTC/" /etc/php/$PHP_VER/apache2/php.ini
fi
if [[ -f /etc/php/$PHP_VER/cli/php.ini ]]; then
    sed -i "s/;date.timezone =.*/date.timezone = UTC/" /etc/php/$PHP_VER/cli/php.ini
fi
if [[ -f /etc/php/$PHP_VER/fpm/php.ini ]]; then
    sed -i "s/;date.timezone =.*/date.timezone = UTC/" /etc/php/$PHP_VER/fpm/php.ini
fi
if [[ "$WEBSERVER" == "apache" ]]; then
    a2enmod php$PHP_VER
    a2enmod rewrite
    a2dismod mpm_event || true
    a2enmod mpm_prefork
fi

# 12. Web server virtual host configuration
if [[ "$WEBSERVER" == "apache" ]]; then
    cat > /etc/apache2/sites-available/librenms.conf <<APACHECONF
<VirtualHost *:80>
    DocumentRoot /opt/librenms/html/
    ServerName ${HOSTNAME}
    AllowEncodedSlashes NoDecode
    <Directory "/opt/librenms/html/">
       Require all granted
       AllowOverride All
       Options FollowSymLinks MultiViews
    </Directory>
    <IfModule setenvif_module>
       SetEnvIfNoCase ^Authorization\$ "(.+)" HTTP_AUTHORIZATION=\$1
    </IfModule>
</VirtualHost>
APACHECONF
    a2dissite 000-default.conf 2>/dev/null || true
    a2ensite librenms.conf
    systemctl reload apache2
    systemctl enable apache2
elif [[ "$WEBSERVER" == "nginx" ]]; then
    cat > /etc/nginx/conf.d/librenms.conf <<NGINXCONF
server {
    listen 80;
    server_name ${HOSTNAME};
    root /opt/librenms/html;
    index index.php;
    charset utf-8;
    gzip on;
    gzip_types text/css application/javascript text/javascript application/x-javascript image/svg+xml text/plain text/xsd text/xsl text/xml image/x-icon;
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ [^/]\.php(/|$) {
        fastcgi_pass unix:/var/run/php/php$PHP_VER-fpm.sock;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        include fastcgi.conf;
    }
    location ~ /\.(?!well-known).* {
        deny all;
    }
}
NGINXCONF
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default 2>/dev/null || true
    systemctl reload nginx
    systemctl enable nginx
    systemctl enable php$PHP_VER-fpm
fi

# 13. SNMP Configuration
echo "Configuring SNMP (snmpd)..."
if [ -f /etc/snmp/snmpd.conf ]; then
    cp /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.orig.$(date +%F)
fi
cp /opt/librenms/snmpd.conf.example /etc/snmp/snmpd.conf
read -r -p "Enter SNMP community name [default: public]: " SNMP_COMM
SNMP_COMM=${SNMP_COMM:-public}
sed -i "s/RANDOMSTRINGGOESHERE/$SNMP_COMM/" /etc/snmp/snmpd.conf
curl -o /usr/bin/distro -s https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/distro
chmod +x /usr/bin/distro
systemctl enable snmpd
systemctl restart snmpd
echo "SNMP community: $SNMP_COMM" >> "$LOGFILE"

# 14. RRDCached Configuration
echo "Setting up rrdcached for performance..."
if [ -f /etc/default/rrdcached ]; then
    # Properly configure rrdcached with correct settings
    sed -i 's/^#*RUNAS=.*/RUNAS=librenms/' /etc/default/rrdcached
    sed -i 's/^#*DAEMON_USER=.*/DAEMON_USER=librenms/' /etc/default/rrdcached
    sed -i 's/^#*BASE_PATH=.*/BASE_PATH=\/opt\/librenms\/rrd/' /etc/default/rrdcached
    sed -i 's/^#*WRITE_TIMEOUT=.*/WRITE_TIMEOUT=1800/' /etc/default/rrdcached
    sed -i 's/^#*JOURNAL_PATH=.*/JOURNAL_PATH=\/var\/lib\/rrdcached\/journal/' /etc/default/rrdcached
    sed -i 's/^#*PIDFILE=.*/PIDFILE=\/run\/rrdcached.pid/' /etc/default/rrdcached
    
    # This line is crucial for socket permissions
    sed -i 's/^#*OPTIONS=.*/OPTIONS="-w 1800 -z 1800 -f 3600 -B -R -j \/var\/lib\/rrdcached\/journal -F -p \/run\/rrdcached.pid -s librenms -m 0660 -l unix:\/run\/rrdcached.sock -b \/opt\/librenms\/rrd"/' /etc/default/rrdcached
    
    # Create journal directory with proper permissions
    mkdir -p /var/lib/rrdcached/journal
    chown -R librenms:librenms /var/lib/rrdcached
fi

# Make sure the config.php includes the correct rrdcached socket path
if grep -q "rrdcached.*sock" /opt/librenms/config.php; then
    sed -i 's|$config\[\x27rrdcached\x27\].*|$config\[\x27rrdcached\x27\] = "unix:/run/rrdcached.sock";|' /opt/librenms/config.php
fi

# Restart and enable rrdcached
systemctl restart rrdcached
systemctl enable rrdcached

# Make sure librenms user can access the socket
usermod -a -G librenms www-data


# 15. Copy configuration
echo "Creating LibreNMS configuration file..."
cat > /opt/librenms/config.php <<CONFIG
<?php
\$config['db_host'] = 'localhost';
\$config['db_user'] = 'librenms';
\$config['db_pass'] = '$LNMS_DB_PASS';
\$config['db_name'] = 'librenms';
\$config['db_socket'] = '';

// Base installation directory
\$config['install_dir'] = '/opt/librenms';

// Default community list to use when adding/discovering
\$config['snmp']['community'] = array("$SNMP_COMM");

// Set default poller threads for improved performance
\$config['poller_threads'] = 16;

// RRD Configuration
\$config['rrdtool_version'] = '1.7.2';
\$config['rrdcached'] = "unix:/run/rrdcached.sock";
\$config['rrd_dir'] = "/opt/librenms/rrd";
\$config['rrd_purge'] = 0;

// Sensible alert settings
\$config['alert']['tolerance_window'] = 5;
\$config['alert']['macros']['rule'] = array(
    'is_warning' => "(\\\$status == 1)",
    'is_critical' => "(\\\$status == 2)",
);

// Enable billing
\$config['enable_billing'] = 1;

// Allow automatic updates
\$config['update'] = 1;
\$config['update_channel'] = 'master';

// Force HTTPS by default for improved security
\$config['secure_cookies'] = 1;

// Enable syslog by default
\$config['enable_syslog'] = 1;
CONFIG
chown librenms:librenms /opt/librenms/config.php
chmod 660 /opt/librenms/config.php

# 16. Setup LibreNMS cron jobs
echo "Setting up cron jobs..."
# Check for different possible locations of the cron file
if [ -f /opt/librenms/librenms.nonroot.cron ]; then
    cp /opt/librenms/librenms.nonroot.cron /etc/cron.d/librenms
elif [ -f /opt/librenms/misc/librenms.nonroot.cron ]; then
    cp /opt/librenms/misc/librenms.nonroot.cron /etc/cron.d/librenms
else
    # Create the cron file directly if neither exists
    cat > /etc/cron.d/librenms <<CRON
# LibreNMS cron jobs
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Run a discovery of all devices every 6 hours
33  */6   * * *   librenms    cd /opt/librenms && php discovery.php -h all >> /dev/null 2>&1

# Run a discovery on new devices and fail fast every 5 minutes
*/5 *     * * *   librenms    cd /opt/librenms && php discovery.php -h new >> /dev/null 2>&1

# Run polling of all devices every 5 minutes
*/5 *     * * *   librenms    cd /opt/librenms && php poller.php -h all >> /dev/null 2>&1

# Check services every 5 minutes
*/5 *     * * *   librenms    cd /opt/librenms && php check-services.php >> /dev/null 2>&1

# Run billing every minute
*   *     * * *   librenms    cd /opt/librenms && php poll-billing.php >> /dev/null 2>&1

# Run alerts every 5 minutes
*/5 *     * * *   librenms    cd /opt/librenms && php alerts.php >> /dev/null 2>&1

# Run alert rules check every 5 minutes
*/5 *     * * *   librenms    cd /opt/librenms && php process_alert_rules.php >> /dev/null 2>&1

# Poll for device component status every 5 minutes
*/5 *     * * *   librenms    cd /opt/librenms && php poll-device-components.php >> /dev/null 2>&1

# Daily maintenance
15  0     * * *   librenms    cd /opt/librenms && php daily.php >> /dev/null 2>&1

# Python poller wrapper - this is the critical entry that was missing
*/5 *     * * *   librenms    cd /opt/librenms && python3 /opt/librenms/poller-wrapper.py 16 >> /dev/null 2>&1
CRON
fi

# Create wrapper entry if missing
if ! grep -q "poller-wrapper.py" /etc/cron.d/librenms; then
    echo "*/5 *     * * *   librenms    cd /opt/librenms && python3 /opt/librenms/poller-wrapper.py 16 >> /dev/null 2>&1" >> /etc/cron.d/librenms
fi

# Set correct permissions on cron file
chmod 644 /etc/cron.d/librenms

# 17. Setup logrotate
echo "Setting up log rotation..."
if [ -f /opt/librenms/misc/librenms.logrotate ]; then
    cp /opt/librenms/misc/librenms.logrotate /etc/logrotate.d/librenms
else
    # Create logrotate config directly if file doesn't exist
    cat > /etc/logrotate.d/librenms <<LOGROTATE
/opt/librenms/logs/*.log {
        daily
        rotate 7
        compress
        delaycompress
        missingok
        notifempty
        create 664 librenms librenms
}
LOGROTATE
fi

# Set correct permissions on logrotate file
chmod 644 /etc/logrotate.d/librenms

# 18. Run installation validation and install additional utilities
echo "Running validation checks and installing additional utilities..."

# Install global lnms shortcut and bash completion
echo "Installing global lnms shortcut and bash completion..."
if [ -f /opt/librenms/lnms ]; then
    ln -sf /opt/librenms/lnms /usr/local/bin/lnms
    
    # Install bash completion
    if [ -d /etc/bash_completion.d ] && [ -f /opt/librenms/misc/lnms-completion.bash ]; then
        cp /opt/librenms/misc/lnms-completion.bash /etc/bash_completion.d/
        # Don't source as it might not work in a script context
    fi
fi

# Run validation
cd /opt/librenms
./validate.php || true

# 19. Web UI admin user creation
echo "Creating LibreNMS admin user..."
read -r -p "Enter Web UI admin username [default: admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}
read -r -s -p "Enter Web UI admin password (leave blank to generate random): " ADMIN_PASS
echo
if [[ -z "$ADMIN_PASS" ]]; then
    ADMIN_PASS=$(openssl rand -base64 12)
    echo "Generated random admin password: $ADMIN_PASS" | tee -a "$LOGFILE"
fi

# 19. Web UI setup information
echo "Setting up web installer..."
cd /opt/librenms

# Create .env file with INSTALL=true to enable web installer
cat > .env <<EOF
APP_KEY=$(php -r "echo md5(random_bytes(32));")
DB_HOST=localhost
DB_DATABASE=librenms
DB_USERNAME=librenms
DB_PASSWORD=$LNMS_DB_PASS

# Enable web installer
INSTALL=true
EOF

# Fix permissions to ensure librenms user can access it
chown librenms:librenms .env
chmod 660 .env

# Clear config cache and run migrations
php artisan config:clear
sudo -u librenms php artisan migrate --force

echo "======================================"
echo "Installation complete!"
echo "LibreNMS has been installed successfully."
echo ""
echo "Please visit http://${HOSTNAME} or http://$(hostname -I | awk '{print $1}')"
echo "to complete the setup and create your admin account."
echo ""
echo "Database credentials have been saved to $LOGFILE"
echo "======================================"

# 20. Final cleanup and restart services
echo "Performing final cleanup and service restart..."

# Apply proper permissions to all directories
chown -R librenms:librenms /opt/librenms
find /opt/librenms -type d -exec chmod 775 {} \;
find /opt/librenms -type f -exec chmod 664 {} \;

# Make specific files executable
find /opt/librenms -name '*.php' -exec chmod 775 {} \;
find /opt/librenms/scripts -type f -exec chmod +x {} \;
chmod +x /opt/librenms/validate.php /opt/librenms/daily.php

# Ensure web server can access RRDCached socket
if [ -S /run/rrdcached.sock ]; then
    chmod 660 /run/rrdcached.sock
    chown librenms:librenms /run/rrdcached.sock
fi

# Fix common webserver configuration issues
if [[ "$WEBSERVER" == "apache" ]]; then
    # Ensure Apache has required modules
    a2enmod rewrite
    a2enmod php$PHP_VER
    systemctl restart apache2
elif [[ "$WEBSERVER" == "nginx" ]]; then
    # Fix PHP-FPM config
    sed -i "s/;clear_env = no/clear_env = no/" /etc/php/$PHP_VER/fpm/pool.d/www.conf
    echo "env[PATH] = \$PATH" >> /etc/php/$PHP_VER/fpm/pool.d/www.conf
    systemctl restart nginx
    systemctl restart php$PHP_VER-fpm
fi

# Restart services one final time
systemctl restart snmpd
systemctl restart rrdcached

echo "======================================"
echo "Installation complete!"
echo "LibreNMS has been installed successfully."
echo ""
echo "Please visit http://${HOSTNAME} or http://$(hostname -I | awk '{print $1}')"
echo "to complete the setup and create your admin account."
echo ""
echo "Database credentials have been saved to $LOGFILE"
echo ""
echo "If you encounter validation issues, run the post-install fix script:"
echo "bash /root/librenms-post-install-fix.sh"
echo "======================================"

# Create the post-install fix script
cat > /root/librenms-post-install-fix.sh <<'POSTINSTALL'
#!/bin/bash
# LibreNMS Post-Install Fix Script
# This script fixes common issues that appear in the validation report

echo "==== LibreNMS Post-Installation Fix Script ===="
echo "This script will fix common issues that appear in the validation report"

# Fix RRDCached socket permissions
if [ -S /run/rrdcached.sock ]; then
    echo "Fixing RRDCached socket permissions..."
    chmod 660 /run/rrdcached.sock
    chown librenms:librenms /run/rrdcached.sock
fi

# Create RRDCached journal directory with proper permissions
if [ ! -d /var/lib/rrdcached/journal ]; then
    echo "Creating RRDCached journal directory..."
    mkdir -p /var/lib/rrdcached/journal
    chown -R librenms:librenms /var/lib/rrdcached
fi

# Restart RRDCached to apply changes
echo "Restarting RRDCached..."
systemctl restart rrdcached

# Update PHP memory limit if needed
echo "Increasing PHP memory limit if needed..."
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
for conf in cli fpm apache2; do
    if [ -f "/etc/php/$PHP_VERSION/$conf/php.ini" ]; then
        sed -i 's/memory_limit = .*/memory_limit = 512M/' "/etc/php/$PHP_VERSION/$conf/php.ini"
    fi
done

# Restart web server
echo "Restarting web server..."
if systemctl is-active --quiet apache2; then
    systemctl restart apache2
elif systemctl is-active --quiet nginx; then
    systemctl restart nginx
    systemctl restart php$PHP_VERSION-fpm
fi

# Fix log directory permissions
echo "Fixing log directory permissions..."
mkdir -p /opt/librenms/logs
touch /opt/librenms/logs/librenms.log
chown -R librenms:librenms /opt/librenms/logs
chmod -R 775 /opt/librenms/logs

# Run validate.php to check for remaining issues
echo "Running validation script to check for remaining issues..."
cd /opt/librenms
sudo -u librenms ./validate.php

echo "==== Fixes Applied ===="
echo "Please review any remaining issues in the validation report."
echo "If web installer doesn't work, make sure you have INSTALL=true in .env file."
echo "To add your first device: ./addhost.php <hostname> <community> v2c"
POSTINSTALL

chmod +x /root/librenms-post-install-fix.sh

exit 0
