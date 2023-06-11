#!/bin/bash

# This script runs from the top of the project directory and
# creates the filesystem image for the MeshChat API package.

IPK_DIR=$1

mkdir -p $IPK_DIR/CONTROL
cp -p package/meshchat-api/* $IPK_DIR/CONTROL/
sed "s%\$GITHUB_SERVER_URL%$GITHUB_SERVER_URL%" $IPK_DIR/CONTROL/control
sed "s%\$GITHUB_REPOSITORY%$GITHUB_REPOSITORY%" $IPK_DIR/CONTROL/control

install -D meshchat $IPK_DIR/www/cgi-bin/meshchat

