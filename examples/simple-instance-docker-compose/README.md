# single instance and docker-compose

## instance + docker-compose stack whoami

Deploy a single instance with a public IP and start a whoami docker-compose stack

- config-sample/config-simple-instance-docker-compose-whoami.yml: terraform VPC config to start an instance with a public IP
- assets/docker-compose.whoami.yml: the docker-compose stack launched on the instance
- terraform-docker-whoami.tfvars.sample: contains variables

## instance + docker-compose stack Kibana + Elastic cluster

Deploy a single instance with a public IP and start an elasticsearch cluster in a docker-compose stack (3 containers elasticsearch cluster + kibana + nginx with SSL enabled)

- config-sample/config-simple-instance-docker-compose-elastic.yml: terraform VPC config to start an instance with a public IP
- assets/docker-compose.elastic-cluster-ssl.yml: the docker-compose stack launched on the instance
- terraform-docker-elastic.tfvars.sample: contains variables used in docker-compose.elastic-cluster-ssl.yml, as elastic, kibana password, elastic version ...
