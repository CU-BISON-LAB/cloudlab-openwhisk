#!/bin/bash

INSTALL_DIR=/home/openwhisk_kubernetes
NUM_NODES=0

disable_swap() {
    # Turn swap off and commend out swap line in /etc/fstab
    sudo swapoff -a
    if [ $? -eq 0 ]; then
        echo "> Turned off swap"
    else
        echo "***Error: Failed to turn off swap, which is necessary for Kubernetes"
        exit 1
    fi
    sudo sed -i.bak 's/UUID=.*swap/# &/' /etc/fstab
}

setup_master() {
    # initialize k8 primary node
    printf "> Starting Kubernetes... (this can take several minutes)... "
    sudo kubeadm init --apiserver-advertise-address=$NODE_IP --pod-network-cidr=10.11.0.0/16 > $INSTALL_DIR/k8s_install.log 2>&1
    if [ $? -eq 0 ]; then
        echo "Done! Output in $INSTALL_DIR/k8s_install.log"
    else
        echo ""
        echo "***Error: Error when running kubeadm init command. Check log found in $INSTALL_DIR/k8s_install.log."
        exit 1
    fi

    # set up kubectl 
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    # wait until all pods are started except 2 (the DNS pods)
    NUM_PENDING=$(sudo kubectl get pods -o wide --all-namespaces 2>&1 | grep Pending | wc -l)
    NUM_RUNNING=$(sudo kubectl get pods -o wide --all-namespaces 2>&1 | grep Running | wc -l)
    printf "> Waiting for pods to start up: "
    while [ "$NUM_PENDING" -ne 2 ] && [ "$NUM_RUNNING" -ne 5 ]
    do
        sleep 1
        printf "."
        NUM_PENDING=$(sudo kubectl get pods -o wide --all-namespaces 2>&1 | grep Pending | wc -l)
        NUM_RUNNING=$(sudo kubectl get pods -o wide --all-namespaces 2>&1 | grep Running | wc -l)
    done
    echo "Done!"
}

apply_calico() {
    kubectl apply -f calico.yaml > $INSTALL_DIR/calico_install.txt
    if [ $? -ne 0 ]; then
       echo "***Error: Error when applying calico networking. Check log found in $INSTALL_DIR/calico_install.txt"
       exit 1
    fi
    echo "> Applied Calico networking found in $INSTALL_DIR/calico.yaml. Install log found in $INSTALL_DIR/calico_install.log"
}

add_cluster_nodes() {
    echo "> On each worker node, run: "
    echo "        $ sudo $INSTALL_DIR/start.sh worker"
    echo "> Next run the command below to join each worker node to the cluster:"
    printf "        $ sudo "
    tail -n 2 $INSTALL_DIR/k8s_install.log

    read -n 10000 -t 1 discard
    read -n 1 -r -s -p $'***Press enter when all worker nodes have been added.\n'
    printf "> Detecting nodes... "
    sleep 5
    echo "Done!"

    NUM_NODES=$(sudo kubectl get nodes | wc -l)
    NUM_NODES=$((NUM_NODES-1))
    echo "> $NUM_NODES nodes detected (including the master node)."
    read -n 10000 -t 1 discard
    read -n 1 -r -s -p $'***Press any key to continue if this is correct.\n'

    echo "> Waiting for all nodes to have status of 'Ready': "
    NUM_READY=$(kubectl get nodes | grep Ready | wc -l)
    NUM_READY=$((NUM_NODES-NUM_READY))
    while [ "$NUM_READY" -ne 0 ]
    do
        sleep 1
        printf "."
        NUM_READY=$(kubectl get nodes | grep READY | wc -l)
        NUM_READY=$((NUM_NODES-NUM_READY))
    done
    echo "Done!"
}

if [ $PWD != "$INSTALL_DIR" ] ; then
    echo "***Error: Please run in $INSTALL_DIR."
    exit 1
fi

if [ $# -ne 1 ]; then
    echo "***Error: Expected 1 argument"
    echo "Usage: sudo ./setup.sh <nodetype>"
    exit 1
fi
if [ $1 != "master" -a $1 != 'worker' ] ; then
    echo "***Error: <nodetype> should be 'master' or 'worker'"
    echo "Usage: sudo ./setup.sh <nodetype>"
    exit 1
fi

echo "> Welcome to the start.sh script! This will set up the current node to be part of a Kubernetes/Openwhisk deployment. Please follow all directions carefully."

# Kubernetes does not support swap, so we must disable it
disable_swap

# grab the node IP address on the private network
NODE_IP=$(ifconfig | grep 10.10.1 | awk '{ print $2 }')
echo "> Node IP is $NODE_IP"

sudo sed -i.bak "s/REPLACE_ME_WITH_IP/$NODE_IP/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
echo "> Updated /etc/systemd/system/kubelet.service.d/10-kubeadm.conf with node IP"

# At this point, the worker is fully configured until it is time for the worker to join the cluster.
if [ $1 == "worker" ] ; then
    echo "> Worker node is now ready to run the 'kubeadm join' command!"
    echo "> Exiting."
    exit
fi

# initialize kubernetes on the master node
setup_master

# Apply calico networking
apply_calico

# Coordinate master to add nodes to the kubernetes cluster
add_cluster_nodes
