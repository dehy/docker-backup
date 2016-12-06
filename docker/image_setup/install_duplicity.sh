#!/bin/bash

DUPLICITY_VERSION="0.7.10"

SCRIPT_DIR="$(dirname $0)"

apt-get update
apt-get install -y --no-install-recommends \
    python python-setuptools gcc \
    python-dev rsync librsync1 librsync-dev

cd "${SCRIPT_DIR}/"
tar xvf duplicity-${DUPLICITY_VERSION}.tar.gz
cd duplicity-${DUPLICITY_VERSION}

python setup.py install
pip install lockfile

cd "${SCRIPT_DIR}/"
rm -rf "${SCRIPT_DIR}/duplicity-${DUPLICITY_VERSION}*"

apt-get purge -y \
    python-setuptools gcc \
    python-dev librsync-dev
