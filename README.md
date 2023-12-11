# terraform-outscale-vpc

This repository enable you to create a VPC and a set of resources in the Outscale Cloud from terraform files and a description and configuration yaml file

## What does it do?

You describe the topology in one Yaml configuration file (`config.yml`), then execute terraform, and the following resources are created:
- net
- public_ip
- subnets
- internet_service
- nat_service
- route_table
- security_group
- load_balancers
- instances

Yaml config file is decoded with, Terraform templatefile and yamldecode functions

The yaml file allows a human representation of configuration variables.

After decoded, the representation is an HCL syntax in the form of a map variable in terraform passed to outscale terraform resources

The yaml file support a subset of YAML 1.2
- Yaml anchor can be used to create multiple reference list. Don't repeat your self (example: define multiple `ip_ranges_cidr`, `vm_types`, image_id, inboud_rules,....)
- yaml config file is also a terraform templatefile. It support variables interpolation based on parameters map defined in terraform tfvars (ex: ${env})

An S3 Backend state template is available in `backend.tf.erb`

Sample config files are available in config-sample file and directory

See https://registry.terraform.io/providers/outscale/outscale/latest/docs for more details on outscale resources configuration

## Getting started: How to use this module

To use this module, See a complete example in examples/simple-instance-docker-compose

In brief:
- declare the following in your main.tf
```
# your main.tf
#
# providers
#
terraform {
  required_providers {
    outscale = {
      source  = "outscale/outscale"
      version = "0.10.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.3"
    }
  }
}

provider "outscale" {
  # Configuration options
  # use env variables
  #   OUTSCALE_ACCESSKEYID
  #   OUTSCALE_SECRETKEYID
  #   OUTSCALE_REGION
}

#
# variables
#
variable "config_file" {
  description = "config.yml file"
  type        = string
}

variable "parameters" {
  description = "parameters variables defines in yaml template config file"
  type        = map(any)
}

module "vpc" {
  source = "github.com/pli01/terraform-outscale-vpc"

  config_file = var.config_file
  parameters  = var.parameters
}
output "vpc" {
  value = module.vpc
}
```

- copy `config-sample.yml` (or one of the files in config-sample directory) to `config.yml` (default `config_file` from variables.tf) and modify to your needs
- copy `cloud-init` scripts (or define your own) to  your directory, adjust path script file in config.yml. modify to your needs
- copy `terraform.tfvars.sample` to `terraform.tfvars` and modify to your needs
- create S3 bucket to store tfstate

```shell
# example with aws cli
aws s3api create-bucket --bucket tfstate-bucket --acl private
```

- generate `backend.tf` from `backend.tf.erb` (or modify backend.tf.sample)

```shell
# set shell variable (modify to your needs)
export S3_BACKEND_TFSTATE_BUCKET=tfstate-bucket
export S3_BACKEND_TFSTATE_FILE=dev/dev.tfstate
export AWS_DEFAULT_REGION=cloudgouv-eu-west-1
export AWS_S3_ENDPOINT=oos.cloudgouv-eu-west-1.outscale.com

# create backend.tf file
erb backend.tf.erb > backend.tf
```

- terraform it !

```bash
terraform init
terraform plan
terraform apply
```

## Description of the yaml configuration file

### Syntax

Th yaml file contains 2 sections:
- `default`: for default parameters or yaml anchor definition
- `resources`: to define resources to create

Each resources describe the configuration and is associated to a terraform file for the logic

### default

Define default parameters and yaml anchor

```yml
default:
  region: eu-west-2              # define region name
  prefix_name: dev               # define prefix use to tag resources
  keypair_name: default-key      # define default keypair name
  #
  # or use ${var} and define var in parameters map in terraform.tfvars
  # region: ${region_name}       # define region_name in parameters map  { "region_name" = "eu-west-2"}
  # prefix_name: ${prefix_name}  # or define prefix_name in parameters map: { "prefix_name" = "dev"}
  # keypair_name: ${keypair_name}# or define default keypair name in parameters map: { "keypair_name" = "default-key"}

  # remove_default_outbound_rule: true # remove default outbound security group. You can define your own outbound SG
```

