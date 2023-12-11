variable "name" {}
variable "value" {}
variable "maxcount" {}
variable "config" {}
variable "subnet_map" {}
variable "public_ip_map" {}
variable "security_group_map" {}
variable "subregion_name" {}

locals {
  separator = "-"

  # create a map from "server_name-index_vm-index_interfaces"
  interface_list = { for entry in flatten([
    for i in range(var.maxcount) : [
      for k, v in var.value.interfaces : {
        key = format("%s%s%s%s%s", var.name, local.separator, i, local.separator, k)
        value = merge(v, {
          subnet_id : var.subnet_map[v.subnet]
          public_ip_id : contains(keys(v), "public_ip") ? var.public_ip_map[v.public_ip].public_ip_id : null
          #
          # resolve security group id (TODO: add default if defined)
          #
          security_group_id : contains(keys(v), "security_groups") ? flatten([for s in v.security_groups : var.security_group_map[s]]) : null
        })
      }
    ]
  ]) : entry.key => entry.value }

  # create a map from "server_name-index_vm-index_volumes"
  volume_list = contains(keys(var.value), "volumes") ? { for entry in flatten([
    for i in range(var.maxcount) : [
      for k, v in var.value.volumes : {
        key   = format("%s%s%s%s%s", var.name, local.separator, i, local.separator, v.name)
        value = merge(v, { index : i }, { state : contains(keys(v), "state") ? v.state : "attaching" })
      }
    ]
  ]) : entry.key => entry.value } : {}

  #  output_volumes_map = { for entry in flatten([
  #    for i in range(var.maxcount) : [
  #      for k, v in var.value.volumes : {
  #        key   = "${var.name}-${i}-${v.name}"
  #        value = outscale_vm.vm[i].block_device_mappings_created[k].bsu.volume_id
  #      }
  #    ]
  #  ]) : entry.key => entry.value }
}

#
# nic
#
resource "outscale_nic" "nic" {
  for_each = { for k, v in local.interface_list : k => v }

  subnet_id = each.value.subnet_id

  security_group_ids = contains(keys(each.value), "security_group_id") ? flatten([each.value.security_group_id]) : []

  dynamic "private_ips" {
    for_each = contains(keys(each.value), "private_ip") ? [each.value.private_ip] : []
    content {
      is_primary = true
      private_ip = private_ips.value
    }
  }
}

#
# public ip link to nic
#
resource "outscale_public_ip_link" "public_ip_link" {
  for_each = { for k, v in local.interface_list : k => v if contains(keys(v), "public_ip") }

  public_ip_id = each.value.public_ip_id
  nic_id       = outscale_nic.nic[each.key].nic_id
  # private_ip   = each.value.private_ip
}

##
## external attached volume
##
resource "outscale_volume" "volume" {
  for_each = { for k, v in local.volume_list : k => v if v.name != "root" && !contains(keys(v), "volume_id") }

  size           = each.value.size
  subregion_name = var.subregion_name
  volume_type    = contains(keys(each.value), "type") ? each.value.type : null
  iops           = contains(keys(each.value), "iops") ? each.value.iops : null
  snapshot_id    = contains(keys(each.value), "snapshot_id") ? each.value.snapshot_id : null

  tags {
    key   = "Name"
    value = format("%s-%s", var.config.default.prefix_name, each.key)
  }
  tags {
    key   = "Env"
    value = var.config.default.prefix_name
  }
}

resource "outscale_volumes_link" "volumes_link" {
  for_each = { for k, v in local.volume_list : k => v if v.name != "root" && v.state != "detached" }

  device_name = each.value.device_name
  volume_id   = contains(keys(each.value), "volume_id") ? each.value.volume_id : outscale_volume.volume[each.key].id
  vm_id       = outscale_vm.vm[each.value.index].id
}

locals {
  state = contains(keys(var.value), "state") ? var.value.state : "running"
}

#
# vm
#
resource "outscale_vm" "vm" {
  count        = var.maxcount
  image_id     = var.value.image_id
  vm_type      = var.value.vm_type
  keypair_name = var.config.default.keypair_name
  state        = local.state

  user_data = local.enable_user_data ? local.user_data : null

  # placement_subregion_name = var.subregion_name

  is_source_dest_checked = contains(keys(var.value), "is_source_dest_checked") ? var.value.is_source_dest_checked : true

  # link nics
  dynamic "nics" {
    for_each = { for k, v in var.value.interfaces : k => v }

    content {
      nic_id        = outscale_nic.nic[format("%s%s%s%s%s", var.name, local.separator, count.index, local.separator, nics.key)].nic_id
      device_number = nics.key
    }
  }

  #
  # resized bootdisk volume
  #
  dynamic "block_device_mappings" {
    for_each = { for k, v in local.volume_list : k => v if k == "${var.name}-${count.index}-root" }
    iterator = volume

    content {
      device_name = volume.value.device_name

      dynamic "bsu" {
        for_each = toset([volume.value.name])
        content {
          volume_size           = volume.value.size
          volume_type           = contains(keys(volume.value), "type") ? volume.value.type : null
          iops                  = contains(keys(volume.value), "iops") ? volume.value.iops : null
          snapshot_id           = contains(keys(volume.value), "snapshot_id") ? volume.value.snapshot_id : null
          delete_on_vm_deletion = contains(keys(volume.value), "delete_on_vm_deletion") ? volume.value.delete_on_vm_deletion : true
        }
      }
    }
  }

  dynamic "tags" {
    for_each = merge(tomap({
      "Name" = format("%s-%s-%s", var.config.default.prefix_name, var.name, count.index),
      "Env"  = var.config.default.prefix_name,
      }), contains(keys(var.value), "tags") ? var.value.tags : {}
    )
    content {
      key   = tags.key
      value = tags.value
    }
  }

  depends_on = [outscale_nic.nic]
  # don't force-recreate instance if only user data changes
  lifecycle {
    ignore_changes = [user_data]
  }

}

output "cloudinit_multipart" {
  value = local.cloudinit_part
}
output "volume_list" {
  value = local.volume_list
}

output "interface_list" {
  value = local.interface_list
}

output "private_ip_list" {
  value = { for k, v in outscale_nic.nic : k => element([for a, b in v.private_ips : b.private_ip], 0) }
}

output "private_ip" {
  value = flatten([for k, v in outscale_nic.nic : [element([for a, b in v.private_ips : b.private_ip], 0)]])
}


output "nic_id_list" {
  value = { for k, v in outscale_nic.nic : k => v.nic_id }
}
output "nic" {
  value = outscale_nic.nic
}
output "vm" {
  value = outscale_vm.vm
}

output "vm_id" {
  value = { for k, v in outscale_vm.vm : k => v.id }
}


#output "volumes_map" {
#  value = local.output_volumes_map
#}

output "user_data" {
  value = local.user_data
}

