#!/bin/bash

set -e

echo "Starting installation of dependencies for the LabJack T7 Zig program..."

# Determine the operating system
OS="$(uname -s)"
ARCH="$(uname -m)"

echo "Detected OS: $OS"
echo "Detected Architecture: $ARCH"

install_zig() {
    echo "Installing Zig compiler..."

    # Define the Zig version you want to install
    ZIG_VERSION="0.13.0"

    if [ "$OS" == "Linux" ]; then
        if [ "$ARCH" == "x86_64" ]; then
            ZIG_TAR="zig-linux-x86_64-$ZIG_VERSION.tar.xz"
        elif [[ "$ARCH" == "armv"* ]] || [[ "$ARCH" == "aarch64" ]]; then
            ZIG_TAR="zig-linux-aarch64-$ZIG_VERSION.tar.xz"
        else
            echo "Unsupported architecture for Zig installation on Linux."
            exit 1
        fi
        ZIG_URL="https://ziglang.org/download/$ZIG_VERSION/$ZIG_TAR"
    elif [ "$OS" == "Darwin" ]; then
        if [ "$ARCH" == "x86_64" ]; then
            ZIG_TAR="zig-macos-x86_64-$ZIG_VERSION.tar.xz"
        elif [ "$ARCH" == "arm64" ]; then
            ZIG_TAR="zig-macos-aarch64-$ZIG_VERSION.tar.xz"
        else
            echo "Unsupported architecture for Zig installation on macOS."
            exit 1
        fi
        ZIG_URL="https://ziglang.org/download/$ZIG_VERSION/$ZIG_TAR"
    else
        echo "Unsupported OS for Zig installation."
        exit 1
    fi

    ZIG_INSTALL_DIR="/usr/local/zig"

    if [ -d "$ZIG_INSTALL_DIR" ]; then
        echo "Zig is already installed in $ZIG_INSTALL_DIR"
    else
        echo "Downloading Zig from $ZIG_URL"
        curl -L "$ZIG_URL" -o "$ZIG_TAR"
        echo "Extracting Zig..."
        sudo mkdir -p "$ZIG_INSTALL_DIR"
        sudo tar -xf "$ZIG_TAR" -C "$ZIG_INSTALL_DIR" --strip-components=1
        rm "$ZIG_TAR"
        echo "Zig installed in $ZIG_INSTALL_DIR"
    fi

    # Add Zig to PATH if not already present
    if ! command -v zig &> /dev/null; then
        if [ "$SHELL" == "/bin/zsh" ]; then
            echo 'export PATH=$PATH:/usr/local/zig' >> ~/.zshrc
            export PATH=$PATH:/usr/local/zig
        else
            echo 'export PATH=$PATH:/usr/local/zig' >> ~/.bashrc
            export PATH=$PATH:/usr/local/zig
        fi
    fi
}

install_paho_mqtt_c() {
    echo "Installing Paho MQTT C client library..."

    PAHO_DIR="paho.mqtt.c"
    PAHO_REPO="https://github.com/eclipse/paho.mqtt.c.git"

    if [ -d "$PAHO_DIR" ]; then
        echo "Paho MQTT C client library already cloned."
    else
        echo "Cloning Paho MQTT C client library from $PAHO_REPO"
        git clone "$PAHO_REPO"
    fi

    echo "Building Paho MQTT C client library..."
    cd "$PAHO_DIR"
    git checkout v1.3.9  # Use a stable version
    mkdir -p build
    cd build
    if [ "$OS" == "Linux" ]; then
        cmake -DPAHO_WITH_SSL=ON ..
    elif [ "$OS" == "Darwin" ]; then
        cmake -DPAHO_WITH_SSL=ON -DOPENSSL_ROOT_DIR=$(brew --prefix openssl) -DOPENSSL_LIB_SEARCH_PATH=$(brew --prefix openssl)/lib -DOPENSSL_INCLUDE_DIR=$(brew --prefix openssl)/include ..
    fi
    make
    sudo make install
    sudo ldconfig || true  # Refresh shared library cache; ignore if not applicable
    cd ../..
    echo "Paho MQTT C client library installed."
}

install_labjack_ljm() {
    echo "Installing LabJack LJM library..."

    if [ "$OS" == "Linux" ]; then
        echo "Downloading LabJack LJM library for Linux..."

        LJM_ZIP="LabJack-LJM.zip"
        LJM_URL="https://files.labjack.com/installers/LJM/Linux/x64/release/LabJack-LJM_2024-06-10.zip"

        curl -L "$LJM_URL" -o "$LJM_ZIP"
        echo "Extracting LabJack LJM installer..."
        unzip "$LJM_ZIP" -d "labjack_ljm_installer"
        rm "$LJM_ZIP"

        echo "Running LabJack LJM installer..."
        cd labjack_ljm_installer
        sudo ./install.sh
        cd ..
        rm -rf labjack_ljm_installer

        echo "LabJack LJM library installed on Linux."

    elif [ "$OS" == "Darwin" ]; then
        echo "Downloading LabJack LJM library for macOS..."

        LJM_ZIP="LabJack-LJM.zip"
        LJM_URL="https://files.labjack.com/installers/LJM/macOS/ARM64/release/LabJack-LJM_2024-05-20.zip"

        curl -L "$LJM_URL" -o "$LJM_ZIP"
        echo "Extracting LabJack LJM installer..."
        unzip "$LJM_ZIP" -d "labjack_ljm_installer"
        rm "$LJM_ZIP"

        echo "Running LabJack LJM installer..."
        cd labjack_ljm_installer
        sudo installer -pkg LabJack-LJM_2024-05-20/LabJack-LJM_2024-05-20.pkg -target /
        cd ..
        rm -rf labjack_ljm_installer

        echo "LabJack LJM library installed on macOS."

    else
        echo "Unsupported OS for LabJack LJM installation."
        exit 1
    fi
}

# Install dependencies based on OS
if [ "$OS" == "Linux" ] || [ "$OS" == "Darwin" ]; then
    if [ "$OS" == "Linux" ]; then
        echo "Updating package lists..."
        sudo apt-get update

        echo "Installing required packages..."
        sudo apt-get install -y git curl build-essential cmake libssl-dev unzip

    elif [ "$OS" == "Darwin" ]; then
        echo "Checking for Homebrew..."
        if ! command -v brew &> /dev/null; then
            echo "Homebrew not found. Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi

        echo "Installing required packages..."
        brew update
        brew install git curl cmake openssl unzip

        # For macOS, set OpenSSL environment variables
        export OPENSSL_ROOT_DIR=$(brew --prefix openssl)
        export OPENSSL_LIB_DIR=$(brew --prefix openssl)/lib
        export OPENSSL_INCLUDE_DIR=$(brew --prefix openssl)/include
    fi

    install_zig
    install_paho_mqtt_c
    install_labjack_ljm

    echo "All dependencies have been installed successfully."
else
    echo "Unsupported operating system: $OS"
    exit 1
fi