```yml
#
# Optional: Define extra yaml anchor and reuse it in all others sections
#
  images:
    debian: &debian             # define a debian yaml anchor and reuse it the instances section, with `*debian`
      ami-0236ba54

  vm_type_list:
    server_type: &server_type
      t2.micro

  cloud_init:
    cloudinit_sample: &cloudinit_sample  # define a yaml anchor for multipart mime cloud_init
      - filename: cloud-init.yaml
        content_type: text/cloud-config
        cloud-config:                                      # sample cloud-config
          merge_how: dict(recurse_array)+list(append)
          packages:
            - jq
          runcmd:
            - [ sh, -xc, "echo $(date) ': hello world!'" ]
          final_message: "The instance is up, after $UPTIME seconds"

```

### resources

#### public_ip

```yml
# define public ip reservation/allocation
  public_ip:                    # define public ip reservation/allocation
    nat01: {}                   #  allocate public ip for nat service
    lb01: {}                    #  allocate public ip for loadbalancer
    bastion:                    # optional: declare a pre reserved public ip for bastion
      public_ip: XXX.XX.XX.XXX  #  define here the public_ip allocated outside this terraform module
```

#### net
```yml
  net:
    name: net01
    ip_range: 172.16.0.0/16     # define ip_range for the vpc
    tags:
      # use this tag to enable security group on vm in same subnet
      osc.fcu.enable_lan_security_groups: true
```
#### internet_service
```yml
  internet_service:
    internet01:                 # define on internet_service in one region
  # internet02:                 # define on internet_service in another region
```

#### subnets
```yml
  subnets:
    # define public subnet, route table use internet service ad default gw
    public-front-a:               # subnet name
      ip_range: 172.16.0.0/24     # define ip_range subnet in vpc net range
      subregion_name: a           # subregion_name: last letter of sub region (a,b,..)
      nat_service: nat01          # create one nat_service for private instances, without public_ip in one region
      route:                      # define route lists
        - destination_ip_range: 0.0.0.0/0
          gateway_id: internet01  # default gw for public-front-a in region a (use internet02, on another region)

    # define private subnet, route table use nat service as default gw
    private-front-a:
      ip_range: 172.16.1.0/24
      subregion_name: a
      route:
        - destination_ip_range: 0.0.0.0/0
          nat_service_id: nat01  # default gw for private instance without public_ip

    # Optional: define private subnet, route table use nat VM interface as default gw
    private-back-a:
      ip_range: 172.16.2.0/24
      subregion_name: a
      route:
        - destination_ip_range: 0.0.0.0/0
          nic_id: fw-0-0        # optional: define vm nic reference if vm act as a nat gateway

```
#### load_balancers

```yml
  load_balancers:
    lb01:
      load_balancer_type: internet-facing  # use 'internal' for internal LB
      public_ip: lb01
      subnets:
        - public-front-a
      security_groups:
        - out-restricted-to-all
        - in-web-from-all

      listeners:                  # define lb listeners (here only http)
        - load_balancer_port: 80
          load_balancer_protocol: HTTP
          backend_port: 80
          backend_protocol: HTTP
          # server_certificate_id: ORN

#      access_log:                # send lb logs to S3 bucket
#        is_enabled: false        # true to enable
#        publication_interval: 5
#        osu_bucket_name: lb-logs
#        osu_bucket_prefix: access-logs-lb01

      health_check:              # define healthcheck to  backend_vms
        - healthy_threshold: 10
          check_interval: 40
          path: "/"
          port: 80
          protocol: HTTP
          timeout: 10
          unhealthy_threshold: 8

      backend_vms:              # define a list of backend_vms
        - web-a                 #  reference to a group of instances in sub region a (all vms define with count value are added to the backend)
        - web-b                 #  reference to a group of instances in sub region b (all vms define with count value are added to the backend)
```

#### security_groups

