terraform {
  required_providers {
    outscale = {
      source  = "outscale/outscale"
      version = "1.2.1"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.3"
    }
  }
}

#provider "outscale" {
# Configuration options
# use env variables
#   OUTSCALE_ACCESSKEYID
#   OUTSCALE_SECRETKEYID
#   OUTSCALE_REGION
#}
