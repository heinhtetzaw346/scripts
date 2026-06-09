#!/bin/bash

declare -a CLUSTERS=($(kind get clusters))

log() {
	echo "[$(date +%D\ %H:%M:%S\ %Z)] -- $@"
}

for CLUSTER in "${CLUSTERS[@]}"; do
	log "Stopping $CLUSTER"
	$HOME/.local/bin/kind-ctl stop $CLUSTER
	if ! [ "$?" -eq 0 ]; then
		log "Failed to stop $CLUSTER"
		exit 1
	fi
done

log "Exiting script with success..."
