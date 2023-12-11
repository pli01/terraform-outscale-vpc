#
# nat gw
#
locals {
  nat_public_ip_map = { for entry in flatten([
    for k, v in local.resources.subnets : {
      key = v.nat_service,
      value = {
        public_ip_id : contains(keys(local.resources.public_ip[v.nat_service]), "public_ip") ? data.outscale_public_ip.public_ip[v.nat_service].public_ip_id : outscale_public_ip.public_ip[v.nat_service].public_ip_id
        subnet_id : outscale_subnet.subnet[k].subnet_id
      }
    } if contains(keys(v), "nat_service")
  ]) : entry.key => entry.value }
}

resource "outscale_nat_service" "nat_service" {

  for_each = local.nat_public_ip_map

  subnet_id    = each.value.subnet_id
  public_ip_id = each.value.public_ip_id

  tags {
    key   = "Name"
    value = format("%s-%s", local.config.default.prefix_name, each.key)
  }
  tags {
    key   = "Env"
    value = local.config.default.prefix_name
  }
}
