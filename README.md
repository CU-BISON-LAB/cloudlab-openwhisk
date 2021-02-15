# CloudLab profile for deploying OpenWhisk via Kubernetes

General information for what on CloudLab profiles created via GitHub repo can be found in the example repo [here](https://github.com/emulab/my-profile) or in the CloudLab [manual](https://docs.cloudlab.us/cloudlab-manual.html)

Specifically, the goal of this repo is to create a CloudLab profile that allows for one-click creation of a Kubernetes OpenWhisk deployment.

## User Information

Create a CloudLab experiment using the OpenWhisk profile. It's recommended to use at least 3 nodes for the cluster. If deploying OpenWhisk, choose a number of invokers less than the number of total nodes. All nodes not labelled as invoker nodes will be labelled as OpenWhisk core nodes. It has been testsed on m510, xl170, and rs630 nodes (e.g., various Intel architectures, not ARM, so do not choose an ARM node). 

On each node, a copy of this repo is available at:
```
    /local/repository
```
Installation specific material (which is baked into the CloudLab disk image) is found at:
```
    /home/openwhisk-kubernetes
```

After logging in, follow the instructions in the profile, namely - from the primary node, which is node1, run the following script:
```
    $ /local/respository/user_setup.sh
```
This will set up files in your home directory and environment variables needed to use ```wsk``` and ```kubectl```.

To see information on OpenWhisk pods, make sure to specify the namespace as openwhisk. To remove OpenWhisk,
run the following commands:
```
    $ cd /home/openwhisk-kuberntes/openwhisk-deploy-kube
    $ helm uninstall owdev -n openwhisk
```
After the helm uninstall, there may be orphan action containers which should be removed via ```kubectl```.

The OpenWhisk that is deployed is specified as in the ```/home/openwhisk-kubernetes/openwhisk-deploy-kube/mycluster.yaml```, and is 
identical to the one found [here](mycluster.yaml), except populated with the number of invokers and the IP of the primary node. The
default OpenWhisk created by this profile is not optimized in any way. To restart OpenWhisk, perhaps after modifying the ```mycluster.yaml```
file, run the following helm command:
```
    $ cd /home/openwhisk-kubernetes/openwhisk-deploy-kube
    $ helm install owdev ./helm/openwhisk -n openwhisk -f mycluster.yaml
```

If anything went wrong with the profile, check the log found at on all nodes:
```
    $ /home/openwhisk-kubernetes/start.log
```

## Documentation

Information on how the disk image used is found [here](docs/image_setup.md).
