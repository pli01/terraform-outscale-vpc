#
# net
#
resource "outscale_net" "net" {
  ip_range = local.resources.net.ip_range

  dynamic "tags" {
    for_each = merge(tomap({
      "Name" = format("%s-%s", local.config.default.prefix_name, local.resources.net.name),
      "Env"  = local.config.default.prefix_name,
      }),
      contains(keys(local.resources.net), "tags") ? local.resources.net.tags : {}
    )
    content {
      key   = tags.key
      value = tags.value
    }
  }
}

#
# subnets
#
resource "outscale_subnet" "subnet" {
  for_each       = local.resources.subnets
  net_id         = outscale_net.net.net_id
  ip_range       = each.value.ip_range
  subregion_name = contains(keys(each.value), "subregion_name") ? format("%s%s", local.config.default.region, each.value.subregion_name) : data.outscale_subregions.all_subregions.subregions[0].subregion_name

  dynamic "tags" {
    for_each = merge(tomap({
      "Name"      = format("%s-%s", local.config.default.prefix_name, each.key),
      "Env"       = local.config.default.prefix_name,
      "Subregion" = contains(keys(each.value), "subregion_name") ? format("%s%s", local.config.default.region, each.value.subregion_name) : data.outscale_subregions.all_subregions.subregions[0].subregion_name
      }),
      contains(keys(each.value), "tags") ? each.value.tags : {}
    )
    content {
      key   = tags.key
      value = tags.value
    }
  }

}

locals {
  subnet_map = { for k, v in outscale_subnet.subnet : k => v.id }
}
