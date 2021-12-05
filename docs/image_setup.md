# Image Setup

## Version Information
Used default Ubuntu 20 CloudLab image (UBUNTU20-64-STD).
Updated system software (using apt) on 05 Feb 2021.

Docker is a version: 19.03.8, build afacb8b7f0
Helm is at version: Version:"v3.5.2", GitCommit:"167aac70832d3a384f65f9745335e9fb40169dc2", GitTreeState:"dirty", GoVersion:"go1.15.7"
OpenWhisk: commit 2b6abd3df8796b9553569fdb5366e8014b52488b
Kubernetes: Major:"1", Minor:"20", GitVersion:"v1.20.2", GitCommit:"faecb196815e248d3ecfb03c680a4507229c2a56"

## Steps to Setup

Create a new single node small-lan experiment using the UBUNTU20-64-STD image.

Updated software (as below), and then restarted the node.
```
$ sudo apt update
$ sudo apt upgrade
$ sudo apt autoremove
```

Run the ```setup_image.sh``` script.

We want to be sure that we use the CloudLab experimental interface and not the control interface within our Kubernetes cluster. To do so, edit ```/etc/systemd/system/kubelet.service.d/10-kubeadm.conf``` to be as below:

```
# Note: This dropin only works with kubeadm and kubelet v1.11+
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml --node-ip=REPLACE_ME_WITH_IP"

Environment="cgroup-driver=systemd/cgroup-driver=cgroupfs"

# This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
# the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
```

We set the --node-ip for kubelet to be REPLACE_ME_WITH_IP, which will be replaced with the node IP in the corresponding startup script. I had some issues with the cgroup drivers, so I had to modify that here too.
