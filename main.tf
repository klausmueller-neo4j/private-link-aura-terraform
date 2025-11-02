locals {
  create_networking = var.vpc_id == null || var.subnet_ids == null || length(var.subnet_ids) == 0
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpc" "this" {
  count = local.create_networking ? 0 : 1
  id    = var.vpc_id
}

resource "aws_vpc" "auto" {
  count                = local.create_networking ? 1 : 0
  cidr_block           = "10.16.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "aura-privatelink-vpc"
  })
}

resource "aws_subnet" "auto" {
  count                   = local.create_networking ? min(3, length(data.aws_availability_zones.available.names)) : 0
  vpc_id                  = aws_vpc.auto[0].id
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = cidrsubnet(aws_vpc.auto[0].cidr_block, 4, count.index)
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "aura-privatelink-subnet-${count.index}"
  })
}

locals {
  allowed_cidrs = var.allowed_cidr_blocks != null ? var.allowed_cidr_blocks : (
    local.create_networking ? [aws_vpc.auto[0].cidr_block] : [data.aws_vpc.this[0].cidr_block]
  )
}

resource "aws_security_group" "this" {
  count       = var.create_security_group ? 1 : 0
  name        = "aura-privatelink-endpoint"
  description = "Security group for Neo4j Aura PrivateLink endpoint"
  vpc_id      = local.create_networking ? aws_vpc.auto[0].id : var.vpc_id

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "aura-privatelink-endpoint"
  })
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  count             = var.create_security_group ? 1 : 0
  security_group_id = aws_security_group.this[0].id
  description       = "Allow HTTP"
  cidr_ipv4         = length(local.allowed_cidrs) == 1 ? local.allowed_cidrs[0] : null
  referenced_security_group_id = null
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  # For multiple CIDRs, create one rule per CIDR
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "http_multi" {
  for_each          = var.create_security_group && length(local.allowed_cidrs) > 1 ? toset(local.allowed_cidrs) : []
  security_group_id = aws_security_group.this[0].id
  description       = "Allow HTTP"
  cidr_ipv4         = each.value
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  count             = var.create_security_group ? 1 : 0
  security_group_id = aws_security_group.this[0].id
  description       = "Allow HTTPS"
  cidr_ipv4         = length(local.allowed_cidrs) == 1 ? local.allowed_cidrs[0] : null
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "https_multi" {
  for_each          = var.create_security_group && length(local.allowed_cidrs) > 1 ? toset(local.allowed_cidrs) : []
  security_group_id = aws_security_group.this[0].id
  description       = "Allow HTTPS"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "bolt" {
  count             = var.create_security_group ? 1 : 0
  security_group_id = aws_security_group.this[0].id
  description       = "Allow Neo4j Bolt"
  cidr_ipv4         = length(local.allowed_cidrs) == 1 ? local.allowed_cidrs[0] : null
  from_port         = 7687
  to_port           = 7687
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "bolt_multi" {
  for_each          = var.create_security_group && length(local.allowed_cidrs) > 1 ? toset(local.allowed_cidrs) : []
  security_group_id = aws_security_group.this[0].id
  description       = "Allow Neo4j Bolt"
  cidr_ipv4         = each.value
  from_port         = 7687
  to_port           = 7687
  ip_protocol       = "tcp"
}

locals {
  endpoint_sg_ids      = var.create_security_group ? [aws_security_group.this[0].id] : var.security_group_ids
  effective_vpc_id     = local.create_networking ? aws_vpc.auto[0].id : var.vpc_id
  effective_subnet_ids = local.create_networking ? tolist(aws_subnet.auto[*].id) : var.subnet_ids
}

resource "aws_vpc_endpoint" "aura" {
  vpc_id              = local.effective_vpc_id
  service_name        = var.service_name
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = var.enable_private_dns
  subnet_ids          = local.effective_subnet_ids
  security_group_ids  = local.endpoint_sg_ids

  tags = merge(var.tags, {
    Name = "aura-privatelink-endpoint"
  })
}


# -----------------------------
# Optional Test EC2 VM
# -----------------------------

data "aws_ami" "al2023" {
  count       = var.create_test_vm ? 1 : 0
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "test_vm" {
  count       = var.create_test_vm ? 1 : 0
  name        = "aura-privatelink-test-vm"
  description = "Security group for PrivateLink test EC2"
  vpc_id      = local.effective_vpc_id

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "aura-privatelink-test-vm"
  })
}

resource "aws_vpc_security_group_ingress_rule" "test_vm_ssh" {
  for_each          = var.create_test_vm && length(var.test_vm_ssh_cidr_blocks) > 0 ? toset(var.test_vm_ssh_cidr_blocks) : []
  security_group_id = aws_security_group.test_vm[0].id
  description       = "Allow SSH to test VM"
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

 

resource "aws_instance" "test" {
  count                       = var.create_test_vm ? 1 : 0
  ami                         = data.aws_ami.al2023[0].id
  instance_type               = var.test_vm_instance_type
  subnet_id                   = local.effective_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.test_vm[0].id]
  associate_public_ip_address = false
  key_name                    = var.test_vm_key_name

  tags = merge(var.tags, {
    Name = "aura-privatelink-test-vm"
  })

  depends_on = [aws_vpc_endpoint.aura]
}


