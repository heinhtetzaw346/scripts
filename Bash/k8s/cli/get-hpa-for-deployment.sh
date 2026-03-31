#!/bin/bash

declare -a namespaces=($(kubectl get ns --no-headers -o custom-columns=":.metadata.name"))

for namespace in "${namespaces[@]}"; do 

    declare -a deployments=($(kubectl get deployments -n "$namespace" --no-headers -o custom-columns=":metadata.name"))

    for deployment in "${deployments[@]}"; do
        { kubectl get hpa -n "$namespace" "$deployment" > /dev/null 2>&1; } || echo "$namespace/$deployment"
    done
done
