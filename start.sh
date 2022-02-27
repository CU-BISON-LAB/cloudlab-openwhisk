#!/bin/bash

set -x
BASE_IP="10.10.1."
SECONDARY_PORT=3000
INSTALL_DIR=/home/cloudlab-openwhisk
NUM_MIN_ARGS=3
PRIMARY_ARG="primary"
SECONDARY_ARG="secondary"
USAGE=$'Usage:\n\t./start.sh secondary <node_ip> <start_kubernetes>\n\t./start.sh primary <node_ip> <num_nodes> <start_kubernetes> <deploy_openwhisk> <invoker_count> <invoker_engine>'
NUM_PRIMARY_ARGS=7
PROFILE_GROUP="profileuser"

configure_docker_storage() {
    printf "%s: %s\n" "$(date +"%T.%N")" "Configuring docker storage"
    sudo mkdir /mydata/docker
    echo -e '{
        "exec-opts": ["native.cgroupdriver=systemd"],
        "log-driver": "json-file",
        "log-opts": {
            "max-size": "100m"
        },
        "storage-driver": "overlay2",
        "data-root": "/mydata/docker"
    }' | sudo tee /etc/docker/daemon.json
    sudo systemctl restart docker || (echo "ERROR: Docker installation failed, exiting." && exit -1)
    sudo docker run hello-world | grep "Hello from Docker!" || (echo "ERROR: Docker installation failed, exiting." && exit -1)
    printf "%s: %s\n" "$(date +"%T.%N")" "Configured docker storage to use mountpoint"
}

disable_swap() {
    # Turn swap off and comment out swap line in /etc/fstab
    sudo swapoff -a
    if [ $? -eq 0 ]; then   
        printf "%s: %s\n" "$(date +"%T.%N")" "Turned off swap"
    else
        echo "***Error: Failed to turn off swap, which is necessary for Kubernetes"
        exit -1
    fi
    sudo sed -i.bak 's/UUID=.*swap/# &/' /etc/fstab
}

setup_secondary() {
    coproc nc { nc -l $1 $SECONDARY_PORT; }
    while true; do
        printf "%s: %s\n" "$(date +"%T.%N")" "Waiting for command to join kubernetes cluster, nc pid is $nc_PID"
        read -r -u${nc[0]} cmd
        case $cmd in
            *"kube"*)
                MY_CMD=$cmd
                break 
                ;;
            *)
	    	printf "%s: %s\n" "$(date +"%T.%N")" "Read: $cmd"
                ;;
        esac
	if [ -z "$nc_PID" ]
	then
	    printf "%s: %s\n" "$(date +"%T.%N")" "Restarting listener via netcat..."
	    coproc nc { nc -l $1 $SECONDARY_PORT; }
	fi
    done

    # Remove forward slash, since original command was on two lines
    MY_CMD=$(echo sudo $MY_CMD | sed 's/\\//')

    printf "%s: %s\n" "$(date +"%T.%N")" "Command to execute is: $MY_CMD"

    # run command to join kubernetes cluster
    eval $MY_CMD
    printf "%s: %s\n" "$(date +"%T.%N")" "Done!"
}

setup_primary() {
    # initialize k8 primary node
    printf "%s: %s\n" "$(date +"%T.%N")" "Starting Kubernetes... (this can take several minutes)... "
    sudo kubeadm init --apiserver-advertise-address=$1 --pod-network-cidr=10.11.0.0/16 > $INSTALL_DIR/k8s_install.log 2>&1
    if [ $? -eq 0 ]; then
        printf "%s: %s\n" "$(date +"%T.%N")" "Done! Output in $INSTALL_DIR/k8s_install.log"
    else
        echo ""
        echo "***Error: Error when running kubeadm init command. Check log found in $INSTALL_DIR/k8s_install.log."
        exit 1
    fi

    # Set up kubectl for all users
    for FILE in /users/*; do
        CURRENT_USER=${FILE##*/}
        sudo mkdir /users/$CURRENT_USER/.kube
        sudo cp /etc/kubernetes/admin.conf /users/$CURRENT_USER/.kube/config
        sudo chown -R $CURRENT_USER:$PROFILE_GROUP /users/$CURRENT_USER/.kube
	printf "%s: %s\n" "$(date +"%T.%N")" "set /users/$CURRENT_USER/.kube to $CURRENT_USER:$PROFILE_GROUP!"
	ls -lah /users/$CURRENT_USER/.kube
    done
    printf "%s: %s\n" "$(date +"%T.%N")" "Done!"
}

