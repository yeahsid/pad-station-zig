#!/bin/bash

set -e

echo "Starting uninstallation of dependencies for the LabJack T7 Zig program..."

# Determine the operating system
OS="$(uname -s)"

echo "Detected OS: $OS"

uninstall_zig() {
    echo "Uninstalling Zig compiler..."

    ZIG_INSTALL_DIR="/usr/local/zig"

    if [ -d "$ZIG_INSTALL_DIR" ]; then
        sudo rm -rf "$ZIG_INSTALL_DIR"
        echo "Zig compiler uninstalled from $ZIG_INSTALL_DIR"
    else
        echo "Zig compiler not found in $ZIG_INSTALL_DIR. Skipping."
    fi
}

uninstall_paho_mqtt_c() {
    echo "Uninstalling Paho MQTT C client library..."

    # Remove installed files manually
    sudo rm -f /usr/local/lib/libpaho-mqtt3c.*
    sudo rm -f /usr/local/lib/libpaho-mqtt3cs.*
    sudo rm -f /usr/local/lib/libpaho-mqtt3a.*
    sudo rm -f /usr/local/lib/libpaho-mqtt3as.*
    sudo rm -f /usr/local/include/MQTTClient.h
    sudo rm -f /usr/local/include/MQTTAsync.h
    sudo rm -f /usr/local/include/MQTTProperties.h
    sudo rm -f /usr/local/include/MQTTReasonCodes.h
    sudo rm -f /usr/local/include/MQTTSubscribeOpts.h

    # Refresh shared library cache
    if [ "$OS" == "Linux" ]; then
        sudo ldconfig
    fi

    echo "Paho MQTT C client library uninstalled."
}

uninstall_labjack_ljm() {
    echo "Uninstalling LabJack LJM library..."

    if [ "$OS" == "Linux" ]; then
        echo "Uninstalling LabJack LJM library on Linux..."

        # Run the uninstall script provided by LabJack if available
        if [ -f "/usr/local/share/LabJack/LJM/ljm_uninstall.sh" ]; then
            sudo /usr/local/share/LabJack/LJM/ljm_uninstall.sh
            echo "LabJack LJM library uninstalled."
        else
            echo "LabJack LJM uninstaller not found. Attempting manual removal."

            # Remove files manually
            sudo rm -rf /usr/local/lib/libLabJackM.so*
            sudo rm -rf /usr/local/include/LabJackM.h
            sudo rm -rf /usr/local/share/LabJack/
            echo "LabJack LJM library files removed."
        fi

    elif [ "$OS" == "Darwin" ]; then
        echo "Uninstalling LabJack LJM library on macOS..."

        # Uninstall using the provided uninstaller script if available
        if [ -f "/Applications/LabJack/LabJack LJM Uninstaller.app/Contents/MacOS/LabJack LJM Uninstaller" ]; then
            sudo "/Applications/LabJack/LabJack LJM Uninstaller.app/Contents/MacOS/LabJack LJM Uninstaller" --unattended
            echo "LabJack LJM library uninstalled."
        else
            echo "LabJack LJM uninstaller not found. Attempting manual removal."

            # Remove files manually
            sudo rm -rf /usr/local/lib/libLabJackM.*
            sudo rm -rf /usr/local/include/LabJackM.h
            sudo rm -rf /Applications/LabJack/
            sudo rm -rf /usr/local/share/LabJack/LJM/
            echo "LabJack LJM library files removed."
        fi

    else
        echo "Unsupported OS for LabJack LJM uninstallation."
        exit 1
    fi
}

# Prompt the user for confirmation
echo "WARNING: This script will uninstall the Zig compiler, Paho MQTT C client library, and LabJack LJM library from your system."
read -p "Do you wish to continue? (y/N): " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Uninstallation aborted."
    exit 0
fi

# Perform uninstallation
uninstall_zig
uninstall_paho_mqtt_c
uninstall_labjack_ljm

echo "All dependencies have been uninstalled successfully."