#!/usr/bin/env bash

#Get all prod namespaces
namespaces=($(kubectl get namespace --no-headers -o custom-columns=":metadata.name"))

for namespace in "${namespaces[@]}"; do
	echo "Getting non helm secrets for $namespace namespace."
	mkdir -p $namespace
	secrets=($(kubectl get secrets -n $namespace -o custom-columns=":.metadata.name,:.type" | grep -v "helm.sh" | awk '{ print $1 }'))
	for secret in "${secrets[@]}"; do
		kubectl get secret -n $namespace $secret -o yaml | kubectl neat > $namespace/$secret.yaml
	done
done
