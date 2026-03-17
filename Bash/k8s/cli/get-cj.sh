#!/bin/bash

# 1. Fetch namespaces into an array safely
# Using grep -o matches just the pattern, or we use awk to grab the first column
namespaces=($(kubectl get ns --no-headers | awk '/prod-/ {print $1}'))

for namespace in "${namespaces[@]}"; do 
    # 2. Fetch CronJob names only (without the 'cronjob.batch/' prefix)
    # Using -o custom-columns keeps it clean for the output
    cronjobs=($(kubectl get cj -n "$namespace" --no-headers -o custom-columns=":metadata.name"))

    for cronjob in "${cronjobs[@]}"; do
        # 3. Fixed the variable name typo: "${cronjob[@]}" vs "${cronjobs[@]}"
        # Added -e to echo to ensure \t is interpreted as a tab
        echo -e "$namespace\t$cronjob"
    done
done
