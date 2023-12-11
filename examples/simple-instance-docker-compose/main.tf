#
# load yaml-config
#
variable "config_file" {
  description = "config.yml file"
  type        = string
}

variable "parameters" {
  description = "parameters variables defines in yaml template config file"
  type        = map(any)
}

#
# 
#
module "vpc" {
#  source = "../.."
  source = "github.com/pli01/terraform-outscale-vpc"

  config_file = var.config_file
  parameters  = var.parameters
}
#
# outputs
#
output "vpc" {
  value = module.vpc
}
