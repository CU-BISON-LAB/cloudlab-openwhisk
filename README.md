# CloudLab profile for deploying OpenWhisk via Kubernetes

General information for what on CloudLab profiles created via GitHub repo can be found in the example repo [here](https://github.com/emulab/my-profile) or in the CloudLab [manual](https://docs.cloudlab.us/cloudlab-manual.html)

Specifically, the goal of this repo is to create a CloudLab profile that allows for one-click creation of a Kubernetes OpenWhisk deployment.

## User Information

Create a CloudLab experiment using the OpenWhisk profile. It's recommended to use at least 3 nodes for the cluster. It has been testsed on m510, xl170, and rs630 nodes (e.g., various Intel architectures, not ARM, so do not choose an ARM node). 

On each node, a copy of this repo is available at:
```
    /local/repository
```
Installation specific material (which is baked into the CloudLab disk image) is found at:
```
    /home/cloudlab-openwhisk
```
Docker images are store in additional ephemeral cloudlab storage, mounted on each node at:
```
    /mydata
```

To see information on OpenWhisk pods, make sure to specify the namespace as openwhisk. To remove OpenWhisk,
run the following commands:
```
    $ cd /home/cloudlab-openwhisk/openwhisk-deploy-kube
    $ helm uninstall owdev -n openwhisk
    $ kubectl delete namespace openwhisk
```

To start OpenWhisk again, run:
```
    $ kubectl create namespace openwhisk
    $ cd /home/cloudlab-openwhisk/openwhisk-deploy-kube
    $ helm install owdev ./helm/openwhisk -n openwhisk -f mycluster.yaml
```

The configuration of OpenWhisk deployed by the experiment is found at: ```/home/cloudlab-openwhisk/openwhisk-deploy-kube/mycluster.yaml```, and is 
identical to the one found [here](mycluster.yaml), except populated with the IP of the primary node. The
default OpenWhisk created by this profile is not optimized in any way. 

To upgrade OpenWhisk, such as after modifying the ```mycluster.yaml``` file, run the following helm command:
```
    $ helm upgrade owdev ./helm/openwhisk -n openwhisk -f mycluster.yaml
```

If anything went wrong with the profile, check the log found at on all nodes:
```
    $ /home/cloudlab-openwhisk/start.log
```

## Versioning
Version 1 of this profile is found in the ```v1``` branch.

Version 2 of this profile is found in the ```v2``` branch (and main).
* Includes bug fixed from version 1 regarding extra storage in /mydata
* Fixes permissions in /home/ directories
* Removes need to run start script after first login to populate environment variables

## Image Creation

The [```image_setup.sh```](image_setup.sh) script is how the image was created from the base CloudLab Ubuntu 20.04 image.
