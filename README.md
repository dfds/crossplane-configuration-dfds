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

### Using a Credentials file

You will need to generate a kubernetes secret containing your credentials that the ProviderConfig references. This can be done by placing credentials in a file, i.e `creds.conf` in the format:

```
[default]
aws_access_key_id = ACCESSKEYHERE
aws_secret_access_key = SECRETKEYHERE
```

And running the command `kubectl create secret generic aws-creds -n my-namespace --from-file=creds=./creds.conf`

### Using IAM role assumption in EKS

Set environment variables to use with commands below
```
export AWS_REGION=region-here
export CLUSTER_NAME=clustername
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
export IAM_ROLE_NAME=name-to-give-iam-role
SERVICE_ACCOUNT_NAMESPACE=namespace-ie-crossplane-system-or-upbound-system
```

The first requirement is that you enable IAM roles for service accounts in your cluster by [Creating an IAM OIDC provider for your cluster](https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html)

```
eksctl utils associate-iam-oidc-provider --cluster "${CLUSTER_NAME}" --region "${AWS_REGION}" --approve
```

Our next step is to install Crossplane

```
kubectl create namespace $SERVICE_ACCOUNT_NAMESPACE
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm install crossplane --namespace $SERVICE_ACCOUNT_NAMESPACE crossplane-stable/crossplane
```

Then install the AWS provider referencing a ControllerConfig containing an annotation

```
cat > provider.yaml <<EOF
apiVersion: pkg.crossplane.io/v1alpha1
kind: ControllerConfig
metadata:
  name: aws-config
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::$AWS_ACCOUNT_ID:role/$IAM_ROLE_NAME
spec:
  podSecurityContext:
    fsGroup: 2000
---
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws
spec:
  package: crossplane/provider-aws:v0.22.0
  controllerConfigRef:
    name: aws-config
EOF

kubectl apply -f provider.yaml
```

Then we need to create an IAM role for our service account in our EKS cluster's AWS account

```
kubectl get serviceaccounts -n $SERVICE_ACCOUNT_NAMESPACE
SERVICE_ACCOUNT_NAME=provider-aws-[id from aws service account name here]
```

Option 1: Using EKSCTL
```
#eksctl create iamserviceaccount --cluster "${CLUSTER_NAME}" --region "${AWS_REGION}" --name="$SERVICE_ACCOUNT_NAME" --namespace="$SERVICE_ACCOUNT_NAMESPACE" --role-name="$IAM_ROLE_NAME" --role-only --attach-policy-arn="arn:aws:iam::aws:policy/AdministratorAccess" --approve --override-existing-serviceaccounts
```

> Note: Using EKSCTL will use StringEquals in the Trust Relationship and use the exact name of the aws-provider service account. This would mean it needs 
editing with each upgrade of the AWS provider so it is preferrable to use the AWS CLI method below instead

Option 2: Using AWS CLI
```
read -r -d '' TRUST_RELATIONSHIP <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
	"StringLike": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${SERVICE_ACCOUNT_NAMESPACE}:provider-aws-*"
        }
      }
    }
  ]
}
EOF
echo "${TRUST_RELATIONSHIP}" > trust.json

aws iam create-role --role-name "${IAM_ROLE_NAME}" --assume-role-policy-document file://trust.json --description "IAM role for provider-aws"

aws iam attach-role-policy --role-name "${IAM_ROLE_NAME}" --policy-arn=arn:aws:iam::aws:policy/AdministratorAccess
```

Then create a ProviderConfig to provision resources in our account

```
cat > provider-config.yaml <<EOF
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: aws-provider
spec:
  assumeRoleARN: "arn:aws:iam::$AWS_ACCOUNT_ID:role/$IAM_ROLE_NAME"
  credentials:
    source: InjectedIdentity
EOF

kubectl apply -f provider-config.yaml
```

To deploy resources into another AWS account, we need to do the following:

Create a role that trusts the role from our EKS AWS account:

```
MY_OTHER_AWS_ACCOUNT_IAM_ROLE_NAME=provider-aws
MY_OTHER_AWS_ACCOUNT_ID=111111111
```

```
read -r -d '' TRUST_RELATIONSHIP_OTHER_AWS_ACCOUNT <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$AWS_ACCOUNT_ID:role/$IAM_ROLE_NAME"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
echo "${TRUST_RELATIONSHIP_OTHER_AWS_ACCOUNT}" > trust_other.json

aws iam create-role --role-name "${MY_OTHER_AWS_ACCOUNT_IAM_ROLE_NAME}" --assume-role-policy-document file://trust_other.json --description "IAM role for $IAM_ROLE_NAME in $AWS_ACCOUNT_ID"
```

Attach AdministratorAccess permissions to the role:

```
aws iam attach-role-policy --role-name "${MY_OTHER_AWS_ACCOUNT_IAM_ROLE_NAME}" --policy-arn=arn:aws:iam::aws:policy/AdministratorAccess
```

Create a new providerconfig set to assume that role. i.e:

```
cat > provider-config-other.yaml <<EOF
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: aws-provider-$MY_OTHER_AWS_ACCOUNT_ID
spec:
  assumeRoleARN: "arn:aws:iam::$MY_OTHER_AWS_ACCOUNT_ID:role/$MY_OTHER_AWS_ACCOUNT_IAM_ROLE_NAME"
  credentials:
    source: InjectedIdentity
EOF

kubectl apply -f provider-config-other.yaml
```

When creating a resource for this capability, reference this providerconfig. i.e:

```
apiVersion: efs.aws.crossplane.io/v1alpha1
kind: FileSystem
metadata:
  name: remote-efs-example
spec:
  forProvider:
    region: eu-west-1
  providerConfigRef:
    name: aws-provider-$MY_OTHER_AWS_ACCOUNT_ID
```

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
    - Contains the composite resource definition manifest files in the relevant versioned subfolders (I.e package\containerregistries\v1) 
      with the package configuration at the top level
- package\aws
    - Contains RBAC composites of AWS resources to work in multi-tenancy cluster. See the README in this folder


New resources should go into a versioned sub-folder inside packages and an example of the resource should go into a sub-folder of the same name under examples.

## Building

There is a script at `build/build.sh` that you can provide parameter values for (docker repo name, tag) and execute in order to build and publish a version of this configuration package.

## Releases

Release images are created by pipeline whenever a new release is created in Github
