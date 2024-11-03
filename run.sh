#!/bin/bash

set -e

# Set the LabJack T7 IP address
if [ -z "$LABJACK_IP" ]; then
    echo "Please set the LABJACK_IP environment variable."
    exit 1
fi

export LABJACK_IP

# Build and run the Docker Compose services
docker-compose up --build