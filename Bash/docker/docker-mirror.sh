#!/usr/bin/env bash

[ -z "$1" ] && { echo "Available options [enable|disable|status]"; exit 1; }

case $1 in
	"enable")
		[ -f "$HOME/.docker/config.json" ] || { echo "Already enabled";  exit 1; }
		mv $HOME/.docker/config.json $HOME/.docker/config.json.dm
		echo "moved config.json to config.json.dm"
		exit 0
		;;
	"disable")
		[ -f "$HOME/.docker/config.json.dm" ] || { echo "Already disabled"; exit 1; }
		mv $HOME/.docker/config.json.dm $HOME/.docker/config.json
		echo "moved config.json.dm to config.json"
		exit 0
		;;
	"status")
		{ [ -f "$HOME/.docker/config.json.dm" ] && ! [ -f "$HOME/.docker/config.json" ]; } && { echo "docker mirror enabled"; exit 0; }
		echo "docker mirror disabled" 
		exit 0
		;;
	*)
		echo "Invalid option"
		exit 1
		;;
esac
