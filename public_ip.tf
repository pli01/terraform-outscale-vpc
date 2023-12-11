#
# public_ip
#
resource "outscale_public_ip" "public_ip" {
  for_each = { for k, v in local.resources.public_ip : k => v if !contains(keys(v), "public_ip") }
  tags {
    key   = "Name"
    value = format("%s-%s", local.config.default.prefix_name, each.key)
  }
  tags {
    key   = "Env"
    value = local.config.default.prefix_name
  }
}

data "outscale_public_ip" "public_ip" {
  for_each = { for k, v in local.resources.public_ip : k => v if contains(keys(v), "public_ip") }

  filter {
    name   = "public_ips"
    values = [each.value.public_ip]
  }
}
