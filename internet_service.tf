#
# igw
#
resource "outscale_internet_service" "internet_service" {
  for_each = local.resources.internet_service
  tags {
    key   = "Name"
    value = format("%s-%s", local.config.default.prefix_name, each.key)
  }
  tags {
    key   = "Env"
    value = local.config.default.prefix_name
  }
}

resource "outscale_internet_service_link" "internet_service_link" {
  for_each            = local.resources.internet_service
  net_id              = outscale_net.net.net_id
  internet_service_id = outscale_internet_service.internet_service[each.key].id
}
