provider "aws" {
  region     = "us-east-1"
}

resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "production"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id
}

resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Prod"
  }
}

resource "aws_subnet" "subnet-1" {
  vpc_id                  = aws_vpc.prod-vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "prod-subnet-1"
  }
}

resource "aws_subnet" "subnet-2" {
  vpc_id                  = aws_vpc.prod-vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "prod-subnet-2"
  }
}

resource "aws_subnet" "subnet-3" {
  vpc_id                  = aws_vpc.prod-vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-1c"
  map_public_ip_on_launch = true
  tags = {
    Name = "prod-subnet-3"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

resource "aws_network_interface" "msk-client-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

}

resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.msk-client-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw]
}

output "server_public_ip" {
  value = aws_eip.one.public_ip
}

resource "aws_instance" "msk-client" {
  ami               = "ami-0c02fb55956c7d316"
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a"
  key_name          = "MSKKeyPair"
  depends_on = [
    aws_msk_cluster.MSKCluster
  ]

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.msk-client-nic.id
  }

  user_data = <<-EOF
                #!/bin/bash
                sudo yum install java-1.8.0 -y
                wget https://archive.apache.org/dist/kafka/2.6.2/kafka_2.12-2.6.2.tgz
                tar -xzf kafka_2.12-2.6.2.tgz
                echo \${aws_msk_cluster.MSKCluster.bootstrap_brokers_tls} > bootstrap_brokers_tls.log
                echo security.protocol=PLAINTEXT > kafka_2.12-2.6.2/bin/client.properties
                kafka_2.12-2.6.2/bin/kafka-topics.sh --create --zookeeper \${aws_msk_cluster.MSKCluster.zookeeper_connect_string} --replication-factor 3 --partitions 1 --topic MSKTutorialTopic
                EOF
  tags = {
    Name = "MSKClient"
  }
}

data "aws_availability_zones" "azs" {
  state = "available"
}

resource "aws_security_group" "sg" {
  vpc_id = aws_vpc.prod-vpc.id

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.allow_web.id]
  }
}

resource "aws_kms_key" "kms" {
  description = "MSKCluster"
}

resource "aws_cloudwatch_log_group" "test" {
  name = "msk_broker_logs"
}

resource "aws_s3_bucket" "bucket" {
  bucket        = "msk-broker-logs-bucket-1"
  force_destroy = true
}

resource "aws_iam_role" "firehose_role" {
  name = "firehose_test_role"

  assume_role_policy = <<EOF
{
"Version": "2012-10-17",
"Statement": [
  {
    "Action": "sts:AssumeRole",
    "Principal": {
      "Service": "firehose.amazonaws.com"
    },
    "Effect": "Allow",
    "Sid": ""
  }
  ]
}
EOF
}

resource "aws_kinesis_firehose_delivery_stream" "test_stream" {
  name        = "terraform-kinesis-firehose-msk-broker-logs-stream"
  destination = "s3"

  s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.bucket.arn
  }

  tags = {
    LogDeliveryEnabled = "placeholder"
  }

  lifecycle {
    ignore_changes = [
      tags["LogDeliveryEnabled"],
    ]
  }
}

resource "aws_msk_cluster" "MSKCluster" {
  cluster_name           = "MSKCluster"
  kafka_version          = "2.6.2"
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = "kafka.t3.small"
    ebs_volume_size = 100
    client_subnets = [
      aws_subnet.subnet-1.id,
      aws_subnet.subnet-2.id,
      aws_subnet.subnet-3.id,
    ]
    security_groups = [aws_security_group.sg.id]
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.kms.arn
  }

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.test.name
      }
      firehose {
        enabled         = true
        delivery_stream = aws_kinesis_firehose_delivery_stream.test_stream.name
      }
      s3 {
        enabled = true
        bucket  = aws_s3_bucket.bucket.id
        prefix  = "logs/msk-"
      }
    }
  }

  tags = {
    foo = "bar"
  }
}

output "zookeeper_connect_string" {
  value = aws_msk_cluster.MSKCluster.zookeeper_connect_string
}

output "bootstrap_brokers_tls" {
  description = "TLS connection host:port pairs"
  value       = aws_msk_cluster.MSKCluster.bootstrap_brokers_tls
}