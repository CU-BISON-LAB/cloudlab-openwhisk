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
                   "Number of nodes in the experiment. It is recommended that at least 3 be used.",
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
if params.nodeCount > 50:
    perr = portal.ParameterWarning("The calico CNI installed is meant to handle only 50 nodes, max :( Consider creating a new profile for larger clusters.",['nodeCount'])
    pc.reportWarning(perr)
    pass
pc.verifyParameters()

link_members = []

# Create nodes
for i in range(params.nodeCount):
    node = request.RawPC("node"+str(i+1))
    node.disk_image = 'urn:publicid:IDN+utah.cloudlab.us+image+cu-bison-lab-PG0:openwhisk'
    node.hardware_type = params.nodeType
    link_members.append(node)

    # Install and execute a script that is contained in the repository.
    # node.addService(rspec.Execute(shell="sh", command="/local/repository/silly.sh"))
    
# Create a link between nodes
link1 = request.Link(members = link_members)

portal.context.printRequestRSpec()
