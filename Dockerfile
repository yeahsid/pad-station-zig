# Use Ubuntu as the base image
FROM ubuntu:20.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV ZIG_INSTALL_DIR=/usr/local/zig

# Copy your install script into the container
COPY install_dependencies.sh /app/install_dependencies.sh

# Set the working directory
WORKDIR /app

# Install necessary packages for running the install script
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    curl \
    build-essential \
    libssl-dev \
    wget \
    ca-certificates \
    cmake \
    unzip \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Make the install script executable
RUN chmod +x /app/install_dependencies.sh

# Run the install script
RUN /app/install_dependencies.sh

# Copy your Zig application source code into the container
COPY . /app

# Build the Zig application
RUN zig build -Drelease-fast

# Expose any necessary ports (e.g., for MQTT communication if needed)
EXPOSE 1883

# Command to run your application
CMD ["./zig-out/bin/labjack_mqtt"]