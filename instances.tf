#
# instances
#
locals {

  public_ip_map = { for entry in flatten([
    for k, v in local.resources.public_ip : {
      key = k,
      value = {
        public_ip_id : contains(keys(v), "public_ip") ? data.outscale_public_ip.public_ip[k].public_ip_id : outscale_public_ip.public_ip[k].public_ip_id
        public_ip : contains(keys(v), "public_ip") ? data.outscale_public_ip.public_ip[k].public_ip : outscale_public_ip.public_ip[k].public_ip
      }
    }
  ]) : entry.key => entry.value }

  security_group_map = { for k, v in outscale_security_group.sg : k => v.id }

  nic_id_map = { for entry in flatten([
    for instance, instance_value in module.instance : [
      for key, value in instance_value.nic_id_list : {
        key   = key,
        value = value
      }
    ]
  ]) : entry.key => entry.value }

  private_ip_map = { for entry in flatten([
    for instance, instance_value in module.instance : [
      for key, value in instance_value.private_ip_list : {
        key   = key,
        value = value
      }
    ]
  ]) : entry.key => entry.value }


  #  volume_id_map = { for entry in flatten([
  #    for instance, instance_value in module.instance : [
  #      for key, value in instance_value.volumes_map : {
  #        key   = key,
  #        value = value
  #      }
  #    ]
  #  ]) : entry.key => entry.value }

}

module "instance" {
  source = "./modules/instance/vm"

  for_each = local.resources.instances

  name     = each.key
  value    = each.value
  maxcount = contains(keys(each.value), "count") ? each.value.count : 1

  parameters = var.parameters

  subregion_name     = contains(keys(each.value), "subregion_name") ? format("%s%s", local.config.default.region, each.value.subregion_name) : data.outscale_subregions.all_subregions.subregions[0].subregion_name
  security_group_map = local.security_group_map
  public_ip_map      = local.public_ip_map
  subnet_map         = local.subnet_map
  config             = local.config

  depends_on = [outscale_route.gateway_route, outscale_route.nat_route]
}

