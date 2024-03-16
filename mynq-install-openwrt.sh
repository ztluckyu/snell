
#!/bin/bash
#
# MyNodeQuery Agent Installation Script for OpenWRT
#
# @version        1.0.2
# @date           2023-06-26
# @copyright      (c) 2021 http://www.idcoffer.com
#

# Set environment
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Prepare output
echo -e "|\n|   MyNodeQuery Installer for OpenWRT\n|   ===================\n|"

# Root required
if [ $(id -u) != "0" ]; then
    echo -e "|   Error: You need to be root to install the MyNodeQuery agent\n|"
    echo -e "|          The agent itself will NOT be running as root but instead under its own non-privileged user\n|"
    exit 1
fi

# Install essential packages using opkg
essential_packages=("coreutils" "bash" "cron")
for package in "${essential_packages[@]}"; do
    if ! command -v $package &> /dev/null; then
        echo -e "|   $package is required and could not be found. Installing...\n|"
        opkg update
        opkg install $package
        if [ $? -ne 0 ]; then
            echo -e "|   Error: $package could not be installed. Please check your package manager settings or network connection.\n|"
            exit 1
        fi
    fi
done

# Check and manage cron service
if ! /etc/init.d/cron enabled; then
    echo "|   Cron service is not enabled, enabling and starting it now..."
    /etc/init.d/cron enable
    /etc/init.d/cron start
    if [ $? -ne 0 ]; then
        echo -e "|   Error: Cron service could not be started.\n|"
        exit 1
    fi
elif ! pgrep cron > /dev/null; then
    echo "|   Cron service is not running, starting it now..."
    /etc/init.d/cron start
    if [ $? -ne 0 ]; then
        echo -e "|   Error: Cron service could not be started.\n|"
        exit 1
    fi
fi

# Other installation steps would go here, ensure they are compatible with OpenWRT

echo -e "|   Success: The MyNodeQuery agent and necessary configurations for OpenWRT have been installed.\n|"
