# AWS MSK Cluster Test

Following [this document](https://docs.aws.amazon.com/msk/latest/developerguide/getting-started.html), we would like to setup the MSK Cluster and a EC2 instance to test the basic functionalities of Kafka cluster in AWS.

## Setup

Terraform is used to spin up the necessarily network and instances. It is composed of the following:

1. A seperate VPC which contains everything.
2. A EC2 instance which can be connected by SSH. Kafka libary is installed in the instance when launched. 
3. A MSK Cluster is installed.
4. A inbound rule is added to security group of the MSK Cluster to allow traffic of the EC2 instance.
5. A topic MSKTutorialTopic is added to MSK Cluster.
