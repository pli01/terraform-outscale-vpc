#
# security group
#
locals {
  sg_rules = { for entry in flatten([
    for k, v in local.resources.security_groups : [
      for r, t in v : {
        key   = format("%s-%s", k, r)
        value = merge(t, { sg = k })
      } if contains(keys(t), "rules")
    ]
  ]) : entry.key => entry.value }
}

resource "outscale_security_group" "sg" {
  for_each = local.resources.security_groups

  description         = each.key
  security_group_name = each.key
  net_id              = outscale_net.net.net_id

  remove_default_outbound_rule = contains(keys(local.config.default), "remove_default_outbound_rule") ? local.config.default.remove_default_outbound_rule : false

  tags {
    key   = "Name"
    value = format("%s-%s", local.config.default.prefix_name, each.key)
  }
  tags {
    key   = "Env"
    value = local.config.default.prefix_name
  }
}

resource "outscale_security_group_rule" "sg_rule" {
  for_each = local.sg_rules

  flow = each.value.flow

  security_group_id = outscale_security_group.sg[each.value.sg].security_group_id

  dynamic "rules" {
    for_each = toset(each.value.rules)
    content {
      from_port_range = contains(keys(rules.value), "from_port_range") ? rules.value.from_port_range : null
      to_port_range   = contains(keys(rules.value), "to_port_range") ? rules.value.to_port_range : null
      ip_protocol     = contains(keys(rules.value), "ip_protocol") ? rules.value.ip_protocol : null
      ip_ranges       = contains(keys(rules.value), "ip_ranges") ? flatten(rules.value.ip_ranges) : null
    }
  }
}
