#!/bin/bash
set -x

# Use particular docker and kubernetes versions. When I've tried to upgrade, I've seen slowdowns in 
# pod creation.
DOCKER_VERSION_STRING=5:20.10.12~3-0~ubuntu-focal
KUBERNETES_VERSION_STRING=1.23.3-00

# Unlike home directories, this directory will be included in the image
OW_USER_GROUP=owuser
INSTALL_DIR=/home/cloudlab-openwhisk

# General updates
sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y

# Openwhisk build dependencies
sudo apt install -y nodejs npm default-jre default-jdk

# In order to use wskdev commands, need to run this:
sudo apt install -y python

# Pip is useful
sudo apt install -y python3-pip
python3 -m pip install --upgrade pip

# Install docker (https://docs.docker.com/engine/install/ubuntu/)
sudo apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce=$DOCKER_VERSION_STRING docker-ce-cli=$DOCKER_VERSION_STRING containerd.io docker-compose-plugin

# Set to use cgroupdriver
echo -e '{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker || (echo "ERROR: Docker installation failed, exiting." && exit -1)
sudo docker run hello-world | grep "Hello from Docker!" || (echo "ERROR: Docker installation failed, exiting." && exit -1)

# Install Kubernetes
sudo curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet=$KUBERNETES_VERSION_STRING kubeadm=$KUBERNETES_VERSION_STRING kubectl=$KUBERNETES_VERSION_STRING

# Set to use private IP
sudo sed -i.bak "s/KUBELET_CONFIG_ARGS=--config=\/var\/lib\/kubelet\/config\.yaml/KUBELET_CONFIG_ARGS=--config=\/var\/lib\/kubelet\/config\.yaml --node-ip=REPLACE_ME_WITH_IP/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# Download and install the OpenWhisk CLI
wget https://github.com/apache/openwhisk-cli/releases/download/latest/OpenWhisk_CLI-latest-linux-386.tgz
tar -xvf OpenWhisk_CLI-latest-linux-386.tgz
sudo mv wsk /usr/local/bin/wsk

# Download and install helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
sudo ./get_helm.sh

# Create $OW_USER_GROUP group so $INSTALL_DIR can be accessible to everyone
sudo groupadd $OW_USER_GROUP
sudo mkdir $INSTALL_DIR
sudo chgrp -R $OW_USER_GROUP $INSTALL_DIR
sudo chmod -R o+rw $INSTALL_DIR

# Download openwhisk-deploy-kube repo
git clone https://github.com/apache/openwhisk-deploy-kube $INSTALL_DIR/openwhisk-deploy-kube
sudo chgrp -R $OW_USER_GROUP $INSTALL_DIR
sudo chmod -R o+rw $INSTALL_DIR

