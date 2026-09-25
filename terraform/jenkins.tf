# ---------------------------------------------------------
# Jenkins Deployment IAM Role
# ---------------------------------------------------------

data "aws_iam_policy_document" "jenkins_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "jenkins" {
  name               = "${var.project_name}-${var.environment}-jenkins-role"
  assume_role_policy = data.aws_iam_policy_document.jenkins_assume_role.json

  tags = {
    Name = "${var.project_name}-${var.environment}-jenkins-role"
  }
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.project_name}-${var.environment}-jenkins-profile"
  role = aws_iam_role.jenkins.name
}


# ---------------------------------------------------------
# Jenkins AWS Deployment Permissions
# ---------------------------------------------------------

data "aws_iam_policy_document" "jenkins_deployment" {

  # Jenkins needs cluster metadata to generate/use kubeconfig.
  statement {
    sid    = "DescribeEKSCluster"
    effect = "Allow"

    actions = [
      "eks:DescribeCluster"
    ]

    resources = [
      aws_eks_cluster.main.arn
    ]
  }

  # Required for ECR authentication.
  statement {
    sid    = "ECRAuthentication"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = ["*"]
  }

  # Jenkins may push application images only to our application repository.
  statement {
    sid    = "PushApplicationImages"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]

    resources = [
      aws_ecr_repository.app.arn
    ]
  }
}

resource "aws_iam_policy" "jenkins_deployment" {
  name   = "${var.project_name}-${var.environment}-jenkins-deployment"
  policy = data.aws_iam_policy_document.jenkins_deployment.json
}

resource "aws_iam_role_policy_attachment" "jenkins_deployment" {
  role       = aws_iam_role.jenkins.name
  policy_arn = aws_iam_policy.jenkins_deployment.arn
}


# ---------------------------------------------------------
# EKS Access Entry
# ---------------------------------------------------------

resource "aws_eks_access_entry" "jenkins" {
  cluster_name      = aws_eks_cluster.main.name
  principal_arn     = aws_iam_role.jenkins.arn
  type              = "STANDARD"
  kubernetes_groups = ["jenkins-deployers"]

  tags = {
    Name = "${var.project_name}-${var.environment}-jenkins-access"
  }

  depends_on = [
    aws_eks_cluster.main
  ]
}
# ---------------------------------------------------------
# Jenkins EC2 - Latest Amazon Linux 2023 AMI
# ---------------------------------------------------------

data "aws_ami" "jenkins" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


# ---------------------------------------------------------
# Jenkins Security Group
# ---------------------------------------------------------

resource "aws_security_group" "jenkins" {
  name        = "${var.project_name}-${var.environment}-jenkins-sg"
  description = "Restricted access to Jenkins controller"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Jenkins UI from administrator public IP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.jenkins_admin_cidr]
  }

  egress {
    description = "Outbound access for package installation and AWS APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-jenkins-sg"
  }
}


# ---------------------------------------------------------
# Jenkins SSM Permissions
# ---------------------------------------------------------

resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# ---------------------------------------------------------
# Jenkins Controller
# ---------------------------------------------------------

resource "aws_instance" "jenkins" {
  ami                         = data.aws_ami.jenkins.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  associate_public_ip_address = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 12
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-jenkins"
  }

  depends_on = [
    aws_iam_role_policy_attachment.jenkins_deployment,
    aws_iam_role_policy_attachment.jenkins_ssm
  ]
}
