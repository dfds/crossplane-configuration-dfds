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

The resource folder must sit in the package//aws folder. The folder name must match the AWS resource name and a sub-folder must exist 
inside this per version in `v#` format.
For example: `package/aws/bucket/v1` for `v1` of the `bucket` resource from provider-aws.

### Versioning

To workaround issues with upgrades, our versioning strategy is to reflect the version in the resource name. This allows different versions of the same 
type of resource to exist together as they are essentially different resources. For example, `XAWSBucketV1`, `XAWSBucketV2`. This is explained under the XRD naming conventions below.

### Naming conventions

We use the following naming conventions in our RBAC Wrapper compositions.

#### Namespace

Our namespace must be [group].xplane.dfds.cloud. [group] should be a generic descriptive category such as:

- storage
- networking
- compute
- messaging

#### XRD

Our Composite Resource Definitions should follow the naming of X[vendor-name][resource-name-defined-by-crossplane]V[iteration]. X stands for Composite. For example, if the resource is an AWS Bucket and it is our first iteration then give it the name of XAWSBucketV1. If the resource is an Azure Blob Storage Container and is our second iteration then the name would be XAzureContainerV2. Apply the plural resource name where appropriate.

#### Claim

The claimNames for the resource should be the same as the XRD but with X omitted. Apply the plural resource name where appropriate.

### Create a definition.yaml

The file should be defined with the following section to define the name of the resources. We will use Bucket as
our example:

```
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xawsbucketv1s.storage.xplane.dfds.cloud
spec:
  defaultCompositionRef:
    name: awsbucketv1s.storage.xplane.dfds.cloud
  group: storage.xplane.dfds.cloud
  names:
    kind: XAWSBucketV1
    plural: xawsbucketv1s
  claimNames:
    kind: AWSBucketV1
    plural: awsbucketv1s
```

Next in the file, we should declare a version for our resource and lay out the schema:

```
  versions:
  - name: v1alpha1
    served: true
    referenceable: true
    additionalPrinterColumns:
    - name: Synced
      type: string
      jsonPath: .status.instanceConditions[?(@.type=='Synced')].status    
    - name: Last Change
      type: string
      jsonPath: .status.instanceConditions[?(@.type=='Synced')].lastTransitionTime    
    schema:
      openAPIV3Schema:
        type: object
        properties:
          status:
            type: object
            properties:
              createdResources:
                description: list of resources created for this claim
                type: object
                properties:
                  bucket:
                    description: Name of the provisioned bucket
                    type: string
                  rbac:
                    description: list of the provisioned RBAC resources
                    type: object
                    x-kubernetes-preserve-unknown-fields: true
              instanceConditions:
                description: >
                  Information about the managed resource condition, e.g. reconcile errors due to bad parameters
                type: array
                items:
                  type: object
                  x-kubernetes-preserve-unknown-fields: true                     
          spec:
            type: object
            parameters:
              parameters:
                type: object
                properties:
```

We should then add properties of the resources under `schema.openAPIV3Schema.spec.parameters.parameters.properties:` we defined above. We can copy and paste
these from the source code of the resource in aws-provider (using the desired release tag). For example, https://raw.githubusercontent.com/crossplane/provider-aws/master/package/crds/s3.aws.crossplane.io_buckets.yaml and copy the forProvider.properties. The full list of resource source code can be found here: https://github.com/crossplane/provider-aws/tree/master/package/crds (make sure to select the correct tag for our current version specified in
`package/crossplane.yaml` from the github dropdown)

And make sure we end with making the required parameters from the raw resource required in our XRD, as in this example:

```
                required:
                - locationConstraint
```
In addition to the resource specific properties, we add deletionPolicy property to enable consumer to determine what will happen with the provisioned resource in case of deletion of the managed resource in kubernetes:

```
deletionPolicy: 
  description: Specify whether the actual cloud resource should be deleted when this managed resource is deleted in Kubernetes API server. Possible values are Delete (the default) and Orphan
  type: string
  default: "Delete" 
```
*Note:* The additionalPrinterColumns section allows adding custom columns with additional information available for the user on `kubectl get` requests 

In the status field under `schema.openAPIV3Schema.spec` we add custom fields to view additional information about the created resources when user do `kubectl describe` on the claim resource. The custom field `instanceConditions` keeps reconcile information that is copied from the managed resource. It's also used as a data source for the additionalPrinterColumns fields.

### Create a composition.yaml

The file should be composed with the following section to define the composition. We will continue to use bucket as our example:

```
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: xawsbucketv1s.storage.xplane.dfds.cloud
  labels:
    provider: aws
spec:
  compositeTypeRef:
    apiVersion: storage.xplane.dfds.cloud/v1alpha1
    kind: XAWSBucketV1
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
    - type: FromCompositeFieldPath
      fromFieldPath: "metadata.annotations[crossplane.io/external-name]"
    - fromFieldPath: spec.parameters.deletionPolicy
      toFieldPath: spec.deletionPolicy
    - type: ToCompositeFieldPath
      fromFieldPath: status.conditions
      toFieldPath: status.instanceConditions
      policy:
        fromFieldPath: Optional         
```
Note that the patches apply our configname patchset from above. In addition, we patch the parameters defined in our definition.yaml through to this resource type by applying it to spec.forProvider. We also produce a status output that will show the raw resource name when you describe the XRD.
One more important thing to notice about metada annotation mapping is that we are enabling reading external name from claims using metadata.annotation property like in the following example claim:
```
apiVersion: storage.xplane.dfds.cloud/v1alpha1
kind: AWSBucketV1
metadata:
  name: awsbucketdfds
  namespace: my-namespace
  annotations:
    crossplane.io/external-name: my-existing-bucket-name-on-aws
spec:
  parameters:
    locationConstraint: eu-west-1
    acl: public-read
```
This enables users to import resources into Crossplane to start managing them using kubernetes.
While this can be the way for attaching existing resources, the following deletionPolicy patch with the value Orphan that can be passed in the claim will "detach" a resource from kubernetes in case of the claim have been deleted. So this will basically keep resources on AWS if there is a need for it.

The last patch field mapping will copy status information from the managed resource and them available in the composite resource and the claim under a new field called instance conditions. It will also allow additionalPrinterCol
 
Finally, we need to define our rbac resource. We need to pass the appropriate values from our bucket resource into the `resourceTypes` and `apiGroups` attributes. Our resourceType is `buckets`, which is a plural version of the `kind` and the API group for it is `s3.aws.crossplane.io` which we can get from `apiVersion` of the bucket resource.

```
  - name: rbac
    base:
      apiVersion: xplane.dfds.cloud/v1alpha1
      kind: XRBACV1
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

To test our composition, we should create an example(s) in the `examples\aws\[resource]\v[#]` folder and provide the values we'd use to create the original resource.
We should then try to deploy these and confirm that it behaves as expected.

