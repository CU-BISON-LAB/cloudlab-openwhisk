""" Ubuntu 20.04 Optional Kubernetes Cluster w/ OpenWhisk optionally deployed with a parameterized
number of nodes and OpenWhisk invokers.

Instructions:
Note: It can take upwards of 10 min. for the cluster to fully initialize. Thank you for your patience!
For full documentation, see the GitHub repo: https://github.com/CU-BISON-LAB/cloudlab-openwhisk
To set up user permissions regarding Kubernetes, after you log in on the primary node (node1),
run the following script: $ /local/repository/user_setup.sh. To see output from the startup script 
on both primary and secondary nodes, run: $ cat /home/openwhisk-kubernetes/start.log
"""

import time

# Import the Portal object.
import geni.portal as portal
# Import the ProtoGENI library.
import geni.rspec.pg as rspec

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
pc.defineParameter("numInvokers",
                   "Number of Invokers",
                   portal.ParameterType.INTEGER,
                   1,
                   longDescription="Number of OpenWhisk invokers set in the mycluster.yaml file, and number of nodes labelled as Openwhisk invokers. " \
                           "All nodes which are not invokers will be labelled as OpenWhisk core nodes.")
pc.defineParameter("extraStorage", 
                   "Temporary filesystem mount point for docker image storage on all nodes",
                   portal.ParameterType.BOOLEAN,
                   False,
                   longDescription="Mount the temporary file system at the /mydata mount point; Configure docker to store images here. This is useful " \
                   for OpenWhisk development.")
params = pc.bindParameters()

# Verify parameters
if params.nodeCount > 50:
    perr = portal.ParameterWarning("The calico CNI installed is meant to handle only 50 nodes, max :( Consider creating a new profile for larger clusters.",['nodeCount'])
    pc.reportError(perr)
if not params.startKubernetes and params.deployOpenWhisk:
    perr = portal.ParameterWarning("The Kubernetes Cluster must be created in order to deploy OpenWhisk",['startKubernetes'])
    pc.reportError(perr)
if not params.deployOpenWhisk and params.numInvokers != 1:
    perr = portal.ParameterWarning("Number of invokers set to default value, but OpenWhisk will not be deployed. Number of invokers has no meaning if OpenWhisk is not deployed.", 
            ["numInvokers"])
    pc.reportError(perr)
if params.numInvokers > params.nodeCount:
    perr = portal.ParameterWarning("Number of invokers must be less than or equal to the total number of nodes.", ["numInvokers"])
    pc.reportError(perr)

pc.verifyParameters()
request = pc.makeRequestRSpec()

nodes = []

# Create nodes
# The start script relies on the idea that the primary node is 10.10.1.1, and subsequent nodes follow the
# pattern 10.10.1.2, 10.10.1.3, ...
for i in range(params.nodeCount):
    name = "node"+str(i+1)
    node = request.RawPC(name)
    node.disk_image = 'urn:publicid:IDN+utah.cloudlab.us+image+cu-bison-lab-PG0:openwhisk'
    node.hardware_type = params.nodeType
    if params.extraStorage:
        bs = node.Blockstore(name + "-bs", "/mydata")
        bs.size = "0GB"
        bs.placement = "any"
    nodes.append(node)

# Create a link between nodes
link1 = request.Link(members = nodes)

for i, node in enumerate(nodes[1:]):
    node.addService(rspec.Execute(shell="bash", command="/local/repository/start.sh secondary 10.10.1.{} {} > /home/openwhisk-kubernetes/start.log &".format(
      i + 2, params.startKubernetes)))

nodes[0].addService(rspec.Execute(shell="bash", command="/local/repository/start.sh primary 10.10.1.1 {} {} {} {} > /home/openwhisk-kubernetes/start.log".format(
  params.nodeCount, params.startKubernetes, params.deployOpenWhisk, params.numInvokers)))


pc.printRequestRSpec()
