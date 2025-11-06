variable "aws_region" {
  description = "AWS region to deploy resources in (must match service name region)."
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "ID of the VPC to attach the PrivateLink endpoint to. If null, a VPC will be created."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs for the endpoint ENIs (recommend one per AZ, typically 3). If null, three subnets will be created across available AZs."
  type        = list(string)
  default     = null
}

variable "service_name" {
  description = "The PrivateLink service name provided by Neo4j Aura (e.g., com.amazonaws.vpce.us-east-1.vpce-svc-xxxxxxxxxxxxxxxxx)."
  type        = string
}

variable "enable_private_dns" {
  description = "Enable Private DNS for the endpoint (must be supported by the service)."
  type        = bool
  default     = false
}

variable "security_group_ids" {
  description = "Optional list of existing Security Group IDs to attach to the endpoint ENIs. If omitted and create_security_group is true, a new SG will be created."
  type        = list(string)
  default     = null
  validation {
    condition     = var.create_security_group || (var.security_group_ids != null && length(var.security_group_ids) > 0)
    error_message = "When create_security_group is false, you must provide at least one security group ID in security_group_ids."
  }
}

variable "create_security_group" {
  description = "Whether to create and manage a Security Group that allows ports 80, 443, 7687."
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach the endpoint ENIs via the managed Security Group."
  type        = list(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition     = length(var.allowed_cidr_blocks) > 0
    error_message = "allowed_cidr_blocks must have at least one entry."
  }
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}

variable "create_test_vm" {
  description = "Whether to create a small EC2 instance in the endpoint subnet to run connectivity tests."
  type        = bool
  default     = false
}

variable "test_vm_instance_type" {
  description = "Instance type for the test VM."
  type        = string
  default     = "t3.micro"
}

variable "test_vm_key_name" {
  description = "Optional EC2 Key Pair name to enable SSH access to the test VM."
  type        = string
  default     = null
}

variable "test_vm_generated_key_name" {
  description = "Name to use when generating an EC2 Key Pair if test_vm_key_name is not provided."
  type        = string
  default     = "aura-privatelink-test-key"
}

variable "test_vm_private_key_output_path" {
  description = "Local filesystem path to write the generated private key PEM (only when generating a key)."
  type        = string
  default     = "ssh/test-vm-key.pem"
}

variable "test_vm_public_ip" {
  description = "Whether to associate a public IP to the test VM."
  type        = bool
  default     = true
}

variable "test_vm_subnet_id" {
  description = "Optional subnet ID for the test VM. If null and networking is auto-created, a public subnet will be created and used; otherwise the first effective subnet is used."
  type        = string
  default     = null
}


