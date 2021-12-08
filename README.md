# Overview 

This repository contains the source for the DFDS Crossplane configuration package. Using it will provide a 
set of composite cloud resources (AWS) with sane defaults defined.

# What is provided

## SQL Database Instance
Installs an AWS RDS Instance (currently postgres only) with a security group allowing public access into the 
default VPC.

# How to Use

## Prerequisites

The following are required in order to use the configuration package

- A Kubernetes cluster
- Crossplane installed through Helm
- An AWS account with an IAM key and secret that has sufficient permissions to deploy resources
- Crossplane CLI installed on local machine

## Installing Crossplane

```bash
kubectl create namespace crossplane-system
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update
helm install crossplane --namespace crossplane-system crossplane-stable/crossplane --version <version>
```

## Installing the Configuration Package

- Execute `docker pull dfdsdk/dfds-infra && kubectl crossplane install configuration dfdsdk/dfds-infra` to get the latest version, or use a release tag to install a specific version:

```bash
kubectl crossplane install configuration dfdsdk/dfds-infra <tag>
```

You can find the list of tags at <https://hub.docker.com/repository/docker/dfdsdk/dfds-infra>


## Upgrading the Configuration Package

- Execute `kubectl crossplane update configuration dfdsdk-dfds-infra [release-number]`

## Uninstalling the Configuration Package

- Execute `kubectl delete configuration.pkg dfdsdk-dfds-infra`

## Setting an AWS ProviderConfig

For each namespace in which you wish to provision resources you will need to install a ProviderConfig which follows the convention of 
namespace name suffixed with `-aws`. See `examples/awsproviderconfig.yaml` which installs a ProviderConfig for the namespace `my-namespace`, resulting in the ProviderConfig name of `my-namespace-aws`.

You will also need to generate a kubernetes secret containing your credentials that the ProviderConfig references. This can be done by placing credentials in a file, i.e `creds.conf` in the format:

```
[default]
aws_access_key_id = ACCESSKEYHERE
aws_secret_access_key = SECRETKEYHERE
```

And running the command `kubectl create secret generic aws-creds -n my-namespace --from-file=creds=./creds.conf`

## Setting a Kubernetes ProviderConfig

A single Kubernetes ProviderConfig will need to be installed in the Kubernetes cluster. See `examples/kubernetesproviderconfig.yaml`

## Provisioning a SQL Database

We use a dynamic claim to provision an RDS Postgres database instance. Running `kubectl apply -f examples/sqldatabases/claim-dynamic-nonproduction.yaml` will deploy a database with non-production defaults set.

To view the status of the install, execute `kubectl get claim` or `kubectl describe claim dynamic-claim-sql-nonprod-example` for more information. You should be able to view the raw RDS Instance using `kubectl get rdsinstance`.

Provisioning of a database can take up to 10 minutes.

## Modifying parameters on a SQL Database

You can update your manifest to change properties of the database. Try adding `storageSize: 30` to the parameters in the manifest and running an apply.

## Deleting a provisioned datbase

Simply run `kubectl delete -f examples/sqldatabases/claim-dynamic-nonproduction.yaml` to delete the deployed database or run `kubectl delete claim dynamic-claim-sql-nonprod-example`

# Development

## Folder structure

The folder structure of this repository is as follows:

- build
    - Contains pipelines and scripts used to build and publish the configuration package
- examples
    - Contains examples of ProviderConfig files and composite resources in the relevant subfolders
- package
    - Contains the composite resource definition manifest files in the relevant subfolders with the package 
    configuration at the top level

New resources should go into a sub-folder inside packages and an example of the resource should go into a sub-folder of the same name under examples.

## Building

There is a script at `build/build.sh` that you can provide parameter values for (docker repo name, tag) and execute in order to build and publish a version of this configuration package.

## Releases

Release images are created by pipeline whenever a new release is created in Github
