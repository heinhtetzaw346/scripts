#!/usr/bin/env bash
#post-startup kubernetes cluster setup

#envars
CALICO_VERSION="${CALICO_VERSION:-v3.31.3}"
METALLB_VIP_RANGE=${METALLB_VIP_RANGE}

declare WHITE="\033[0m" #white
declare RED="\033[1;31m" #red
declare GREEN="\033[1;32m" #green
declare YELLOW="\033[1;33m" #yellow

declare temp_path="/tmp/cluster-setup"
declare help_message="------------------------------------------------------------
⚓ post-startup kubernetes setup script ⚓
Please provide --profile flag with the following values
🚀 full (calico, metrics-server, metallb, istio)
🚀 kind (metrics-server, metallb, istio)
🚀 minimal (metrics-server, metallb)"

declare available_options=("full" "minimal" "kind")

log() {
	case "$1" in
		success)
			echo -e "$GREEN✔️ $2$WHITE"
			;;
		failure)
			echo -e "$RED❌ $2$WHITE"
			;;
		progress)
			echo -e "$YELLOW🚀 $2$WHITE"
			;;
	esac
}

check_tools() {
	local -a tools=( "kubectl" "helm" "istioctl")
	log progress "Checking for tools in \$PATH"
	for tool in "${tools[@]}"; do
		if which "$tool" > /dev/null; then
			log success "$tool exists in \$PATH"
			return 0
		else
			log failure "$tool doesn't exist in \$PATH"
			exit 1
		fi
	done
}

check_context() {
	log progress "Checking for context"
	if kubectl config get-contexts | grep "*" > /dev/null; then
		log success "Kubectl context found. Using $(kubectl config get-contexts | grep '*' | awk -F ' ' '{ print $2 }')"
		return 0
	else
		log failure "No kubectl context found. Please select a context"
		exit 1
	fi
}

check_args() {
	case "$1" in
		--help)
			echo "$help_message"
			exit 0
			;;
		--profile)
			if ! [ -z ${2+true} ]; then
				found=0
				for option in "${available_options[@]}"; do
					[ "$2" = "$option" ] && found=1 && break
				done
				[ $found -eq 0 ] && log failure "Invalid option $2" && exit 1
				log success "Profile value exists. Using profile [$2]" && return 0
			else
				log failure "Please set a value for --profile flag"
				exit 1
			fi
			;;
		*)
			echo "$help_message"
			exit 0
			;;
	esac
}

label_nodes() {
	local -a nodes=($(kubectl get nodes --no-headers -o custom-columns="Name:.metadata.name,Label:.metadata.labels" | grep -vE "control-plane" | awk -F ' ' '{ print $1 }'))
	for node in "${nodes[@]}"; do
		if ! (kubectl get nodes $node -o custom-columns=":.metadata.labels" | grep "node-role" > /dev/null); then
			kubectl label nodes $node node-role.kubernetes.io/worker=
		else
			log success "Worker node $node is already labeled"		
		fi
	done
}

install_calico() {

	if (kubectl -n kube-system  rollout status deployments calico-kube-controllers > /dev/null 2>&1); then
		log success "Calico controller is ready"
		return 0
	fi

	log progress "Getting latest calico manifest to $temp_path/calico.yml"
	curl -fsS https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml --output $temp_path/calico.yml
	if [ "$?" -eq 0 ]; then
		log progress "Installing calico"
		kubectl apply -f $temp_path/calico.yml
		sleep 5
	else
		log failure "Getting calico manifest failed. Try again"
		exit 1
	fi

	log progress "Checking calico controller status"
	if ! (kubectl -n kube-system  rollout status deployments calico-kube-controllers ); then
		log failure "Calico controller is still not ready"
		exit 1
	else
		log success "Calico controller is ready"
		return 0
	fi
}

setup_networks() {
	if (kubectl get ippool --no-headers -o custom-columns=":.metadata.name" | grep -v "default" > /dev/null 2>&1); then
		log success "Ippools already created"
		return 0
	fi
	log progress "Generating ippool config to $temp_path/calico_ippools.yaml"
	local -a nodes=($(kubectl get nodes --no-headers -o custom-columns="Name:.metadata.name"))
	for node in "${nodes[@]}"; do
		if (kubectl get ippool --no-headers -o custom-columns=":.metadata.name" | grep "$node"); then
			log success "Ippool for $node is already set"
			continue
		fi
		current_cidr=$(kubectl get nodes $node --no-headers -o custom-columns=':.spec.podCIDRs[0]')
		IFS="/" read -ra cidr <<< "$current_cidr"
		blockSize="${cidr[1]}"
		cat <<EOF >> $temp_path/calico_ippools.yaml
apiVersion: crd.projectcalico.org/v1
kind: IPPool
metadata:
  name: $node-ippool
spec:
  allowedUses:
  - Workload
  - Tunnel
  cidr: ${current_cidr}
  blockSize: ${blockSize}
  ipipMode: Always
  natOutgoing: true
  nodeSelector: 'kubernetes.io/hostname == "$node"'
  vxlanMode: Never
---
EOF
	done
	log progress "Applying ippools"
	kubectl apply -f $temp_path/calico_ippools.yaml
	if [ "$?" -eq 0 ]; then
		log success "Ippools created"
		log progress "Deleting default ipv4 pool"
		kubectl delete ippool default-ipv4-ippool
		return 0
	else
		log failure "Ippool creation failed"
	fi
}