```yml
  security_groups:
    out-restricted-to-all:
      - flow: Outbound           # Define restricted outbound SG (allow only outbound ports: dns, ntp, http, https)
        rules:
          - from_port_range: 53
            to_port_range: 53
            ip_protocol: tcp
            ip_ranges:
              - 0.0.0.0/0
          - from_port_range: 53
            to_port_range: 53
            ip_protocol: udp
            ip_ranges:
              - 0.0.0.0/0
          - from_port_range: 123
            to_port_range: 123
            ip_protocol: udp
            ip_ranges:
              - 0.0.0.0/0
          - from_port_range: 80
            to_port_range: 80
            ip_protocol: tcp
            ip_ranges:
              - 0.0.0.0/0
          - from_port_range: 443
            to_port_range: 443
            ip_protocol: tcp
            ip_ranges:
              - 0.0.0.0/0

    in-ssh-from-all:           # allow ssh from all (or range of ip)
      - flow: Inbound
        rules:
          - from_port_range: "22"
            to_port_range: "22"
            ip_protocol: tcp
            ip_ranges:
              - 0.0.0.0/0
              - *somehosts        # you can define Yaml anchor to a list of authorized IPs or IP range

    in-ssh-from-bastion:          # allow ssh from dedicated bastion private ip
      - flow: Inbound
        rules:
          - from_port_range: "22"
            to_port_range: "22"
            ip_protocol: tcp
            ip_ranges:           # optional: specify IP/CIDR
              - 172.16.0.100/32
            vm_ranges:           # optional: specify instance group to allow (all ips are resolved and added to the rule)
              - bastion
            subnet_ranges:       # optional: specity subnet to allow (all ip_range are added to the rule)
              - admin-front-a

    in-all-from-all:          # warning: this SG allow all from all
      - flow: Inbound
        rules:
         - ip_protocol: "-1"
           ip_ranges:
              - 0.0.0.0/0

```
#### instances
Create one or multiple instances resource group
- use count to define the number of instances to create. Act as a servergroup
- define image_id, vm_type
- define interfaces list
- optional: define volumes list, root volume, or multiple extra volumes
- optional: define `cloudinit_multipart` to configure instances at bootstrap time with cloud-config or shell scripts
  - sample cloudinit files are in `cloud-init` directory

```yml
  instances:
    bastion:
      count: 1                      # default count = 1,   instance name will be : bastion-0
      vm_type: t2.micro             # vm type
      image_id: ami-0236ba54        # image debian
      interfaces:                   # define interfaces list
        - subnet: public-front-a    # define the subnet key to attach the nic interface. first interface will be named bastion-0-0
          private_ip: 172.16.0.10   # optional: define static private ip. Comment it to allocate dynamic ip  (use it only with count = 1)
          public_ip: bastion        # optional: reference key to public_ip key (use it only with count = 1)
          security_groups:          # define security groups list
            - in-ssh-from-all       # reference a list of security_groups key
        - subnet: private-front-a    # define the subnet key to attach the nic interface. second interface will be named bastion-0-1
          private_ip: 172.16.1.10
          security_groups:
            - in-all-from-all

    web:
      count: 2                      # define servergroup of instances . if count >1 , dhcp only, no private_ip, no public_ip key
                                    # instances name will be server-0, server-1
                                    # first instances interfaces will be server-0-0, server-1-0
      vm_type: *server_type         # optional: use yaml anchor
      image_id: *debian             # optional: use yaml anchor
      tags:
        # use this tags to repulse instances on different hypervisor
        osc.fcu.repulse_server_strict: web
      interfaces:                   # interfaces list: web-0-0 will be the first interface of first server, web-1-0, will be first interface of second server
        - subnet: private-front-a
          security_groups:
            - in-ssh-from-bastion
            - in-web-from-all
      enable_user_data: true        # enable user_data and cloudinit
      cloudinit_multipart:          # optional: define cloudinit multipart list
        *cloudinit_web              #  use yaml anchor

    db:
      count: 2                      # define servergroup of instances . if count >1 , dhcp only, no private_ip, no public_ip key
                                    # instances name will be server-0, server-1, ....
      vm_type: *server_type         # optional: use yaml anchor
      image_id: *debian             # optional: use yaml anchor
      tags:
        # use this tags to repulse instances on different hypervisor
        osc.fcu.repulse_server_strict: db
      interfaces:                   # interfaces list: db-0-0 will be first interface of first server, db-1-0, will be first interface of second server
        - subnet: private-back-a
          security_groups:
            - in-ssh-from-bastion
            - in-db-from-web
      volumes:                      # optional: define dedicated volumes map
        - name: root                # optional: define root volume
          device_name: /dev/sda1    # root disk must be /dev/sda1 see outscale_vm, or outscale_volume for details
          size: 11
        - name: data                # optional: define other data volumes
          device_name: /dev/sdb
          size: 15
          #type:
          #iops:
          #delete_on_vm_deletion: false
          #state: detached          # optional: detach volume from instance without deleting volume
#        - name: other               # optional: define external volumes created outside of this terraform
#          device_name: /dev/sdc
#          volume_id: vol-xxxxx      #  volume id
```

