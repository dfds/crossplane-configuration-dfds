#!/bin/bash

# Authenticate with your docker repository

# Replace the following variables with your docker repo and desired tag
repo=samdidfds/dfds-infra
tag=myversiontest-nobucket

cd ../package
rm -f *.xpkg
#kubectl delete configuration.pkg samdidfds-dfds-infra
kubectl crossplane build configuration
kubectl crossplane push configuration samdidfds/dfds-infra:myversiontest-nobucket
kubectl crossplane update configuration samdidfds-dfds-infra myversiontest-nobucket

#kubectl crossplane install configuration samdidfds/dfds-infra:myversiontest-nobucket