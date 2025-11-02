output "vpc_endpoint_id" {
  description = "The ID of the created VPC Interface Endpoint."
  value       = aws_vpc_endpoint.aura.id
}

output "vpc_endpoint_dns_entries" {
  description = "DNS entries for the endpoint. Use these for verification/troubleshooting."
  value       = aws_vpc_endpoint.aura.dns_entry
}

output "vpc_endpoint_network_interface_ids" {
  description = "Network Interface IDs created for the endpoint (one per subnet)."
  value       = aws_vpc_endpoint.aura.network_interface_ids
}

output "security_group_id" {
  description = "ID of the managed Security Group (if created)."
  value       = try(aws_security_group.this[0].id, null)
}

output "test_vm_instance_id" {
  description = "ID of the test EC2 instance (if created)."
  value       = try(aws_instance.test[0].id, null)
}

output "test_vm_private_ip" {
  description = "Private IP of the test EC2 instance (if created)."
  value       = try(aws_instance.test[0].private_ip, null)
}