apply_calico() {
    # https://projectcalico.docs.tigera.io/getting-started/kubernetes/helm
    helm repo add projectcalico https://projectcalico.docs.tigera.io/charts > $INSTALL_DIR/calico_install.log 2>&1 
    if [ $? -ne 0 ]; then
       echo "***Error: Error when loading helm calico repo. Log written to $INSTALL_DIR/calico_install.log"
       exit 1
    fi
    printf "%s: %s\n" "$(date +"%T.%N")" "Loaded helm calico repo"

    helm install calico projectcalico/tigera-operator --version v3.22.0 >> $INSTALL_DIR/calico_install.log 2>&1
    if [ $? -ne 0 ]; then
       echo "***Error: Error when installing calico with helm. Log appended to $INSTALL_DIR/calico_install.log"
       exit 1
    fi
    printf "%s: %s\n" "$(date +"%T.%N")" "Applied Calico networking from "

    # wait for calico pods to be in ready state
    printf "%s: %s\n" "$(date +"%T.%N")" "Waiting for calico pods to have status of 'Running': "
    NUM_PODS=$(kubectl get pods -n calico-system | wc -l)
    NUM_RUNNING=$(kubectl get pods -n calico-system | grep " Running" | wc -l)
    NUM_RUNNING=$((NUM_PODS-NUM_RUNNING))
    while [ "$NUM_RUNNING" -ne 0 ]
    do
        sleep 1
        printf "."
        NUM_RUNNING=$(kubectl get pods -n calico-system | grep " Running" | wc -l)
        NUM_RUNNING=$((NUM_PODS-NUM_RUNNING))
    done
    printf "%s: %s\n" "$(date +"%T.%N")" "Calico running!"
}

add_cluster_nodes() {
    REMOTE_CMD=$(tail -n 2 $INSTALL_DIR/k8s_install.log)
    printf "%s: %s\n" "$(date +"%T.%N")" "Remote command is: $REMOTE_CMD"

    NUM_REGISTERED=$(kubectl get nodes | wc -l)
    NUM_REGISTERED=$(($1-NUM_REGISTERED+1))
    counter=0
    while [ "$NUM_REGISTERED" -ne 0 ]
    do 
	sleep 2
        printf "%s: %s\n" "$(date +"%T.%N")" "Registering nodes, attempt #$counter, registered=$NUM_REGISTERED"
        for (( i=2; i<=$1; i++ ))
        do
            SECONDARY_IP=$BASE_IP$i
            echo $SECONDARY_IP
            exec 3<>/dev/tcp/$SECONDARY_IP/$SECONDARY_PORT
            echo $REMOTE_CMD 1>&3
            exec 3<&-
        done
	counter=$((counter+1))
        NUM_REGISTERED=$(kubectl get nodes | wc -l)
        NUM_REGISTERED=$(($1-NUM_REGISTERED+1)) 
    done

    printf "%s: %s\n" "$(date +"%T.%N")" "Waiting for all nodes to have status of 'Ready': "
    NUM_READY=$(kubectl get nodes | grep " Ready" | wc -l)
    NUM_READY=$(($1-NUM_READY))
    while [ "$NUM_READY" -ne 0 ]
    do
        sleep 1
        printf "."
        NUM_READY=$(kubectl get nodes | grep " Ready" | wc -l)
        NUM_READY=$(($1-NUM_READY))
    done
    printf "%s: %s\n" "$(date +"%T.%N")" "Done!"
}

prepare_for_openwhisk() {
    # Args: 1 = IP, 2 = num nodes, 3 = num invokers, 4 = invoker engine
    # Iterate over each node and set the openwhisk role
    # From https://superuser.com/questions/284187/bash-iterating-over-lines-in-a-variable

    NODE_NAMES=$(kubectl get nodes -o name)
    CORE_NODES=$(($2-$3))
    counter=0
    while IFS= read -r line; do
	if [ $counter -lt $CORE_NODES ] ; then
	    printf "%s: %s\n" "$(date +"%T.%N")" "Skipped labelling non-invoker node ${line:5}"
        else
            kubectl label nodes ${line:5} openwhisk-role=invoker
            if [ $? -ne 0 ]; then
                echo "***Error: Failed to set openwhisk role to invoker on ${line:5}."
                exit -1
            fi
	    printf "%s: %s\n" "$(date +"%T.%N")" "Labelled ${line:5} as openwhisk invoker node"
	fi
	counter=$((counter+1))
    done <<< "$NODE_NAMES"
    printf "%s: %s\n" "$(date +"%T.%N")" "Finished labelling nodes."

    kubectl create namespace openwhisk
    if [ $? -ne 0 ]; then
        echo "***Error: Failed to create openwhisk namespace"
        exit 1
    fi
    printf "%s: %s\n" "$(date +"%T.%N")" "Created openwhisk namespace in Kubernetes."

    cp /local/repository/mycluster.yaml $INSTALL_DIR/openwhisk-deploy-kube/mycluster.yaml
    sed -i.bak "s/REPLACE_ME_WITH_IP/$1/g" $INSTALL_DIR/openwhisk-deploy-kube/mycluster.yaml
    sed -i.bak "s/REPLACE_ME_WITH_INVOKER_ENGINE/$4/g" $INSTALL_DIR/openwhisk-deploy-kube/mycluster.yaml
    sed -i.bak "s/REPLACE_ME_WITH_INVOKER_COUNT/$3/g" $INSTALL_DIR/openwhisk-deploy-kube/mycluster.yaml
    sudo chown $USER:$PROFILE_GROUP $INSTALL_DIR/openwhisk-deploy-kube/mycluster.yaml
    sudo chmod -R g+rw $INSTALL_DIR/openwhisk-deploy-kube/mycluster.yaml
    printf "%s: %s\n" "$(date +"%T.%N")" "Added actual primary node IP to $INSTALL_DIR/openwhisk-deploy-kube/mycluster.yaml"
}


