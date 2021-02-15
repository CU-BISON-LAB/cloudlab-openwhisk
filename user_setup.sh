#!/bin/bash

# set up kubectl (so can run kubectl commands without sudo)
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# set up docker (so can run docker commands without sudo)
sudo usermod -aG docker $USER
newgrp docker 

# set up wsk
wsk property set --apihost 10.10.1.1:31001
wsk property set --auth 23bc46b1-71f6-4ed5-8c54-816aa4f8c502:123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP
