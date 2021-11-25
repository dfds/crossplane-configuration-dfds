# Overview

Contained here are RBAC compositions around individual AWS resources to allow for multi-tenancy. We call them 
'RBAC Wrappers'. We need these to implement generic AWS resources into our existing multi-tenancy RBAC setup

## DFDS Multi-Tenancy

### Cluster Level
At Cluster level, users are allowed to list namespaces and pods and not much else. This is defined in a ClusterRole which is 
assigned to a ReadOnly group, of which the cluster user is a member of by assuming their 'Capability' role.

### Namespace level
At Namespace level, users are allowed to perform a larger number of actions to create and view deployments, volumes etc etc. 
This is defined in a Role deployed in their namespace to which they are bound.

### The problem
As the Crossplane resource sit at Cluster level rather than Namespace level, teams need to be given permission to create AWS 
resources but only view and manage the individual resources they have created. To achieve this, we use our RBAC solution.

### The solution
Our solution is to have an rbac composite resource into which we can pass the resource type and API group, and also patch in the resource name. 
This will create a clusterrole and clusterrole binding, with access to modify the created resource restricted to the creating namespace's group.

```
                                   ___________________________________
                                   |                                  |
                                   | _______________________________  |
 _____________________             | |                              | |
|                     |  <---------|-|--           RBAC             | |               ___________________
|  ClusterRole        |            | |______________________________| |               |                  |
|  ClusterRoleBinding |            | ________________________________ |  <----------- |  Dynamic Claim   |
|_____________________|            | |                              | |               |__________________|
                                   | |         AWS Resource         | |
                                   | |______________________________| |
                                   |        Composite Resource        |
                                   |__________________________________|
```

## Creating an RBAC Wrapper

The process of creating an RBAC Wrapper for an AWS resource is as follows:

### Requirements

- The API of the resource to be wrapped must have reached at least v1beta1 to avoid potentially breaking changes from alpha versions

### Folder structure

The resource folder must sit in the package//aws folder. The folder name must match the AWS resource name. 
For example: `package/aws/bucket` for the `bucket` resource from provider-aws.

### Naming conventions

We use the following naming conventions in our RBAC Wrapper compositions.

#### Namespace

Our namespace must be [group].crossplane.dfds.cloud. [group] should be a generic descriptive category such as:

- storage
- networking
- compute
- messaging

#### XRD

Our Composite Resource Definitions should follow the naming of X[vendor-name][resource-name-defined-by-crossplane]. X stands for Composite. For example, if the resource is an AWS Bucket then the name of XAWSBucket. If the resource is an Azure Blob Storage Container then the name would be XAzureContainer. Apply the plural resource name where appropriate.

#### Claim

The claimNames for the resource should be the same as the XRD but with X omitted. Apply the plural resource name where appropriate.

### Create a definition.yaml

The file should be defined with the following section to define the name of the resources. We will use Bucket as 
our example:

```
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xawsbuckets.storage.crossplane.dfds.cloud
spec:
  defaultCompositionRef:
    name: awsbuckets.storage.crossplane.dfds.cloud
  group: storage.crossplane.dfds.cloud
  names:
    kind: XAWSBucket
    plural: xawsbuckets
  claimNames:
    kind: awsbucket
    plural: awsbuckets
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

We should then add properties of the resources under the third `properties:` we defined above. We can copy and paste 
these from the source code of the resource in aws-provider (using the desired release tag). For example, https://raw.githubusercontent.com/crossplane/provider-aws/master/package/crds/s3.aws.crossplane.io_buckets.yaml and copy the forProvider.properties. The full list of resource source code can be found here: https://github.com/crossplane/provider-aws/tree/master/package/crds (make sure to select the correct tag for our current version specified in 
`package/crossplane.yaml` from the github dropdown)

And make sure we end with making the required parameters from the raw resource required in our XRD:

```
                required:
                - locationConstraint
```

### Create a composition.yaml

The file should be composed with the following section to define the composition. We will continue to use bucket as our example:

```
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: xawsbuckets.storage.crossplane.dfds.cloud
  labels:
    provider: aws
spec:
  compositeTypeRef:
    apiVersion: storage.crossplane.dfds.cloud/v1alpha1
    kind: XAWSBucket
```

Next in the file, we should define our patchsets. One for the providerConfig which will automatically set the providerConfig reference to our convention of 
`[namespace]-[cloudprovider]`. I.e `default-aws` if the resource is deployed into the default namespace:

```
  patchSets:
  - name: configname
    patches:
    - fromFieldPath: spec.claimRef.namespace    
      toFieldPath: spec.providerConfigRef.name
      transforms:
      - type: string
        string:
          fmt: "%s-aws"
      policy:
        fromFieldPath: Required
```

We must then define our resource for depoyment. Firstly, our bucket resource and also our rbac resource, which is our solution to work with multi-tenancy. 


```
  resources:
  - name: bucket
    base:
      apiVersion: s3.aws.crossplane.io/v1beta1
      kind: Bucket
      spec:
        forProvider:
          locationConstraint: eu-west-1
    patches:
    - type: PatchSet
      patchSetName: configname   
    - fromFieldPath: spec.parameters
      toFieldPath: spec.forProvider
    - type: ToCompositeFieldPath
      fromFieldPath: "metadata.name"
      toFieldPath: "status.createdResources.bucket"     
```
Note that the patches apply our configname patchset from above. In addition, we patch the parameters defined in our definition.yaml through to this resource type by applying it to spec.forProvider. We also produce a status output that will show the raw resource name when you describe the XRD.

Finally, we need to define our rbac resource. We need to pass the appropriate values from our bucket resource into the `resourceTypes` and `apiGroups` attributes. Our resourceType is `buckets`, which is a plural version of the `kind` and the API group for it is `s3.aws.crossplane.io` which we can get from `apiVersion` of the bucket resource.

```
  - name: rbac
    base:
      apiVersion: crossplane.dfds.cloud/v1alpha1
      kind: XRBAC
      spec:
        resourceTypes: 
        - buckets
        apiGroups: 
        - s3.aws.crossplane.io
        providerConfigRef:
          name: kubernetes-provider       
    patches: 
    - fromFieldPath: metadata.name
      toFieldPath: spec.resourceName
    - fromFieldPath: spec.claimRef.namespace
      toFieldPath: spec.resourceNamespace
    - type: ToCompositeFieldPath
      fromFieldPath: status.createdResources
      toFieldPath: status.createdResources.rbac
      policy:
        fromFieldPath: Optional    
```

Note that our patches pass resource name and namespace values through from our claim to the XRBAC resource.

### Create an example

To test our composition, we should create an example(s) in the `examples\aws\[resource]` folder and provide the values we'd use to create the original resource. 
We should then try to deploy these and confirm that it behaves as expected.

