#
# load_balancers
#
resource "outscale_load_balancer" "lb" {
  for_each           = local.resources.load_balancers
  load_balancer_name = format("%s-%s", local.default.prefix_name, each.key)
  load_balancer_type = each.value.load_balancer_type

  dynamic "listeners" {
    for_each = each.value.listeners

    content {
      load_balancer_protocol = listeners.value.load_balancer_protocol
      load_balancer_port     = listeners.value.load_balancer_port
      backend_port           = listeners.value.backend_port
      backend_protocol       = listeners.value.backend_protocol
    }
  }
  subnets         = flatten([for s in each.value.subnets : outscale_subnet.subnet[s].id])
  security_groups = flatten([for s in each.value.security_groups : local.security_group_map[s]])
  public_ip       = contains(keys(each.value), "public_ip") ? local.public_ip_map[each.value.public_ip].public_ip : null

  tags {
    key   = "Name"
    value = format("%s-%s", local.default.prefix_name, each.key)
  }
  tags {
    key   = "Env"
    value = local.default.prefix_name
  }
  depends_on = [
    outscale_public_ip.public_ip,
    data.outscale_public_ip.public_ip,
    outscale_route_table_link.route_table_link,
    outscale_route.gateway_route,
  ]
}

locals {
  lb_backend_vms = { for entry in flatten([
    for k, v in local.resources.load_balancers : [for a in v.backend_vms : {
      key   = k,
      value = module.instance[a].vm[*].vm_id
      } if length(module.instance[a].vm) > 0
    ]
  ]) : entry.key => entry.value... }
}

resource "outscale_load_balancer_vms" "lb_backend_vms" {
  for_each = local.lb_backend_vms

  load_balancer_name = outscale_load_balancer.lb[each.key].load_balancer_name
  backend_vm_ids     = flatten([each.value])
}

resource "outscale_load_balancer_attributes" "access_log" {
  for_each           = { for k, v in local.resources.load_balancers : k => v.access_log if contains(keys(v), "access_log") }
  load_balancer_name = outscale_load_balancer.lb[each.key].load_balancer_name

  dynamic "access_log" {
    for_each = flatten([{ for k, v in each.value : k => v }])

    content {
      publication_interval = access_log.value.publication_interval
      is_enabled           = access_log.value.is_enabled
      osu_bucket_name      = access_log.value.osu_bucket_name
      osu_bucket_prefix    = access_log.value.osu_bucket_prefix
    }
  }
}

resource "outscale_load_balancer_attributes" "health_check" {
  for_each           = { for k, v in local.resources.load_balancers : k => v.health_check if contains(keys(v), "health_check") }
  load_balancer_name = outscale_load_balancer.lb[each.key].load_balancer_name

  dynamic "health_check" {
    for_each = each.value

    content {
      healthy_threshold   = health_check.value.healthy_threshold
      check_interval      = health_check.value.check_interval
      path                = contains(keys(health_check.value), "path") ? health_check.value.path : null
      port                = health_check.value.port
      protocol            = health_check.value.protocol
      timeout             = health_check.value.timeout
      unhealthy_threshold = health_check.value.unhealthy_threshold
    }
  }
}

output "lb_dns_name" {
  value = { for k, v in outscale_load_balancer.lb : k => v.dns_name }
}
