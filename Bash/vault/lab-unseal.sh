#!/usr/bin/env bash

source $HOME/.openbao-vault/lab-unseal-keys

VAULT_NS="vault-system"
VAULT_RN="openbao"

for key in "$KEY1" "$KEY2" "$KEY3"; do
	kubectl get pods -n ${VAULT_NS} ${VAULT_RN}-0 > /dev/null && kubectl exec -it -n ${VAULT_NS} ${VAULT_RN}-0 -- bao operator unseal ${key}
	kubectl get pods -n ${VAULT_NS} ${VAULT_RN}-1 > /dev/null && kubectl exec -it -n ${VAULT_NS} ${VAULT_RN}-1 -- bao operator unseal ${key}
	kubectl get pods -n ${VAULT_NS} ${VAULT_RN}-2 > /dev/null && kubectl exec -it -n ${VAULT_NS} ${VAULT_RN}-2 -- bao operator unseal ${key}
done
