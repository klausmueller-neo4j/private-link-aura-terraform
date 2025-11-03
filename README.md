# Neo4j Aura PrivateLink on AWS with Terraform

This repository provisions an AWS VPC Interface Endpoint for a Neo4j Aura PrivateLink service, including optional creation of a security group that allows ports 80, 443, and 7687, and enabling Private DNS when supported.

## What this creates
- A VPC Interface Endpoint (`aws_vpc_endpoint`) targeting the Neo4j Aura PrivateLink service you provide via `service_name`.
- Optional Security Group (managed) that allows inbound 80/443/7687 from allowed CIDRs (defaults to the VPC CIDR).
- Private DNS enabled on the endpoint (when supported by the service).
 - Optional networking when `vpc_id`/`subnet_ids` are omitted: a VPC (`10.16.0.0/16`), three private subnets for the endpoint ENIs, plus one public subnet, Internet Gateway, and a public route table for the test VM.

## Prerequisites
- Terraform >= 1.3
- AWS provider >= 5.x
- AWS credentials configured in your environment (e.g., via `aws configure`, environment variables, or a profile).

## Inputs you need
- `vpc_id`: The VPC to connect from. If omitted, a new VPC is created.
- `subnet_ids`: One or more subnets for the endpoint ENIs. If omitted, three subnets are created across available AZs.
- `service_name`: The Neo4j Aura PrivateLink service name.
- Optionally, you can supply existing `security_group_ids` or let this module create one that opens ports 80, 443, and 7687.

## Usage
1. Copy `examples/terraform.tfvars.example` to `terraform.tfvars` and fill in your values.
2. Initialize, plan, and apply:

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

3. On success, note the outputs:
   - `vpc_endpoint_id`: The ID of the created endpoint.
   - `vpc_endpoint_dns_entries`: DNS entries for verification/troubleshooting.
   - `vpc_endpoint_network_interface_ids`: ENIs created (one per subnet).
   - `security_group_id`: If a managed Security Group was created.

## Initial two-step setup (required)
Private DNS can only be enabled after Neo4j Aura accepts your endpoint connection. Do this once per VPC:

1) Create the endpoint with Private DNS disabled

```hcl
# terraform.tfvars (first apply)
enable_private_dns = false
```

```bash
terraform apply -auto-approve
```

Record the output `vpc_endpoint_id`.

2) Accept the endpoint in Aura console
- In Aura console, open your deployment → Network Access → Edit network access configuration.
- Find your newly created endpoint request (`vpce-...`) and click Accept.

3) Enable Private DNS and apply again

```hcl
# terraform.tfvars (second apply)
enable_private_dns = true
```

```bash
terraform apply -auto-approve
```

After this, the endpoint will have Private DNS enabled and DNS names resolvable inside your VPC.

### Optional: Test EC2 VM
Set `create_test_vm = true` to spin up a small EC2 instance. By default:
- If networking is auto-created, a public subnet and Internet Gateway are created and the VM gets a public IP.
- If you provide an existing VPC, the VM will use the first provided subnet unless you set `test_vm_subnet_id`. Set `test_vm_public_ip = true` and ensure the subnet is public (has a route to an IGW) if you want SSH over the Internet.

SSH and keys:
- If you set `test_vm_key_name`, that key pair is used.
- If not, Terraform generates a key pair (`test_vm_generated_key_name`) and writes the private key to `test_vm_private_key_output_path` (default `ssh/test-vm-key.pem`, mode 0400). Keep it safe.

The test VM reuses the endpoint Security Group. Allow SSH from your IPs via `test_vm_ssh_cidr_blocks` (Terraform adds port 22 rules to the SG).

Outputs include `test_vm_instance_id`, `test_vm_private_ip`.

## Private DNS
This configuration sets `private_dns_enabled = true` by default. The underlying service must support Private DNS; if it does not, set `enable_private_dns = false`.

## Security group behavior
- By default, a managed Security Group is created with inbound rules for TCP ports 80, 443, and 7687. The source is `allowed_cidr_blocks` if provided, otherwise the VPC CIDR.
- To reuse an existing Security Group, set `create_security_group = false` and provide `security_group_ids = ["sg-..."]`.

## Example `terraform.tfvars`
See `examples/terraform.tfvars.example`:

```hcl
aws_region   = "us-east-1"
vpc_id       = "vpc-0123456789abcdef0"
subnet_ids   = [
  "subnet-aaaabbbbcccc11111",
  "subnet-ddddeeeeffff22222",
  "subnet-gggghhhhiiii33333",
]
service_name = "com.amazonaws.vpce.us-east-1.vpce-svc-000000000000000"
```

## Clean up
```bash
terraform destroy -auto-approve
```

## Notes
- The `service_name` is region-specific. Ensure `aws_region` matches the region in the service name.
- Subnets must belong to the provided VPC and should be in distinct AZs for high availability.
- Your application traffic to Neo4j Aura will flow through the endpoint ENIs within your VPC.
