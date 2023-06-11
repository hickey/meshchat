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
    # branch gets date code
    version=$(date +%Y%m%d)
fi

sed -i "s/^Version:.*/Version: $version/" $IPK_DIR/CONTROL/control
