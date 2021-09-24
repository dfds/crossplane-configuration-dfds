#!/bin/bash
cd ../package
rm *.xpkg
kubectl crossplane build configuration
kubectl crossplane push configuration dfdsdk/dfds-infra:rifis
kubectl crossplane install configuration dfdsdk/dfds-infra:rifis