#!/bin/bash

BASE_IP="10.10.1."
SECONDARY_PORT=3000
INSTALL_DIR=/home/openwhisk-kubernetes
NUM_MIN_ARGS=2
PRIMARY_ARG="primary"
SECONDARY_ARG="secondary"
NUM_PRIMARY_ARGS=7
USAGE=$'Usage:\n\t./start.sh secondary <node_ip>\n\t./start.sh primary <node_ip> <num_nodes>'

disable_swap() {
    # Turn swap off and comment out swap line in /etc/fstab
    sudo swapoff -a
    if [ $? -eq 0 ]; then
        echo "> Turned off swap"
    else
        echo "***Error: Failed to turn off swap, which is necessary for Kubernetes"
        exit -1
    fi
    sudo sed -i.bak 's/UUID=.*swap/# &/' /etc/fstab
}

setup_secondary() {
    coproc nc -l $1 $SECONDARY_PORT

    echo "> Waiting for command to join kubernetes cluster"
    while true; do
        read -ru ${COPROC[0]} cmd
        case $cmd in
            *"kube"*)
                MY_CMD=$cmd
                break 
                ;;
            *)
                ;;
        esac
    done

    # Remove forward slash, since original command was on two lines
    MY_CMD=$(echo sudo $MY_CMD | sed 's/\\//')

    echo "> Command to execute is: $MY_CMD"

    # run command to join kubernetes cluster
    eval $MY_CMD
    echo "Done!"

    # Client terminates, so we don't need to.
    # kill "$COPROC_PID"
}

setup_primary() {
    # initialize k8 primary node
    printf "> Starting Kubernetes... (this can take several minutes)... "
    sudo kubeadm init --apiserver-advertise-address=$1 --pod-network-cidr=10.11.0.0/16 > $INSTALL_DIR/k8s_install.log 2>&1
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
    NUM_PENDING=$(kubectl get pods -o wide --all-namespaces 2>&1 | grep Pending | wc -l)
    NUM_RUNNING=$(kubectl get pods -o wide --all-namespaces 2>&1 | grep Running | wc -l)
    printf "> Waiting for pods to start up: "
    while [ "$NUM_PENDING" -ne 2 ] && [ "$NUM_RUNNING" -ne 5 ]
    do
        sleep 1
        printf "."
        NUM_PENDING=$(kubectl get pods -o wide --all-namespaces 2>&1 | grep Pending | wc -l)
        NUM_RUNNING=$(kubectl get pods -o wide --all-namespaces 2>&1 | grep Running | wc -l)
    done
    echo "Done!"
}

apply_calico() {
    kubectl apply -f $INSTALL_DIR/calico.yaml > $INSTALL_DIR/calico_install.txt
    if [ $? -ne 0 ]; then
       echo "***Error: Error when applying calico networking. Check log found in $INSTALL_DIR/calico_install.txt"
       exit 1
    fi
    echo "> Applied Calico networking found in $INSTALL_DIR/calico.yaml. Install log found in $INSTALL_DIR/calico_install.log"
}


add_cluster_nodes() {
    REMOTE_CMD=$(tail -n 2 $INSTALL_DIR/k8s_install.log)
    echo "> Remote command is: $REMOTE_CMD"

    for (( i=2; i<=$1; i++ ))
    do
        SECONDARY_IP=$BASE_IP$i
        echo $SECONDARY_IP
        exec 3<>/dev/tcp/$SECONDARY_IP/$SECONDARY_PORT
        echo $REMOTE_CMD 1>&3
        exec 3<&-
    done

    echo "> Waiting for all nodes to have status of 'Ready': "
    NUM_READY=$(kubectl get nodes | grep Ready | wc -l)
    NUM_READY=$(($1-NUM_READY))
    while [ "$NUM_READY" -ne 0 ]
    do
        sleep 1
        printf "."
        NUM_READY=$(kubectl get nodes | grep Ready | wc -l)
        NUM_READY=$(($1-NUM_READY))
    done
    echo "Done!"
}

# Check the min number of arguments
if [ $# -lt $NUM_MIN_ARGS ]; then
    echo "***Error: Expected at least $NUM_MIN_ARGS arguments."
    echo "$USAGE"
    exit -1
fi

# Check to make sure the first argument is as expected
if [ $1 != $PRIMARY_ARG -a $1 != $SECONDARY_ARG ] ; then
    echo "***Error: First arg should be '$PRIMARY_ARG' or '$SECONDARY_ARG'"
    echo "$USAGE"
    exit -1
fi

# Do common things that are necessary for both primary and secondary nodes
sudo usermod -a -G owk8s $USER

# Kubernetes does not support swap, so we must disable it
disable_swap

# Use second argument (node IP) to replace filler in kubeadm configuration
sudo sed -i.bak "s/REPLACE_ME_WITH_IP/$2/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# At this point, a secondary node is fully configured until it is time for the node to join the cluster.
if [ $1 == $SECONDARY_ARG ] ; then
    setup_secondary $2
    exit 0
fi

# Check the min number of arguments
if [ $# -ne $NUM_PRIMARY_ARGS ]; then
    echo "***Error: Expected at least $NUM_PRIMARY_ARGS arguments."
    echo "$USAGE"
    exit -1
fi

# Finish setting up the primary node
# Argument is node_ip
setup_primary $2

# Apply calico networking
apply_calico

# Coordinate master to add nodes to the kubernetes cluster
# Argument is number of secondary nodes
add_cluster_nodes $3
