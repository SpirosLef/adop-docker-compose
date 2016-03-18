# AWS Docker cluster using Swarm

A CloudFormation template to build a CentOS-based Docker cluster on AWS
using Swarm.

## Parameters

The CloudFormation template takes the following parameters:

| Parameter | Description |
|-----------|-------------|
| InstanceType | EC2 HVM instance type (t2.micro, m3.medium, etc.) for the
Swarm master and node hosts. |
| ClusterSize | Number of nodes in the Swarm cluster (3-12). |
| ProxyClusterSize | Number of outer proxy nodes (1-12). |
| DiscoveryURL | A unique etcd cluster discovery URL. Grab a new token from https://discovery.etcd.io/new?size=4 |
| AdvertisedIPAddress | Use 'private' if your etcd cluster is within one region or 'public' if it spans regions or cloud providers. |
| AllowSSHFrom | The net block (CIDR) from which you can use SSH and docker to communicate with the Swarm master. |
| KeyName | The name of an EC2 Key Pair to allow SSH access to the Swarm master. |
| VpcAvailabilityZones | Comma-delimited list of three VPC availability zones in which to create subnets. |

The template builds a new VPC with 3 subnets (in 3 availability zones) for proxy, 3 subnets (in 3 availability zones) for public ELB 
and  3 subnets (in 3 availability zones) for a single Swarm master, a cluster of between 3 and 12 nodes and
one dedicated instance for adop reverse proxy, using the standard AWS CentOS AMI.

The swarm hosts form part of an initial etcd cluster for node
discovery during bootstrapping.
Therefore the size option on the discovery.etcd.io URL must be one more than
the size of the CentOS cluster.

Swarm hosts are evenly distributed across the 3 availability zones and are created
within an auto-scaling group which can be manually adjusted to alter
the Swarm cluster size post-launch.

A 'docker-swarm' container is run on each swarm host (the Swarm master and the nodes).
Hosts listen on port 4243, leaving the standard docker port (2375)
free for use by the 'docker-swarm' container on the master.

Separate 'master' and 'node' security groups control access between the nodes.
The template builds the Swarm master first, then the auto-scaling group
for the nodes
(each of which needs to register with the master via its 'docker-swarm'
container).

Note that each host also runs the Fleet service, which can be used as an
alternative cluster manager.

## Outputs

| Output | Description |
|--------|-------------|
| MasterDockerPs | Command to run a 'docker ps' on the Swarm master |
| ADOPReverseProxyPrivateIP | ADOP reverse proxy private IP to access stack |
| ELBPublicDNSName | ELB DNS to access the ADOP stack |

## Testing

Try

    docker -H tcp://_OuterProxyPublicIP_:2375 info

to see if the cluster is working.

For debugging, you should be able to ssh to the master, using the username 'centos' and your private key.
You can ssh on from there to each of the nodes. Other than that, it shouldn't really be necessary to
log in to any of the hosts.

## Future work

* Persistent storge - no, there isn't any currently!