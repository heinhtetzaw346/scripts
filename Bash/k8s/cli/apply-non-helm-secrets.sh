#!/usr/bin/env bash

#for prod-namespaces
declare -a namespaces=($(kubectl get ns --no-headers -o custom-columns=":.metadata.name" | grep -ie 'prod'))
for namespace in "${namespaces[@]}"; do
	echo "Applying secrets for $namespace namespace"
	kubectl apply -f $namespace
done
