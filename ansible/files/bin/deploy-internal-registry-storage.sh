#!/bin/bash

# Clean up!!!
oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState": "Removed"}}'
oc delete pvc registry -n openshift-image-registry
oc delete pv registry

# Create!!!

nfs_server=$(dig +short +search bastion)

echo "Note: Using $nfs_server as the NFS Server."

echo "---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: registry
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteMany 
  nfs: 
    path: /exports/registry
    server: $nfs_server
  persistentVolumeReclaimPolicy: Retain" | oc create -f -

echo "---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: registry
spec:
  accessModes:
    - ReadWriteMany 
  resources:
    requests:
      storage: 100Gi" | oc -n openshift-image-registry create -f -

# Patch for managed and replicas=2
oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"pvc":{"claim":"registry"}}, "managementState": "Managed", "replicas": 2}}'
