#!/bin/bash

# Unlike home directories, this directory will be included in the image
INSTALL_DIR=/home/openwhisk-kubernetes

# Install docker
sudo apt update
sudo apt install -y docker.io
sudo systemctl start docker
sudo systemctl enable docker

# Prereq for docker rootless, which will be installed later
sudo apt install uidmap
# curl -fsSL https://get.docker.com/rootless | sh

# Install Kubernetes
# From: https://linuxconfig.org/how-to-install-kubernetes-on-ubuntu-20-04-focal-fossa-linux
sudo apt install apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
sudo apt install -y kubeadm kubelet kubectl
sudo apt-mark hold kubeadm kubelet kubectl

# Packages needed for standalone openwhisk build
sudo apt install -y nodejs npm default-jre

# Needed for OpenWhisk tests
sudo apt install -y default-jdk

# Download and install Helm
# Note that OpenWhisk now requires Helm 3 or above
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
sudo ./get_helm.sh

# Create directory and clone the OpenWhisk Kubernetes Deployment repo
sudo groupadd owk8s
sudo mkdir $INSTALL_DIR
sudo git clone https://github.com/apache/openwhisk-deploy-kube.git $INSTALL_DIR/openwhisk-deploy-kube
sudo cp mycluster.yaml $INSTALL_DIR/openwhisk-deploy-kube/mycluster.yaml

# Prepare to install calico (<50 nodes version)
cd $INSTALL_DIR
sudo curl https://docs.projectcalico.org/manifests/calico.yaml -O

# Fix permissions
sudo chgrp -R owk8s $INSTALL_DIR
sudo chmod -R o+rw $INSTALL_DIR

# Download and install the OpenWhisk CLI
wget https://github.com/apache/openwhisk-cli/releases/download/latest/OpenWhisk_CLI-latest-linux-386.tgz
tar -xvf OpenWhisk_CLI-latest-linux-386.tgz
sudo mv wsk /usr/local/bin/wsk

# In order to use wskdev commands, need to run this:
sudo apt install python
