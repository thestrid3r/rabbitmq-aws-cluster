data "aws_vpc" "vpc" {
  id = "${var.vpc_id}"
}

data "aws_ami_ids" "ubuntu" {
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }
  filter {
        name   = "virtualization-type"
        values = ["hvm"]
    }
  owners = ["099720109477"] #Canonical

}

data "aws_iam_policy_document" "policy_doc" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "template_file" "cloud-init" {
  template = "${file("${path.module}/cloud-init.yaml")}"

  vars {
    sync_node_count = 3
    region            = "${var.region}"
    secret_cookie     = "${var.rabbitmq_secret_cookie}"
    admin_password    = "${var.admin_password}"
    rabbit_password   = "${var.rabbit_password}"
    message_timeout   = "${3 * 24 * 60 * 60 * 1000}"  # 3 days
  }
}

resource "aws_iam_role" "role" {
  name               = "rabbitmq"
  assume_role_policy = "${data.aws_iam_policy_document.policy_doc.json}"
}

resource "aws_iam_role_policy" "policy" {
  name   = "rabbitmq"
  role   = "${aws_iam_role.role.id}"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingInstances",
                "ec2:DescribeInstances"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_instance_profile" "profile" {
  name = "rabbitmq"
  role = "${aws_iam_role.role.name}"
}

resource "aws_security_group" "elb-nodes" {
  name        = "elb-nodes"
  vpc_id      = "${var.vpc_id}"
  description = "Security Group for the rabbitmq elb and nodes"

  ingress {
    protocol        = "tcp"
    from_port       = 5672
    to_port         = 5672
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol        = "tcp"
    from_port       = 5671
    to_port         = 5671
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol        = "tcp"
    from_port       = 25672
    to_port         = 25672
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol        = "tcp"
    from_port       = 4369
    to_port         = 4369
    cidr_blocks = ["0.0.0.0/0"]
  }
   ingress {
    protocol        = "tcp"
    from_port       = 5672
    to_port         = 5672
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol        = "tcp"
    from_port       = 15672
    to_port         = 15672
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol        = "tcp"
    from_port       = 22
    to_port         = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags {
    Name = "rabbitmqSG"
  }
}  

resource "aws_launch_configuration" "rabbitmq" {
  name                 = "rabbitmq"
  image_id             = "${data.aws_ami_ids.ubuntu.ids[0]}"
  instance_type        = "${var.instance_type}"
  key_name             = "${var.ssh_key_name}"
  security_groups      = ["${aws_security_group.elb-nodes.id}"]
  iam_instance_profile = "${aws_iam_instance_profile.profile.id}"
  user_data            = "${data.template_file.cloud-init.rendered}"
}

resource "aws_autoscaling_group" "rabbitmq" {
  name                      = "rabbitmq"
  max_size                  = "${var.rabbitmq_node_count}"
  min_size                  = "${var.rabbitmq_node_count}"
  desired_capacity          = "${var.rabbitmq_node_count}"
  health_check_grace_period = 300
  health_check_type         = "ELB"
  force_delete              = true
  launch_configuration      = "${aws_launch_configuration.rabbitmq.name}"
  load_balancers            = ["${aws_elb.elb.name}"]
  vpc_zone_identifier       = ["${var.subnet_ids}"]

  tag {
    key = "Name"
    value = "rabbitmq"
    propagate_at_launch = true
  }
}

resource "aws_elb" "elb" {
  name                 = "rabbit-elb"

  listener {
    instance_port      = 5672
    instance_protocol  = "tcp"
    lb_port            = 5672
    lb_protocol        = "tcp"
  }

  listener {
    instance_port      = 15672
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }

  health_check {
    interval            = 45
    unhealthy_threshold = 10
    healthy_threshold   = 2
    timeout             = 6
    target              = "TCP:5672"
  }

  subnets               = ["${var.subnet_ids}"]
  idle_timeout          = 3600
  internal              = false
  security_groups       = ["${aws_security_group.elb-nodes.id}"]

  tags {
    Name = "rabbitmq"
  }
}
