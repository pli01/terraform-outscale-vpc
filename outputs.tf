#
# outputs
#
output "vpc_id" {
  value = outscale_net.net.id
}

output "public_ip" {
  value = local.public_ip_map
}

output "subnet_map" {
  value = local.subnet_map
}
output "nic_id_map" {
  value = local.nic_id_map
}

output "private_ip_map" {
  value = local.private_ip_map
}

output "vm_id" {
  value = { for k, v in module.instance : k => v.vm_id }
}



#output "volume_id_map" {
#  value = local.volume_id_map
#}
#output "instances" {
#  value = module.instance
#}
#
