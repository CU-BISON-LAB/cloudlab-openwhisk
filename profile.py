"""
TODO: write directions.
"""

# Import the Portal object.
import geni.portal as portal
# Import the ProtoGENI library.
import geni.rspec.pg as rspec

request = portal.context.makeRequestRSpec()

# Set up parameters
pc = portal.Context()
pc.defineParameter("nodeCount", 
                   "Number of nodes in the experiment. It is recommended that at least 3 be used for the Kubernetes/OpenWhisk ",
                   portal.ParameterType.INTEGER, 
                   3
)
pc.defineParameter("nodeType", 
                   "Node Hardware Type",
                   portal.ParameterType.NODETYPE, 
                   "m510",
                   longDescription="A specific hardware type to use for all nodes. This profile has primarily been tested with m510 and xl170 nodes.")
params = pc.bindParameters()

# Verify parameters
if params.nodeCount > 10:
    perr = portal.ParameterWarning("Do you really need more than 8 compute nodes?  Think of your fellow users scrambling to get nodes :).",['nodeCount'])
    pc.reportWarning(perr)
    pass
pc.verifyParameters()

link_members = []

# Create nodes
for i in range(params.nodeCount):
    node = request.RawPC("node"+str(i+1))
    node.disk_image = 'urn:publicid:IDN+utah.cloudlab.us+image+cu-bison-lab-PG0:openwhisk:1'
    node.hardware_type = params.nodeType
    link_members.append(node)

    # Install and execute a script that is contained in the repository.
    node.addService(rspec.Execute(shell="sh", command="/local/repository/silly.sh"))
    
# Create a link between nodes
link1 = request.Link(members = link_members)

portal.context.printRequestRSpec()
