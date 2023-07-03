# terraform-rancherlab
Terraform configuration for a local rancher cluster management lab

## Prerequisites
- docker
- [kind] (https://kind.sigs.k8s.io/) Tool to create local docker based kubernetes clusters
- helm 3
- kubectl
- terraform
- jq

## Install
Once all requistes installed and can be run by your local user.
Just do:
```
$ git clone https://github.com/framegrace/terraform-rancherlab.git
$ cd terraform-rancherlab/sample-lab
$ terraform init
$ terraform plan -out=lab.plan
$ terraform apply lab.plan
```
## Uninstall
```
$ cd terraform-rancherlab/sample-lab
$ terraform destroy
```
## Troubleshooting
- If destroy fails, just do:
```
# List all the clusters
$ kind get clusters
rancher
sample1
sample2
# Remove them
$ kind delete clusters rancher sample1 sample2
$ cd terraform-rancherlab/sample-lab
$ rm terraform.tfstate
```
