#!/bin/bash

# This script runs from the top of the project directory and
# creates the filesystem image for the MeshChat API package.

IPK_DIR=$1
OSNAME=$2

# Populate the CONTROL portion of the package
mkdir -p $IPK_DIR/CONTROL
cp -p package/meshchat/* $IPK_DIR/CONTROL/
sed -i "s%\$GITHUB_SERVER_URL%$GITHUB_SERVER_URL%" $IPK_DIR/CONTROL/control
sed -i "s%\$GITHUB_REPOSITORY%$GITHUB_REPOSITORY%" $IPK_DIR/CONTROL/control

# Populate the filesystem image for the package
if [[ "$OSNAME" == "debian" ]]; then
    install -d $IPK_DIR/DEBIAN
    install -m 644 package/meshchat/* $IPK_DIR/DEBIAN
    install -d $IPK_DIR/var/www/html/meshchat
    install www/* $IPK_DIR/var/www/html/meshchat
    install -d $IPK_DIR/usr/lib/cgi-bin
    install -m 755 meshchat $IPK_DIR/usr/lib/cgi-bin
    install -m 644 meshchatlib.lua $IPK_DIR/usr/lib/cgi-bin
    install -m 644 meshchatconfig.lua $IPK_DIR/usr/lib/cgi-bin
    install -D support/meshchatsync-init.d -m 755 $IPK_DIR/etc/init.d/meshchatsync
    install -D support/meshchatsync -m 755 $IPK_DIR/usr/local/bin/meshchatsync
    install -d $IPK_DIR/usr/local/lib/lua/5.4/net
    install -m 644 lib/json.lua $IPK_DIR/usr/local/lib/lua/5.4/net
elif [[ "$OSNAME" == "openwrt" ]]; then
    install -d $IPK_DIR/www/meshchat
    install www/* $IPK_DIR/www/meshchat
    install -d $IPK_DIR/www/cgi-bin
    install -m 755 meshchat $IPK_DIR/www/cgi-bin
    install -m 644 meshchatlib.lua $IPK_DIR/www/cgi-bin
    install -m 644 meshchatconfig.lua $IPK_DIR/www/cgi-bin
    install -D support/meshchatsync-init.d -m 755 $IPK_DIR/etc/init.d/meshchatsync
    install -D support/meshchatsync -m 755 $IPK_DIR/usr/local/bin/meshchatsync
    install -d $IPK_DIR/usr/lib/lua
    install -m 644 lib/json.lua $IPK_DIR/usr/lib/lua
fi
