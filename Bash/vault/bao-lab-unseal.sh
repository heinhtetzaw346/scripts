#!/usr/bin/env bash

KEYS_FILE="$HOME/.openbao-vault/lab-unseal-keys"

mapfile -t KEYS < "$KEYS_FILE"

VAULT_NS="vault-system"
VAULT_RN="openbao"

for i in {0..2}
do
    kubectl get pods -n "${VAULT_NS}" "${VAULT_RN}-$i" > /dev/null 2>&1 || { echo "${VAULT_RN}-$i pod doesn't exist yet"; }
    for key in "${KEYS[@]:0:3}"; do
        kubectl exec -i -n "${VAULT_NS}" "${VAULT_RN}-$i" -- bao operator unseal "${key}"
    done
    echo ""
    kubectl wait --for=condition=Ready -n ${VAULT_NS} pod/${VAULT_RN}-$i
    echo ""
    sleep 1
done