install_metrics() {
	if (kubectl -n kube-system rollout status deployments metrics-server > /dev/null 2>&1); then
		log success "Metrics server is ready"
		return 0
	fi
	log progress "Getting metrics-server helm repo"
	set -e; helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/; set +e
	set -e; helm upgrade --install metrics-server metrics-server/metrics-server --namespace kube-system --set "args={--kubelet-insecure-tls}"; set +e
#	log progress "Checking metrics server status"
#	if ! (kubectl -n kube-system rollout status deployments metrics-server); then
#		log failure "Metrics server is still not ready"
#		exit 1
#	else
#		log success "Metrics server is ready"
#		return 0
#	fi
}

install_metallb() {
	if (kubectl -n metallb-system rollout status deployments metallb-controller > /dev/null 2>&1); then
		log success "Metallb controller is ready"
		return 0
	fi
	set -e; helm repo add metallb https://metallb.github.io/metallb; set +e
	set -e; helm upgrade --install metallb metallb/metallb --set speaker.tolerateMaster=false --namespace metallb-system --create-namespace; set +e
	log progress "Checking metallb controller status"
	if ! (kubectl -n metallb-system rollout status deployments metallb-controller); then
		log failure "Metallb controller is still not ready"
		exit 1
	else
		log success "Metallb controller is ready"
		return 0
	fi
}

setup_metallb() {
	kubectl get ipaddresspools.metallb.io --no-headers -n metallb-system | grep pool > /dev/null 2>&1 && \
		kubectl get l2advertisements.metallb.io --no-headers -n metallb-system | grep pool > /dev/null 2>&1 && \
		log success "Metallb IPAddressPool and L2Advertisement already exists" && return 0

	if [ -z ${METALLB_VIP_RANGE+true} ]; then
		log progress "Using virtual IP range from \$METALLB_VIP_LIST"
	else
		log progress "Auto selecting virtual IP range from node IPs"
		IFS="." read -ra IP <<< $(kubectl get nodes --no-headers -o custom-columns="IP:.status.addresses[0].address" | head -n 1)
		METALLB_VIP_RANGE="${IP[0]}.${IP[1]}.${IP[2]}.200-${IP[0]}.${IP[1]}.${IP[2]}.250"
	fi
		log progress "Generating metallb manifests in $temp_path/metallb_ip_l2.yml"
	cat <<EOF > $temp_path/metallb_ip_l2.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - "${METALLB_VIP_RANGE}"
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-pool-l2a
  namespace: metallb-system
spec:
  ipAddressPools:
    - default-pool
EOF
	log progress "Applying metallb manifests"
	kubectl apply -f $temp_path/metallb_ip_l2.yaml -n metallb-system
	if [ "$?" -eq 0 ]; then
		log success "Metallb IPAddressPool and L2Advertisement created"
		return 0
	else
		log failure "Metallb IPAddressPool and L2Advertisement creation failed"
	fi
}

install_istio() {
	if (kubectl -n istio-system rollout status deployments istiod > /dev/null 2>&1); then
		log success "Istio control plane is ready"
		return 0
	fi
	log process "Installing istio with istioctl"
	set -e; istioctl install --namespace istio-system --set profile=default -y; set +e
}

cleanup() {
	if [ -d "$temp_path" ]; then
		log progress "Cleaning up the temp directory at $temp_path"
		set -e; rm -rf $temp_path; set +e
		log success "$temp_path deleted"
	fi
}

profile_full() {
	install_calico
	setup_networks
	install_metrics
	install_metallb
	setup_metallb
	install_istio
	cleanup
}

profile_minimal() {
	install_metrics
	install_metallb
	setup_metallb
	cleanup
}

profile_kind() {
	install_metrics
	install_metallb
	setup_metallb
	install_istio
	cleanup
}

main() {
	mkdir -p $temp_path
	check_args "$@"
	local option="$2"
	check_tools
	check_context
	label_nodes
	case "$option" in
		full)
			profile_full
			;;
		kind)
			profile_kind
			;;
		minimal)
			profile_minimal
			;;
		esac
	log success "Cluster-setup script exited"
}

main "$@"
