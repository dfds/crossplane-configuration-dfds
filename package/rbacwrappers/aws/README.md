# Overview

Contained here are RBAC compositions around individual AWS resources to allow for multi-tenancy. We call them 
'RBAC Wrappers'

## Creating an RBAC Wrapper

The process of creating an RBAC Wrapper is as follows:

### Requirements

- The API of the resource to be wrapped must have reached v1beta1

### Folder structure

The resource folder must sit in the package/rbacwrappers/aws folder. The folder name must match the AWS resource name. 
For example: `package/rbacwrappers/aws/bucket` for the `bucket` resource from provider-aws.

### Create a definition.yaml

The file should be composed with the following section to define the name of the resources. We will use dfdsawsbucket as 
our example:

```
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: compositedfdsawsbuckets.crossplane.dfds.cloud
spec:
  defaultCompositionRef:
    name: dfdsawsbuckets.crossplane.dfds.cloud
  group: crossplane.dfds.cloud
  names:
    kind: CompositeDFDSAWSBucket
    plural: compositedfdsawsbuckets
  claimNames:
    kind: DFDSAWSBucket
    plural: dfdsawsbuckets
```

Next in the file, we should declare a version for our resource and lay out the schema:

```
versions: 
  - name: v1alpha1
    served: true
    referenceable: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              parameters:
                type: object
                properties:
```

We should then add properties of the resources under `properties:` we defined above. We can copy and paste 
these from the source code of the resource in aws-provider (using the correct tag). For example, `https://github.com/crossplane/provider-aws/blob/v0.19.1/package/crds/s3.aws.crossplane.io_buckets.yaml` and copy the forProvider.properties