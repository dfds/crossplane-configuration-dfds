# crossplane-configuration-dfds
DFDS Crossplane configuration package source definitions

```
cd databases
kubectl crossplane build configuration
kubectl crossplane push configuration dfdsdk/dfds-infra:v0.0.1-alpha.0
kubectl crossplane install configuration dfdsdk/dfds-infra:v0.0.1-alpha.0
```