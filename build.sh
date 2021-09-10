#!/bin/bash
buid_number=demo-after

rm -rf databases/dfds-infra-*.xpkg
kubectl crossplane build configuration -f databases
kubectl crossplane push configuration -f databases/dfds-infra-*.xpkg dfdsdk/dfds-infra:$buid_number
#kubectl crossplane install configuration dfdsdk/dfds-infra:$buid_number

# kubectl crossplane update configuration dfdsdk-dfds-infra $buid_number
