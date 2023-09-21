#!/bin/bash

# This script runs from the top of the project directory and
# updates the version number in the control file for the package
# being built.

IPK_DIR=$1

if [[ "$GITHUB_REF_TYPE" == 'tag' ]]; then
    # ideally should only get version tags (i.e. 'v' followed by a number)
    if [[ "${GITHUB_REF_NAME}" =~ ^v[0-9].* ]]; then
        version="${GITHUB_REF_NAME#v}"
    fi
else
    # branch gets date code-branch_name-commit
    date=$(date +%Y%m%d)
    branch=$(git rev-parse --abbrev-ref HEAD)
    commit=$(git rev-parse --short HEAD)
    version="${date}-${branch}-${commit}"
fi

sed -i "s/^Version:.*/Version: $version/" $IPK_DIR/CONTROL/control

# Update the version in meshchatconfig.lua if present
if [[ -f $IPK_DIR/www/cgi-bin/meshchatconfig.lua ]]; then
    sed -i "s/^app_version.*$/app_version                = \"${version}\"/" $IPK_DIR/www/cgi-bin/meshchatconfig.lua
fi
