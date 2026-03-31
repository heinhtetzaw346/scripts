#!/usr/bin/env bash

read -p "Please enter the parent directory (where the namespace directories are located): " PARENT_DIR

read -p "Please enter the subdir values (aka the resource type to apply): " SUB_DIR

RESOURCE_DIR="${PARENT_DIR}/${SUB_DIR}"

[ -d "${RESOURCE_DIR}" ] || echo "Non-existent directory ${RESOURCE_DIR}"; exit 1;


