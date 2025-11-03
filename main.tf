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

resource "aws_internet_gateway" "this" {
  count  = local.create_networking ? 1 : 0
  vpc_id = aws_vpc.auto[0].id

  tags = merge(var.tags, {
    Name = "aura-privatelink-igw"
  })
}

resource "aws_subnet" "public" {
  count                   = local.create_networking ? 1 : 0
  vpc_id                  = aws_vpc.auto[0].id
  availability_zone       = data.aws_availability_zones.available.names[0]
  cidr_block              = cidrsubnet(aws_vpc.auto[0].cidr_block, 4, 3)
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "aura-privatelink-public-subnet"
  })
}

resource "aws_route_table" "public" {
  count  = local.create_networking ? 1 : 0
  vpc_id = aws_vpc.auto[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  tags = merge(var.tags, {
    Name = "aura-privatelink-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = local.create_networking ? 1 : 0
  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
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

resource "aws_vpc_security_group_ingress_rule" "ssh_managed_sg" {
  for_each          = var.create_security_group && length(var.test_vm_ssh_cidr_blocks) > 0 ? toset(var.test_vm_ssh_cidr_blocks) : []
  security_group_id = aws_security_group.this[0].id
  description       = "Allow SSH to test VM (managed SG)"
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

locals {
  ssh_existing_pairs = !var.create_security_group && var.security_group_ids != null && length(var.test_vm_ssh_cidr_blocks) > 0 ? {
    for pair in setproduct(var.security_group_ids, var.test_vm_ssh_cidr_blocks) :
    "${pair[0]}|${pair[1]}" => { sg_id = pair[0], cidr = pair[1] }
  } : {}
}

resource "aws_vpc_security_group_ingress_rule" "ssh_existing_sg" {
  for_each          = local.ssh_existing_pairs
  security_group_id = each.value.sg_id
  description       = "Allow SSH to test VM (existing SG)"
  cidr_ipv4         = each.value.cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_instance" "test" {
  count                       = var.create_test_vm ? 1 : 0
  ami                         = data.aws_ami.al2023[0].id
  instance_type               = var.test_vm_instance_type
  subnet_id                   = var.test_vm_subnet_id != null ? var.test_vm_subnet_id : (local.create_networking ? aws_subnet.public[0].id : local.effective_subnet_ids[0])
  vpc_security_group_ids      = local.endpoint_sg_ids
  associate_public_ip_address = var.test_vm_public_ip
  key_name                    = coalesce(var.test_vm_key_name, try(aws_key_pair.test_vm[0].key_name, null))

  tags = merge(var.tags, {
    Name = "aura-privatelink-test-vm"
  })

  depends_on = [aws_vpc_endpoint.aura]
}

# -----------------------------
# Optional Key Pair Generation
# -----------------------------

resource "tls_private_key" "test_vm" {
  count     = var.create_test_vm && var.test_vm_key_name == null ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "test_vm" {
  count      = var.create_test_vm && var.test_vm_key_name == null ? 1 : 0
  key_name   = var.test_vm_generated_key_name
  public_key = tls_private_key.test_vm[0].public_key_openssh
}

resource "local_file" "test_vm_private_key" {
  count           = var.create_test_vm && var.test_vm_key_name == null ? 1 : 0
  filename        = var.test_vm_private_key_output_path
  content         = tls_private_key.test_vm[0].private_key_pem
  file_permission = "0400"
}


