#!/bin/bash

declare WHITE="\033[0m" #white
declare RED="\033[1;31m" #red
declare GREEN="\033[1;32m" #green
declare YELLOW="\033[1;33m" #yellow

log() {

	case "$1" in
		success)
			echo -e "$GREEN$2$WHITE"
			;;
		failure)
			echo -e "$RED$2$WHITE"
			;;
		progress)
			echo -e "$YELLOW$2$WHITE"
			;;
		normal)
			echo -e "$2"
			;;
	esac

}

validate_kubeconfig() {
	log progress "Confirming kubeconfig with user"
	if ! [ -z "$KUBECONFIG" ]; then
		kubeconfig="$KUBECONFIG"
	else
		kubeconfig="$HOME/.kube/config"
	fi
	read -r -p "Current kubeconfig file is at [ $kubeconfig ]. Please confirm [Y/n]: " CONFIRM
	CONFIRM="${CONFIRM:-Y}"
	
	case "$CONFIRM" in
		Y|y)
			log success "Kubeconfig confirmed. Continuing"
			;;
		N|n)
			log failure "Stopping the script."
			exit 0
			;;
		*)
			log failure "Invalid input. Stopping the script"
			exit 1
			;;
	esac
}

show_node_versions() {
	log normal "Here are the latest kindest/node versions"
	printf "=> docker.io/kindest/node:%s\n" "${LATEST_NODE_VERSIONS[@]}"
}

select_node_version() {
	log progress "Please select a node version to use"
	if command -v fzf > /dev/null; then
		SELECTED_NODE_VERSION=$(printf "%s\n" "${LATEST_NODE_VERSIONS[@]}" | fzf --reverse)
		log normal "Node version ${SELECTED_NODE_VERSION} selected"
	else
		COLUMNS=1
		select version in "${LATEST_NODE_VERSIONS[@]}"
		do
			SELECTED_NODE_VERSION=$version
			log normal "Node version ${SELECTED_NODE_VERSION} selected"
			break
		done
	fi
}

gather_options() {
	log normal "Please enter necessary configs"
	
	#cluster name
	read -r -p "Enter cluster name[kind]: " CLUSTER_NAME
	CLUSTER_NAME="${CLUSTER_NAME:-kind}"

	#node version
	select_node_version	

	#node count
	read -r -p "Enter the number of worker nodes[1]: " WORKER_NODE_COUNT
	WORKER_NODE_COUNT="${WORKER_NODE_COUNT:-1}"

	#pod network cidr
	read -r -p "Enter the pod network cidr[10.244.0.0/16]: " POD_SUBNET_CIDR
	POD_SUBNET_CIDR="${POD_SUBNET_CIDR:-10.244.0.0/16}"

	#service network cidr
	read -r -p "Enter the service network cidr[10.96.0.0/12]: " SERVICE_SUBNET_CIDR
	SERVICE_SUBNET_CIDR="${SERVICE_SUBNET_CIDR:-10.96.0.0/12}"

	#kube proxy mode
	read -r -p "Enter the kube-proxy mode [iptables]: " KUBE_PROXY_MODE	
	KUBE_PROXY_MODE="${KUBE_PROXY_MODE:-iptables}"

	#Disable default CNI?
	read -r -p "Disable default CNI?[false]: " DISABLE_DEFAULT_CNI
	DISABLE_DEFAULT_CNI="${DISABLE_DEFAULT_CNI:-false}"

	log success "Necessary options gathered as below: "
	printf "%s => %s\n" "CLUSTER_NAME" "${CLUSTER_NAME}"
	printf "%s => %s\n" "SELECTED_NODE_VERSION" "${SELECTED_NODE_VERSION}"
	printf "%s => %s\n" "WORKER_NODE_COUNT" "${WORKER_NODE_COUNT}"
	printf "%s => %s\n" "POD_SUBNET_CIDR" "${POD_SUBNET_CIDR}"
	printf "%s => %s\n" "SERVICE_SUBNET_CIDR" "${SERVICE_SUBNET_CIDR}"
	printf "%s => %s\n" "KUBE_PROXY_MODE" "${KUBE_PROXY_MODE}"
	printf "%s => %s\n" "DISABLE_DEFAULT_CNI" "${DISABLE_DEFAULT_CNI}"
	
}

generate_kind_config() {
	log progress "Generating kind config"
	TEMP_DIR=$(mktemp -d)
	CONFIG_FILE="${TEMP_DIR}/config.yaml"
cat << EOF >> $CONFIG_FILE
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
networking:
  kubeProxyMode: ${KUBE_PROXY_MODE}
  podSubnet: ${POD_SUBNET_CIDR}
  serviceSubnet: ${SERVICE_SUBNET_CIDR}
  disableDefaultCNI: ${DISABLE_DEFAULT_CNI}
nodes:
- role: control-plane
  image: kindest/node:${SELECTED_NODE_VERSION}
EOF
for ((i=1;i<=WORKER_NODE_COUNT;i++))
	do
		cat << EOF >> $CONFIG_FILE
- role: worker
  image: kindest/node:${SELECTED_NODE_VERSION}
EOF
	done
	log success "Kind config generated! You can find it at $CONFIG_FILE"
}

create_kind_cluster() {
	log progress "Creating kind cluster with the generated config"
	set -e
	kind create cluster --config ${CONFIG_FILE}
	set +e
	log success "Cluster created successfully"
}

main() {
	log progress "Fetching node versions from dockerhub"
	LATEST_NODE_VERSIONS=($(curl -s "https://hub.docker.com/v2/namespaces/kindest/repositories/node/tags?page_size=100" | jq -r '.results[].name' | sort -rV | awk -F. '{minor=$1"."$2; if (!seen[minor]++) print}'))

	case "$1" in show-node-versions)
			show_node_versions
			;;
		*)
			validate_kubeconfig
			gather_options
			generate_kind_config
			create_kind_cluster
			;;
	esac
}

main "$@"
