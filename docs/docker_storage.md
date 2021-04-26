# Docker Storage & Cloudlab

Oftentimes, due to limited disk spcace, there can be an issue with OpenWhisk running out of room to store docker images. 
This can lead to some very odd behavior as docker images may be purged to create room.

## Setup Using ```small-lan``` profile

First allocate extra space when creating the setup using cloudlab (using the advance option - let’s say you name this partition ```/mydata```). 
Now install docker normally and simply modify the data-root field in the docker daemon. (look below the exact commands)

```
sudo apt install -y docker-ce=18.06.2~ce~3-0~ubuntu
echo -e '{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "data-root": "/mydata/docker"
}' | sudo tee /etc/docker/daemon.json
```

Note that you only need to update the ```data-root``` to direct it to your installation. In the case above, a docker directory was created in the new partition.
