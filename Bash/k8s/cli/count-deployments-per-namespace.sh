declare -a namespaces=($( kubectl get namespaces --no-headers -o custom-columns="Name:.metadata.name" | grep prod-))
for namespace in "${namespaces[@]}"; do
	
	deployments=$(kubectl get deployments -n $namespace --no-headers 2> /dev/null | grep prod-)
	if [[ -n "$deployments" ]]; then
		count=$(echo "$deployments" | wc -l)
	else
		count="0"
	fi
	printf 'Namespace: %s -> Count: %s\n' "$namespace" "$count"
done