deploy_openwhisk() {
    # Takes cluster IP as argument to set up wskprops files.

    # Deploy openwhisk via helm
    printf "%s: %s\n" "$(date +"%T.%N")" "About to deploy OpenWhisk via Helm... "
    cd $INSTALL_DIR/openwhisk-deploy-kube
    helm install owdev ./helm/openwhisk -n openwhisk -f mycluster.yaml > $INSTALL_DIR/ow_install.log 2>&1 
    if [ $? -eq 0 ]; then
        printf "%s: %s\n" "$(date +"%T.%N")" "Ran helm command to deploy OpenWhisk"
    else
        echo ""
        echo "***Error: Helm install error. Please check $INSTALL_DIR/ow_install.log."
        exit 1
    fi
    cd $INSTALL_DIR

    # Monitor pods until openwhisk is fully deployed
    kubectl get pods -n openwhisk
    printf "%s: %s\n" "$(date +"%T.%N")" "Waiting for OpenWhisk to complete deploying (this can take several minutes): "
    DEPLOY_COMPLETE=$(kubectl get pods -n openwhisk | grep owdev-install-packages | grep Completed | wc -l)
    while [ "$DEPLOY_COMPLETE" -ne 1 ]
    do
        sleep 2
        DEPLOY_COMPLETE=$(kubectl get pods -n openwhisk | grep owdev-install-packages | grep Completed | wc -l)
    done
    printf "%s: %s\n" "$(date +"%T.%N")" "OpenWhisk deployed!"
    
    # Set up wsk properties for all users
    for FILE in /users/*; do
        CURRENT_USER=${FILE##*/}
        echo -e "
	APIHOST=$1:31001
	AUTH=23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP
	" | sudo tee /users/$CURRENT_USER/.wskprops
	sudo chown $CURRENT_USER:$PROFILE_GROUP /users/$CURRENT_USER/.wskprops
    done
}

# Start by recording the arguments
printf "%s: args=(" "$(date +"%T.%N")"
for var in "$@"
do
    printf "'%s' " "$var"
done
printf ")\n"

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

# Kubernetes does not support swap, so we must disable it
disable_swap

# Use mountpoint (if it exists) to set up additional docker image storage
#if test -d "/mydata"; then
#    configure_docker_storage
#fi

# All all users to the docker group

# Fix permissions of install dir, add group for all users to set permission of shared files correctly
sudo groupadd $PROFILE_GROUP
for FILE in /users/*; do
    CURRENT_USER=${FILE##*/}
    sudo gpasswd -a $CURRENT_USER $PROFILE_GROUP
    sudo gpasswd -a $CURRENT_USER docker
done
sudo chown -R $USER:$PROFILE_GROUP $INSTALL_DIR
sudo chmod -R g+rw $INSTALL_DIR

# Use second argument (node IP) to replace filler in kubeadm configuration
sudo sed -i.bak "s/REPLACE_ME_WITH_IP/$2/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# At this point, a secondary node is fully configured until it is time for the node to join the cluster.
if [ $1 == $SECONDARY_ARG ] ; then

    # Exit early if we don't need to start Kubernetes
    if [ "$3" == "False" ]; then
        printf "%s: %s\n" "$(date +"%T.%N")" "Start Kubernetes is $3, done!"
        exit 0
    fi

    setup_secondary $2
    exit 0
fi

# Check the min number of arguments
if [ $# -ne $NUM_PRIMARY_ARGS ]; then
    echo "***Error: Expected at least $NUM_PRIMARY_ARGS arguments."
    echo "$USAGE"
    exit -1
fi

# Exit early if we don't need to start Kubernetes
if [ "$4" = "False" ]; then
    printf "%s: %s\n" "$(date +"%T.%N")" "Start Kubernetes is $4, done!"
    exit 0
fi

# Finish setting up the primary node
# Argument is node_ip
setup_primary $2

# Apply calico networking
apply_calico

# Coordinate master to add nodes to the kubernetes cluster
# Argument is number of nodes
add_cluster_nodes $3

# Exit early if we don't need to deploy OpenWhisk
if [ "$5" = "False" ]; then
    printf "%s: %s\n" "$(date +"%T.%N")" "Deploy Openwhisk is $4, done!"
    exit 0
fi

# Prepare cluster to deploy OpenWhisk: takes IP, num nodes, invoker num, and invoker engine
prepare_for_openwhisk $2 $3 $6 $7

# Deploy OpenWhisk via Helm
# Takes cluster IP
deploy_openwhisk $1

printf "%s: %s\n" "$(date +"%T.%N")" "Profile setup completed!"
