#!/bin/bash
buid_number=v0.0.1-alpha.3

cd databases
rm -rf dfds-infra-*
kubectl crossplane build configuration
kubectl crossplane push configuration dfdsdk/dfds-infra:$buid_number
#kubectl crossplane install configuration dfdsdk/dfds-infra:$buid_number

kubectl crossplane update configuration dfdsdk-dfds-infra $buid_number

cd ..