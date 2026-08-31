resource "aws_vpc" "main_vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = var.private_subnet_cidr

  tags = {
    Name = "private-subnet"
  }
}

resource "aws_internet_gateway" "main_gw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "main-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_gw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "nat-elastic-ip"
  }
}

resource "aws_nat_gateway" "main_nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "main-nat-gateway"
  }

  depends_on = [aws_internet_gateway.main_gw]
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.main_nat_gw.id
  }

  tags = {
    Name = "private-route-table"
  }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_security_group" "public_sg" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port = 22
    to_port   = 22

    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0

    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "private_sg" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port = 22
    to_port   = 22

    protocol        = "tcp"
    security_groups = [aws_security_group.public_sg.id]
  }

  egress {
    from_port = 0
    to_port   = 0

    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-*"]
  }
}

resource "aws_key_pair" "def_key" {
  key_name = "def-key"

  public_key = file("~/.ssh/def-key.pub")
}

resource "aws_instance" "public_instance" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.def_key.key_name
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = file("${path.module}/scripts/userdata.sh")

  tags = {
    Name = "public-instance"
  }
}

data "aws_region" "current" {}

resource "aws_vpc_endpoint" "s3_vpc_endpoint" {
  vpc_id       = aws_vpc.main_vpc.id
  service_name = "com.amazonaws.${data.aws_region.current.region}.s3"

  vpc_endpoint_type = "Gateway"

  tags = {
    Name = "s3-vpc-endpoint"
  }
}

resource "aws_vpc_endpoint_route_table_association" "s3_vpc_endpoint_public_rt_assoc" {
  vpc_endpoint_id = aws_vpc_endpoint.s3_vpc_endpoint.id
  route_table_id  = aws_route_table.public_rt.id
}

resource "aws_vpc_endpoint_route_table_association" "s3_vpc_endpoint_private_rt_assoc" {
  vpc_endpoint_id = aws_vpc_endpoint.s3_vpc_endpoint.id
  route_table_id  = aws_route_table.private_rt.id
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_s3_role" {
  name               = "ec2_s3_access_role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "ec2_s3_permissions" {
  statement {
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListAllMyBuckets"
    ]

    resources = [
      "arn:aws:s3:::*",
      "arn:aws:s3:::*/*"
    ]
  }
}

resource "aws_iam_role_policy" "attach_iam_role_permissions" {
  name   = "read_write_role_policy_attachment"
  role   = aws_iam_role.ec2_s3_role.id
  policy = data.aws_iam_policy_document.ec2_s3_permissions.json
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_s3_instance_profile"
  role = aws_iam_role.ec2_s3_role.name
}

resource "aws_s3_bucket" "app_bucket" {
  bucket_prefix = "app-bucket-"
  force_destroy = true

  tags = {
    Name = "app-bucket"
  }
}

resource "aws_s3_bucket" "replicated_app_bucket" {
  bucket_prefix = "replicated-app-bucket-s"
  force_destroy = true

  tags = {
    Name = "replicated-app-bucket"
  }
}

resource "aws_s3_bucket_versioning" "s3_app_versioning" {
  bucket = aws_s3_bucket.app_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "s3_replicated_versioning" {
  bucket = aws_s3_bucket.replicated_app_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_website_configuration" "s3_website_config" {
  bucket = aws_s3_bucket.app_bucket.id

  index_document {
    suffix = "index.html"
  }
}

data "aws_iam_policy_document" "app_bucket_policy" {
  statement {
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.app_bucket.arn,
      "${aws_s3_bucket.app_bucket.arn}/*"
    ]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.ec2_s3_role.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "app_bucket_apply_policy" {
  bucket = aws_s3_bucket.app_bucket.id
  policy = data.aws_iam_policy_document.app_bucket_policy.json
}

data "aws_iam_policy_document" "s3_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication_role" {
  name               = "s3_replication_role"
  assume_role_policy = data.aws_iam_policy_document.s3_assume_role.json
}

data "aws_iam_policy_document" "replication_policy" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket"
    ]

    resources = [aws_s3_bucket.app_bucket.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging"
    ]

    resources = ["${aws_s3_bucket.app_bucket.arn}/*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags"
    ]

    resources = ["${aws_s3_bucket.replicated_app_bucket.arn}/*"]
  }
}

resource "aws_iam_role_policy" "s3_app_replication_policy_attachment" {
  name   = "s3_replication_policy"
  role   = aws_iam_role.replication_role.name
  policy = data.aws_iam_policy_document.replication_policy.json
}

resource "aws_s3_bucket_replication_configuration" "s3_app_replication_config" {
  depends_on = [
    aws_s3_bucket_versioning.s3_app_versioning,
    aws_s3_bucket_versioning.s3_replicated_versioning
  ]

  role   = aws_iam_role.replication_role.arn
  bucket = aws_s3_bucket.app_bucket.id


  rule {
    id     = "backup_entire_bucket"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.replicated_app_bucket.arn
      storage_class = "STANDARD"
    }
  }
}