# Overview

Contained here are RBAC compositions around individual AWS resources to allow for multi-tenancy. We call them 
'RBAC Wrappers'

## Creating an RBAC Wrapper

The process of creating an RBAC Wrapper is as follows:

### Requirements

- The API of the resource to be wrapped must have reached at least v1beta1 to avoid potentially breaking changes from alpha versions

### Folder structure

The resource folder must sit in the package/rbacwrappers/aws folder. The folder name must match the AWS resource name. 
For example: `package/rbacwrappers/aws/bucket` for the `bucket` resource from provider-aws.

### Create a definition.yaml

The file should be defined with the following section to define the name of the resources. We will use dfdsawsbucket as 
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
these from the source code of the resource in aws-provider (using the desired release tag). For example, `https://github.com/crossplane/provider-aws/blob/v0.19.1/package/crds/s3.aws.crossplane.io_buckets.yaml` and copy the forProvider.properties


### Create a composition.yaml

The file should be composed with the following section to define the composition. We will use dfdsawsbuckets as our example:

```
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: compositedfdsawsbuckets.crossplane.dfds.cloud
  labels:
    provider: aws
spec:
  compositeTypeRef:
    apiVersion: crossplane.dfds.cloud/v1alpha1
    kind: CompositeDFDSAWSBucket
```

Next in the file, we should define our patchsets. One for object-metadata which will fill in a name and labels from the supplied metadata when we deploy a resource and 
reference the patchset from it. Also, one for the providerConfig which will automatically set the providerConfig reference to our convention of 
`[namespace]-[cloudprovider]`. I.e `default-aws` if the resource is deployed into the default namespace:

```
  patchSets:
  - name: object-metadata
    patches:
    - fromFieldPath: metadata.name
      toFieldPath: spec.forProvider.manifest.metadata.name    
      policy:
        fromFieldPath: Required       
    - fromFieldPath: metadata.labels
      toFieldPath: spec.forProvider.manifest.metadata.labels
      policy:
        fromFieldPath: Required
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

We must then define our resources and any patches that apply to them. Firstly, our RBAC clusterrole and clusterrolebinding which allows for 
appropriate multi-tenancy in our cluster. Change the rules as appropriate for the resource we are deploying. Here we are using the s3bucket as an example: 

```
resources:
  - name: role
    base:
      apiVersion: kubernetes.crossplane.io/v1alpha1
      kind: Object
      spec:
        forProvider:
          manifest:
            apiVersion: rbac.authorization.k8s.io/v1
            kind: ClusterRole
            metadata:
              name: deployed-using-crossplane
              labels:
                managed-by: "crossplane"
            rules:
            - apiGroups: ["s3.aws.crossplane.io"]
              resources: ["buckets"]
              resourceNames: [ ]
              verbs: ["get"]           
        providerConfigRef:
          name: kubernetes-provider        
    patches:
    - type: PatchSet
      patchSetName: object-metadata
    - fromFieldPath: metadata.name
      toFieldPath: spec.forProvider.manifest.rules[0].resourceNames[0]
    - type: ToCompositeFieldPath
      fromFieldPath: "metadata.name"
      toFieldPath: "status.createdResources.clusterrole" 

  - name: rolebinding
    base:
      apiVersion: kubernetes.crossplane.io/v1alpha1
      kind: Object
      spec:
        forProvider:
          manifest:
            apiVersion: rbac.authorization.k8s.io/v1
            kind: ClusterRoleBinding
            metadata:
              name: placeholder
            roleRef:
              apiGroup: rbac.authorization.k8s.io
              kind: ClusterRole
              name: roleref
            subjects:
            - apiGroup: rbac.authorization.k8s.io
              kind: Group
              name: placeholder
        providerConfigRef:
          name: kubernetes-provider
    patches:
    - type: PatchSet
      patchSetName: object-metadata    
    - fromFieldPath: metadata.name
      toFieldPath: spec.forProvider.manifest.roleRef.name
    - fromFieldPath: spec.claimRef.namespace
      toFieldPath: spec.forProvider.manifest.subjects[0].name
    - type: ToCompositeFieldPath
      fromFieldPath: "metadata.name"
      toFieldPath: "status.createdResources.clusterrolebinding"
```

Finally, we need our actual wrapped resource itself and apply the configname patchset and also a patch for all parameters from the definition 
to the forProvider fields. In this case, our resource is a Bucket:

```
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
```