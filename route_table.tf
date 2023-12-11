##
## route table
##
locals {
  route_map = flatten([
    for k, v in local.resources.subnets : [
      for subnet_k, subnet_v in v :
      [for a, b in subnet_v : merge({
        key : format("%s-%s", k, a),
        subnet : k,
        },
        b
      )] if subnet_k == "route"
    ]
  ])
}

resource "outscale_route_table" "route_table" {
  for_each = { for k, v in local.resources.subnets : k => v if contains(keys(v), "route") }
  net_id   = outscale_net.net.net_id
  tags {
    key   = "Name"
    value = format("%s-%s", local.config.default.prefix_name, each.key)
  }
  tags {
    key   = "Env"
    value = local.config.default.prefix_name
  }
}

resource "outscale_route_table_link" "route_table_link" {
  for_each       = { for k, v in local.resources.subnets : k => v if contains(keys(v), "route") }
  subnet_id      = outscale_subnet.subnet[each.key].subnet_id
  route_table_id = outscale_route_table.route_table[each.key].id
}

#
# route with internet service and gateway_id must be created before the nat_service
# tf parallelism must be greater than number of nat services
#
resource "outscale_route" "gateway_route" {
  for_each = { for k, v in local.route_map : v.key => v if contains(keys(v), "gateway_id") }

  destination_ip_range = each.value.destination_ip_range
  route_table_id       = outscale_route_table.route_table[each.value.subnet].route_table_id
  gateway_id           = contains(keys(each.value), "gateway_id") ? outscale_internet_service.internet_service[each.value.gateway_id].internet_service_id : null
}

resource "outscale_route" "nat_route" {
  for_each = { for k, v in local.route_map : v.key => v if contains(keys(v), "nat_service_id") }

  destination_ip_range = each.value.destination_ip_range
  route_table_id       = outscale_route_table.route_table[each.value.subnet].route_table_id
  nat_service_id       = contains(keys(each.value), "nat_service_id") ? outscale_nat_service.nat_service[each.value.nat_service_id].nat_service_id : null
}

resource "outscale_route" "nic_route" {
  for_each = { for k, v in local.route_map : v.key => v if contains(keys(v), "nic_id") }

  destination_ip_range = each.value.destination_ip_range
  route_table_id       = outscale_route_table.route_table[each.value.subnet].route_table_id
  nic_id               = contains(keys(each.value), "nic_id") ? tostring(local.nic_id_map[each.value.nic_id]) : null
}
