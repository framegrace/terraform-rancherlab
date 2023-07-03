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
Once all requistes installed and your user can run normally all of them (Local user just needs permission to use docker):

Do:
```
$ git clone https://github.com/framegrace/terraform-rancherlab.git
$ cd terraform-rancherlab/sample-lab
$ terraform init
$ terraform plan -out=lab.plan
$ terraform apply lab.plan
...
...
Outputs:

rancher_url = "https://172.19.0.2.sslip.io/"
$
```
Point your browser to the hostname printed at the end to Go to rancher. (Default password is admin/administrator. You can change it on the code)
This sample creates a rancher cluster to host rancher, and a couple of sample clusters with 2 virtual nodes each.
Prometheus monitoring is enabled by default.

## Modifying
Just check the main.tf file on the sample project on how all works.  You can create your own projects.
The configuration is still sort of hardcoded, and more modules can be extracted. But is a good starting point to work with rancher.
This terraform creates a private CA and all certificates needed to import clusters.
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
