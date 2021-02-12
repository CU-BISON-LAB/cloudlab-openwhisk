"""
TODO: Not finished yet, use owk8s profile in the meantime
"""
import time

# Import the Portal object.
import geni.portal as portal
# Import the ProtoGENI library.
import geni.rspec.pg as rspec

request = portal.context.makeRequestRSpec()

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
                   True)
pc.defineParameter("deployOpenWhisk",
                   "Deploy OpenWhisk",
                   portal.ParameterType.BOOLEAN,
                   True)
pc.defineParameter("helmTests",
                   "Run helm tests (recommended if deploying OpenWhisk",
                   portal.ParameterType.BOOLEAN,
                   True)
pc.defineParameter("manualTests",
                   "Run manual OpenWhisk tests (recommended if deploying OpenWhisk",
                   portal.ParameterType.BOOLEAN,
                   True)
params = pc.bindParameters()

# Verify parameters
if params.nodeCount > 50:
    perr = portal.ParameterWarning("The calico CNI installed is meant to handle only 50 nodes, max :( Consider creating a new profile for larger clusters.",['nodeCount'])
    pc.reportWarning(perr)
    pass
if not params.startKubernetes and (params.deployOpenWhisk or params.helmTests or params.manualTests):
    perr = portal.ParameterWarning("The Kubernetes Cluster must be created in order to deploy OpenWhisk and run tests",['startKubernetes'])
    pc.reportWarning(perr)
    pass
if not params.deployOpenWhisk and (params.helmTests or params.manualTests):
    perr = portal.ParameterWarning("OpenWhisk must be deployed in order to run tests",['deployOpenWhisk'])
    pc.reportWarning(perr)
    pass
pc.verifyParameters()

nodes = []

# Create nodes
for i in range(params.nodeCount):
    node = request.RawPC("node"+str(i+1))
    node.disk_image = 'urn:publicid:IDN+utah.cloudlab.us+image+cu-bison-lab-PG0:openwhisk'
    node.hardware_type = params.nodeType
    nodes.append(node)
    
# Create a link between nodes
link1 = request.Link(members = nodes)

for i, node in enumerate(nodes[1:]):
    node.addService(rspec.Execute(shell="bash", command="/local/repository/start_k8s.sh secondary 10.10.1.{} > /home/openwhisk-kubernetes/start_k8s.log &".format(i + 2)))

nodes[0].addService(rspec.Execute(shell="bash", command="/local/repository/start_k8s.sh primary 10.10.1.1 {} {} {} {} {}> /home/openwhisk-kubernetes/start_k8s.log".format(
  params.nodeCount, params.startKuberentes, params.deployOpenwhisk, params.helmTests, params.manualTests)))
portal.context.printRequestRSpec()
