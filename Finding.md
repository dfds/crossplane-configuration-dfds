# System setup
Crossplane version 1.5 (TODO on sandbox)

# Managing migration of workloads
## Change of manifests for existing workloads 
Specify external name in the claim annotation. Does it work for all types of resourceS?
Search: external-name on slack
https://crossplane.slack.com/archives/CEG3T90A1/p1637606211218600?thread_ts=1637027271.059100&cid=CEG3T90A1

Taking over existing resource but not sure if it concile the behaviour

# API upgrades
## Set API version test and CompositionRevisions

Test XRD with Spec 
AWSRDSInstance v1alpha1 using AWS specific fields
AWSRDSInstance v1alpha2 using abstracted fields

Then migrate workloadsto bucket fields using external names 


Cannot delete v1 of claims. composite was deleted after settings referenacble to true. but claim deployment was not deleted
 Warning  DeleteCompositeResource     7m49s (x4 over 17m)  offered/compositeresourcedefinition.apiextensions.crossplane.io  Refusing to delete composite resource that is not bound to this claim

claim from v1 

# Policy mechanism


# Considerations
- Ensure support for importing existing resources for seamless migration of workloads using claims
- add 2 tags:
-- Managed by
-- Last sync time
- might end up using v2 of composite resources alternatively use of helm charts or kustomize will be needed



mark a revision as stable or latest or upgrade-safe to avoid claim having to specify reicison 



Currently Crossplane requires that all versions
  # have an identical schema, so this is mostly useful to 'promote' a type of XR
  # from alpha to beta to production ready ? 
https://crossplane.io/docs/v1.4/reference/composition.html



helm --namespace crossplane-system upgrade crossplane crossplane-stable/crossplane --version 1.4 --set args='{--enable-composition-revisions}'




# if this is not true => cannot delete resource in v1! How to upgrade existing resource to latest if possible?

    #1 New change to API result in bumping version in XRD and will result in composition changed to to use it
    # Create resources
    #2 Ensure existing resource work under the existing APIv1 (Need to preserve API + impementation)
    #3 Ensure APIv1 resources can be deleted from cluster when needed
    #4 Ensure new resources provisioned using new APIv2 (API+implementation)
    