#### cloudinit_multipart

```yml
default:
  cloud_init:
    #
    # define cloud_init anchor for web instances
    #   below a multipart mime with 2 files and 1 template
    #
    cloudinit_web: &cloudinit_web              # define a cloud_init anchor for web instances
      - filename: cloud-init.yaml
        content_type: text/cloud-config
        file: cloud-init/cloud-config.yml      # file is located in ./
      - filename: config-script.sh
        content_type: text/x-shellscript
        file: cloud-init/config-script-web.sh  # file is located in ./
      - filename: config-script-demo.sh
        content_type: text/x-shellscript
        templatefile: cloud-init/config-script-demo.sh.tftpl # templatefile is located in ./. Can use ${var} in it and define var in parameters map

    #
    # define cloud_init anchor for web instances
    #   below a multipart mime with 1 inline cloud-config syntax
    #

    cloudinit_sample: &cloudinit_sample
      - filename: cloud-init.yaml
        content_type: text/cloud-config
        cloud-config:                                      # sample cloud-config
          merge_how: dict(recurse_array)+list(append)
          packages:
            - jq
          runcmd:
            - [ sh, -xc, "echo $(date) ': hello world!'" ]
          final_message: "The instance is up, after $UPTIME seconds"

    #
    # define cloud_init anchor for web instances
    #   below a multipart mime with 1 inline shell script
    #
    cloudinit_web_script: &cloudinit_web_script
      - filename: config-script-web.sh
        content_type: text/x-shellscript
        content: |                                        # sample shell script
          #!/bin/bash
          apt-get update -qy
          apt-get install -qy lighttpd
          echo "Hello World! I'm starting up now" > $HOME/out


```


### Description of the sample config file

The sample config file `config-sample.yml` create the following resources:

- 1 net vpc with ip_range 172.16.0.0/16
- 3 subnets:
  - `public_front_a` 172.16.0.0/24 in subregion a
  - `private_front_a`: 172.16.1.0/24 in subregion a
  - `private_back_a`: 172.16.2.0/24 in subregion a
- 1 internet service
- 1 nat service in `public_front_a`
- reserved public_ips for nat, bastion and lb instances
- route tables per subnets
- security groups list
  - allow inbound ssh from all host to bastion
  - allow inbound http from all host to lb
  - allow outbound all from all to all
- 1 load_balancers , listen on http port with 2 web backend vms
- 2 type of instances: (with interfaces and root, data volumes)
  - 1 bastion instance , with one public_ip, 2 interfaces one in each network: `public_front_a`, `private_front_a`
  - 1 servergroup of 2 web instances in subnet `private_front_a`


See more examples in config-sample directory:
- config-sample/config-vpc-multiple-subnets-instances.yml
- config-sample/config-lb-multi-region.yml
- config-sample/config-simple-instance.yml
- config-sample/config-vpc-only-subnets.yml


