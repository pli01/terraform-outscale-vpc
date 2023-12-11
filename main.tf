#
# load yaml-config
#
module "yaml-config" {
  source = "./modules/yaml-config"

  config_file = "${path.root}/${var.config_file}"
  parameters  = var.parameters
}

locals {
  config    = module.yaml-config.config
  resources = module.yaml-config.config.resources
  default   = module.yaml-config.config.default
}
