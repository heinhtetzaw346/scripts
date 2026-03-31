declare -a namespaces=($(kubectl get ns --no-headers -o custom-columns=":.metadata.name"))

for namespace in "${namespaces[@]}"; do
	declare -a cronjobs=($(kubectl get cj -n $namespace --no-headers -o custom-columns=":.metadata.name"))
	for cj in "${cronjobs[@]}"; do
		kubectl patch cj -n $namespace $cj --patch='{"spec": {"suspend": true}}'
	done
done
