""" Ubuntu 20.04 Optional Kubernetes Cluster w/ OpenWhisk optionally deployed with a parameterized
number of nodes.

Instructions:
Note: It can take upwards of 10 min. for the cluster to fully initialize. Thank you for your patience!
For full documentation, see the GitHub repo: https://github.com/CU-BISON-LAB/cloudlab-openwhisk
Output from the startup script is found at /home/openwhisk-kubernetes/start.log on all nodes
"""

import time

# Import the Portal object.
import geni.portal as portal
# Import the ProtoGENI library.
import geni.rspec.pg as rspec

BASE_IP = "10.10.1"
BANDWIDTH = 10000000
IMAGE = 'urn:publicid:IDN+utah.cloudlab.us+image+cu-bison-lab-PG0:openwhiskv2'

# Set up parameters
pc = portal.Context()
pc.defineParameter("nodeCount", 
                   "Number of nodes in the experiment. It is recommended that at least 3 be used.",
                   portal.ParameterType.INTEGER, 
                   3)
pc.defineParameter("nodeType", 
                   "Node Hardware Type",
                   portal.ParameterType.NODETYPE, 
                   "m510",
                   longDescription="A specific hardware type to use for all nodes. This profile has primarily been tested with m510 and xl170 nodes.")
pc.defineParameter("startKubernetes",
                   "Create Kubernetes cluster",
                   portal.ParameterType.BOOLEAN,
                   True,
                   longDescription="Create a Kubernetes cluster using default image setup (calico networking, etc.)")
pc.defineParameter("deployOpenWhisk",
                   "Deploy OpenWhisk",
                   portal.ParameterType.BOOLEAN,
                   True,
                   longDescription="Use helm to deploy OpenWhisk.")
# Below two options copy/pasted directly from small-lan experiment on CloudLab
# Optional ephemeral blockstore
pc.defineParameter("tempFileSystemSize", 
                   "Temporary Filesystem Size",
                   portal.ParameterType.INTEGER, 
                   0,
                   advanced=True,
                   longDescription="The size in GB of a temporary file system to mount on each of your " +
                   "nodes. Temporary means that they are deleted when your experiment is terminated. " +
                   "The images provided by the system have small root partitions, so use this option " +
                   "if you expect you will need more space to build your software packages or store " +
                   "temporary files. 0 GB indicates maximum size.")
params = pc.bindParameters()

# Verify parameters
if not params.startKubernetes and params.deployOpenWhisk:
    perr = portal.ParameterWarning("A Kubernetes cluster must be created in order to deploy OpenWhisk",['startKubernetes'])
    pc.reportError(perr)

pc.verifyParameters()
request = pc.makeRequestRSpec()

def create_node(name, nodes, lan):
  # Create node
  node = request.RawPC(name)
  node.disk_image = IMAGE
  node.hardware_type = params.nodeType
  
  # Add interface
  iface = node.addInterface("if1")
  iface.addAddress(rspec.IPv4Address("{}.{}".format(BASE_IP, 1 + len(nodes)), "255.255.255.0"))
  lan.addInterface(iface)
  
  # Add extra storage space
  bs = node.Blockstore(name + "-bs", "/mydata")
  bs.size = str(params.tempFileSystemSize) + "GB"
  bs.placement = "any"
  
  # Add to node list
  nodes.append(node)

nodes = []
lan = request.LAN()
lan.bandwidth = BANDWIDTH

# Create nodes
# The start script relies on the idea that the primary node is 10.10.1.1, and subsequent nodes follow the
# pattern 10.10.1.2, 10.10.1.3, ...
for i in range(params.nodeCount):
    name = "ow"+str(i+1)
    create_node(name, nodes, lan)

# Iterate over secondary nodes first
for i, node in enumerate(nodes[1:]):
    node.addService(rspec.Execute(shell="bash", command="/local/repository/start.sh secondary {}.{} {} > /home/cloudlab-openwhisk/start.log 2>&1 &".format(
      BASE_IP, i + 2, params.startKubernetes)))

# Start primary node
nodes[0].addService(rspec.Execute(shell="bash", command="/local/repository/start.sh primary {}.1 {} {} {} > /home/cloudlab-openwhisk/start.log 2>&1".format(
  BASE_IP, params.nodeCount, params.startKubernetes, params.deployOpenWhisk)))


pc.printRequestRSpec()