```yml
#
# sample config
#
default:
  region: eu-west-2              # define region name
  prefix_name: dev               # define prefix use to tag resources
  # prefix_name: ${environment}  # define extra vars in parameters map: {environment=test}
  keypair_name: default-key      # define default keypair name
  #
  # extra_custom_parameters: ${my_var}  # define extra vars in parameters map: {my_var=test}
  #
  # simple yaml anchor supported
  #    define anchor and reuse it in the yaml file
  #
  ip_ranges_cidr:
    somehosts: &somehosts
      - 172.16.1.200/32
      - 172.16.1.201/32
      - 172.16.1.202/32
  images:
    debian: &debian             # define a debian yaml anchor and reuse it the instances section
      ami-0236ba54

  vm_type_list:
    server_type: &server_type
      t2.micro

  cloud_init:
    cloudinit_web: &cloudinit_web              # define a cloud_init anchor for web instances
      - filename: cloud-init.yaml
        content_type: text/cloud-config
        file: cloud-init/cloud-config.yml      # file is located in ./
      - filename: config-script.sh
        content_type: text/x-shellscript
        file: cloud-init/config-script-web.sh  # file is located in ./
      - filename: config-script-demo.sh
        content_type: text/x-shellscript
        templatefile: cloud-init/config-script-demo.sh.tftpl # templatefile is located in ./

    cloudinit_sample: &cloudinit_sample
      - filename: cloud-init.yaml
        content_type: text/cloud-config
        cloud-config:                                      # sample cloud-config
          merge_how: dict(recurse_array)+list(append)
          packages:
            - jq
          runcmd:
            - [ sh, -xc, "echo $(date) ': hello world!'" ]
          final_message: "The instance is up, after $UPTIME seconds"

    cloudinit_web_script: &cloudinit_web_script
      - filename: config-script-web.sh
        content_type: text/x-shellscript
        content: |                                        # sample shell script
          #!/bin/bash
          apt-get update -qy
          apt-get install -qy lighttpd
          echo "Hello World! I'm starting up now" > $HOME/out


#
# define resources to create
#
resources:
  #
  # public_ip
  #
  public_ip:                     # define public ip reservation/allocation
    nat01: {}                    #  allocate public ip for nat service
    web: {}
    bastion: {}
  #  bastion:                    # optional: declare a pre reserved public ip for bastion
  #    public_ip: XXX.XX.XX.XXX  #  define here the public_ip allocated outside this terraform module
  #
  # net
  #
  net:
    name: net01
    ip_range: 172.16.0.0/16     # define ip_range for the vpc
    tags:
      # This tag is needed to enable security group on vm in same subnet
      osc.fcu.enable_lan_security_groups: true
  #
  # internet_service
  #
  internet_service:
    internet01:                 # define on internet_service in one region
  # internet02:                 # define on internet_service in another region
  #
  # subnets
  #   route and route_table
  #   nat_service
  #
  subnets:
    public-front-a:               # subnet name
      ip_range: 172.16.0.0/24     # define ip_range subnet in vpc net range
      subregion_name: a           # subregion_name: last letter of sub region (a,b,..)
      nat_service: nat01          # create one nat_service for private instances, without public_ip in one region
      route:                      # define route lists
        - destination_ip_range: 0.0.0.0/0
          gateway_id: internet01  # default gw for public-front-a in region a (use internet02, on another region)
    private-front-a:
      ip_range: 172.16.1.0/24
      subregion_name: a
      route:
        - destination_ip_range: 0.0.0.0/0
          nat_service_id: nat01  # default gw for private instance without public_ip
    private-back-a:
      ip_range: 172.16.2.0/24
      subregion_name: a
      route:
        - destination_ip_range: 0.0.0.0/0
          nat_service_id: nat01
  #        nic_id: fw-0-0           # optional: define vm nic_id if vm act as a gateway instead of nat_service_id
  #
  # security group and rules
  #
  # security_groups: {}         # empty security groups map
  #
  security_groups:
    in-ssh-from-all:            # security group name
      - flow: Inbound           # define outscale_security_group_rule lists (see terraform outscale_security_group_rule)
        rules:                  # define rules list
        - from_port_range: "22" # start port range
          to_port_range: "22"   # end port range
          ip_protocol: "tcp"
          ip_ranges:
            - 0.0.0.0/0
            - *somehosts        # optional: use yaml anchor
    in-ssh-from-bastion:
      - flow: Inbound
        rules:
          - from_port_range: "22"
            to_port_range: "22"
            ip_protocol: "tcp"
            ip_ranges:
              - 172.16.0.10/32
    in-all-from-all:
      - flow: Inbound
        rules:
         - ip_protocol: "-1"
           ip_ranges:
              - 0.0.0.0/0
    in-web-from-all:
      - flow: Inbound
        rules:
        - from_port_range: "80"
          to_port_range: "80"
          ip_protocol: "tcp"
          ip_ranges:
            - 0.0.0.0/0
        - from_port_range: "443"
          to_port_range: "443"
          ip_protocol: "tcp"
          ip_ranges:
            - 0.0.0.0/0
  #
  # loadbalancers
  #
  # load_balancer_: {}
  load_balancers:
    lb01:
      load_balancer_type: internet-facing  # internal
      public_ip: lb01
      subnets:
        - public-front-a
      security_groups:
        - in-web-from-all
      listeners:
        - load_balancer_port: 80
          load_balancer_protocol: HTTP
          backend_port: 80
          backend_protocol: HTTP
          # server_certificate_id: ORN
      health_check:
        - healthy_threshold: 10
          check_interval: 40
          path: "/"
          port: 80
          protocol: HTTP
          timeout: 10
          unhealthy_threshold: 7
#      access_log:
#        is_enabled: true # false
#        publication_interval: 5
#        osu_bucket_name: lb-logs
#        osu_bucket_prefix: access-logs-lb01

      # backend_vms: []
      backend_vms:
        - web
  #
  # instances
  #   volumes list (root and multiple data volumes)
  #   interfaces list with fixed or dynamic ip, and public ip
  #
  # instances: {} # empty instances map
  #
  instances:
    bastion:
      count: 1                      # default count = 1,   instance name will be : bastion-0
      vm_type: t2.micro             # vm type
      image_id: ami-0236ba54        # image debian
      interfaces:                   # define interfaces list
        - subnet: public-front-a    #  first interface will be bastion-0-0  : define subnet key name
          private_ip: 172.16.0.10   # optional: define static private ip. Comment it to allocate dynamic ip
          public_ip: bastion        # optional: reference key to public_ip key
          security_groups:          # define security groups list
            - in-ssh-from-all       # reference a list of security_groups key
        - subnet: private-front-a   #  first interface will be bastion-0-1  : define subnet key name
          private_ip: 172.16.1.10
          security_groups:
            - in-all-from-all
    web:
      count: 2                      # define servergroup of instances . if count >1 , dhcp only, no private_ip, no public_ip key
                                    # instances name will be server-0, server-1, ....
      vm_type: *server_type         # optional: use yaml anchor
      image_id: *debian             # optional: use yaml anchor
      tags:
        # this tags to repulse instances on different hypervisor
        osc.fcu.repulse_server_strict: web
      cloudinit_multipart:          # optional: define cloudinit multipart list
        *cloudinit_web              #  use yaml anchor
      interfaces:                   # interfaces list: server-0-0 will be first interface of first server, server-1-0, will be first interface of second server
        - subnet: private-front-a
          security_groups:
            - in-ssh-from-bastion
            - in-web-from-all
      volumes:                      # optional: define dedicated volumes map
        - name: root                # optional: define root volume
          device_name: /dev/sda1    # root disk is /dev/sda1 see outscale_vm, or outscale_volume for details
          size: 11
  #      - name: data               # optional: define other data volumes
  #        device_name: /dev/sdb
  #        size: 15
  #        #type:
  #        #iops:
  #        #delete_on_vm_deletion: false
```

### Tips

* Yaml file and cloud-init templatefile support variables interpolation (`${var}`)

To set variables, declare variables in a map `parameters` with var, var-file or tfvars file

```
terraform apply -var 'parameters={"env":"test"}'
```

* To reinit load_balancers healthcheck, taint the healthcheck resource and apply

```
terraform taint 'outscale_load_balancer_attributes.health_check["lb01"]'
terraform apply
```

* To force instances group to different hypervisor (anti-affinity) use instance tags with value `osc.fcu.repulse_server_strict: web`
* To force instances group on same hypervisor (affinity) use instance tags with value `osc.fcu.attract_server_strict: samehost`
* To be more restricted and enable security group on vm in same subnet, use net tags `osc.fcu.enable_lan_security_groups: true`
See Details: https://docs.outscale.com/fr/userguide/R%C3%A9f%C3%A9rence-des-tags-user-data.html




