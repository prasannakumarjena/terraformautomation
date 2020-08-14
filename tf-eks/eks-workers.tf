data "aws_ami" "eks-worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.demo-cluster.version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon
}

# EKS currently documents this required userdata for EKS worker nodes to
# properly configure Kubernetes applications on the EC2 instance.
# We utilize a Terraform local here to simplify Base64 encoding this
# information into the AutoScaling Launch Configuration.
# More information: https://docs.aws.amazon.com/eks/latest/userguide/launch-workers.html
locals {
  demo-node-userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.demo-cluster.endpoint}' --b64-cluster-ca '${aws_eks_cluster.demo-cluster.certificate_authority[0].data}' '${var.cluster-name}'
USERDATA

}

resource "aws_launch_configuration" "demo" {
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.demo-node.name
  image_id                    = "ami-077b1b2235fbf9333"
  instance_type               = "t2.medium"
  key_name                    = "terraformkey"
  name_prefix                 = "terraform-eks-demo"
  security_groups             = [aws_security_group.demo-node-wrkgrp.id]
  user_data_base64            = base64encode(local.demo-node-userdata)
  
   root_block_device {
    volume_type           = "gp2"
    volume_size           = 30
    delete_on_termination = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "demo" {
  desired_capacity = 1
  launch_configuration = aws_launch_configuration.demo.id
  max_size = 5
  min_size = 1
  name = "terraform-eks-demo"

  vpc_zone_identifier = module.vpc.public_subnets

  tag {
    key = "Name"
    value = "terraform-eks-demo"
    propagate_at_launch = true
  }

  tag {
    key = "kubernetes.io/cluster/${var.cluster-name}"
    value = "owned"
    propagate_at_launch = true
  }

  tag {
    key = "k8s.io/cluster-autoscaler/enabled"
    value = "true"
    propagate_at_launch = true
  }

  tag {
    key = "k8s.io/cluster-autoscaler/${var.cluster-name}"
    value = "owned"
    propagate_at_launch = true
  }

}

