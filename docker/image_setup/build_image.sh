#!/bin/bash

set -eux

export DEBIAN_FRONTEND=noninteractive
SETUP_DIR=/image_setup

apt-get update
apt-get upgrade -y
apt-get install -y --no-install-recommends apt-transport-https ca-certificates

echo "deb https://apt.dockerproject.org/repo ubuntu-xenial main" > /etc/apt/sources.list.d/docker.list

apt-key add ${SETUP_DIR}/2C52609D.gpg

apt-get update
apt-get -y install --no-install-recommends \
    cron \
    curl \
    nodejs \
    npm \
    python-pip \
    python-setuptools \
    git \
    wget \
    lftp \
    par2 \
    gcc make g++
update-alternatives --install /usr/bin/node nodejs /usr/bin/nodejs 100
npm install -g underscore-cli
pip install --upgrade pip
pip install boto shyaml pexpect

bash ${SETUP_DIR}/install_duplicity.sh

mv ${SETUP_DIR}/docker-backup-entrypoint.sh /
cp -v -R ${SETUP_DIR}/etc/* /etc/

apt-get -y purge \
    python-pip python-setuptools npm \
    gcc make g++

apt-get -y autoremove
apt-get clean

# Preload all docker-engine packages
docker_engine_packages=$(apt-cache madison docker-engine | awk -F "|" '{ print $2 }' | tr -d " ")
for package_version in $docker_engine_packages
do
    apt-get install -y --no-install-recommends --download-only docker-engine=$package_version
done

# Do some cleaning
rm -rf \
    /usr/share/man/* \
    /tmp/* \
    /root/.npm
