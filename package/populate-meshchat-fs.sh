#!/bin/bash

# This script runs from the top of the project directory and
# creates the filesystem image for the MeshChat API package.

IPK_DIR=$1

# Populate the CONTROL portion of the package
mkdir -p $IPK_DIR/CONTROL
cp -p package/meshchat/* $IPK_DIR/CONTROL/
sed -i "s%\$GITHUB_SERVER_URL%$GITHUB_SERVER_URL%" $IPK_DIR/CONTROL/control
sed -i "s%\$GITHUB_REPOSITORY%$GITHUB_REPOSITORY%" $IPK_DIR/CONTROL/control

# Populate the filesystem image for the package
install -d $IPK_DIR/www
install www/* $IPK_DIR/www
install -d $IPK_DIR/www/cgi-bin
install cgi-bin/* $IPK_DIR/www/cgi-bin
install -D support/init.d/meshchatsync $IPK_DIR/etc/init.d/meshchatsync
install -D meshchatsync $IPK_DIR/usr/local/bin/meshchatsync
