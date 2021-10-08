#!/bin/bash

# Authenticate with your docker repository

# Replace the following variables with your docker repo and desired tag
repo=dfdsdk/dfds-infra
tag=wicar

kubectl delete configuration.pkg dfdsdk-dfds-infra

cd ../package
rm -f *.xpkg
kubectl crossplane build configuration
kubectl crossplane push configuration $repo:$tag
kubectl crossplane install configuration $repo:$tag
