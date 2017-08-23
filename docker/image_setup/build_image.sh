#!/bin/bash

set -eux

export DEBIAN_FRONTEND=noninteractive
SETUP_DIR=/image_setup

apt-get update
apt-get upgrade -y
apt-get install -y --no-install-recommends apt-transport-https ca-certificates

echo "deb https://apt.dockerproject.org/repo ubuntu-xenial main" > /etc/apt/sources.list.d/docker-engine.list
echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu xenial stable edge" > /etc/apt/sources.list.d/docker-ce.list

apt-key add ${SETUP_DIR}/2C52609D.gpg
apt-key add ${SETUP_DIR}/0EBFCD88.gpg

apt-get update
apt-get -y install --no-install-recommends \
    cron \
    curl \
    nodejs \
    npm \
    python \
    python-pip \
    python-setuptools \
    python-pkg-resources \
    git \
    wget \
    lftp \
    par2 \
    openssh-client \
    python-dev \
    gcc make g++ \
    libffi-dev \
    iptables \
    libltdl7 \
    libnfnetlink0 \
    libxtables11
update-alternatives --install /usr/bin/node nodejs /usr/bin/nodejs 100
npm install -g underscore-cli
pip install --upgrade pip
pip install boto shyaml pexpect cryptography paramiko fasteners

bash ${SETUP_DIR}/install_duplicity.sh

mv ${SETUP_DIR}/docker-backup-entrypoint.sh /
cp -v -R ${SETUP_DIR}/etc/* /etc/

apt-get -y purge \
    python-dev python-setuptools python-pip npm \
    gcc make g++

apt-get -y autoremove
apt-get clean

# Preload all docker-engine packages
docker_engine_packages=$(apt-cache madison docker-engine | awk -F "|" '{ print $2 }' | tr -d " ")
for package_version in $docker_engine_packages
do
    apt-get install -y --no-install-recommends --download-only docker-engine=$package_version
done

# Preload all docker-ce packages
docker_engine_packages=$(apt-cache madison docker-ce | awk -F "|" '{ print $2 }' | tr -d " ")
for package_version in $docker_engine_packages
do
    apt-get install -y --no-install-recommends --download-only docker-ce=$package_version
done

# Do some cleaning
rm -rf \
    /usr/share/man/* \
    /tmp/* \
    /root/.npm
