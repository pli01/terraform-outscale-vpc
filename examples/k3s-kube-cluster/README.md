# k3s kube cluster

Deploy a full k3 kube cluster, with 2 LB (ctrlplane and workers), and 2 servergroup (ctrlplane and workers)

- config-sample/config-kube-cluster.yml: terraform VPC config to start a full kube cluster
- cloud-init/: install script
  - cloud-init/config-script-docker.sh
  - cloud-init/config-script-k3s-agent.sh
  -	cloud-init/config-script-k3s-config.sh.tftpl
  -	cloud-init/config-script-k3s-master.sh
- terraform-k3s.tfvars.sample: variables
