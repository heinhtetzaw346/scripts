#!/usr/bin/env bash

# --- Configuration ---
# APIM Base URL
APIM_BASE_URL="https://apim.yomabank.io"

# You can modify the target environments to filter for in this array.
# Endpoints / Environments to check:
TARGET_ENVIRONMENTS=("apim-gw-v4-ext" "new-nga-apigwc")

# Load environment variables
if [ -f ".env.tokens" ]; then
    # Load and export envs to make them available to subshells / commands
    export $(grep -v '^#' .env.tokens | xargs)
else
    echo "Error: .env.tokens file not found!" >&2
    exit 1
fi

# Ensure required tokens are present
if [ -z "${AM_ACC_TOKEN_DEFAULT_P2}" ] || [ -z "${WSO2_AM_TOKEN_1_Default}" ]; then
    echo "Error: Missing required tokens AM_ACC_TOKEN_DEFAULT_P2 or WSO2_AM_TOKEN_1_Default in .env.tokens" >&2
    exit 1
fi

# Output CSV Path
OUTPUT_CSV="deployed_apis.csv"

echo "Fetching all APIs from ${APIM_BASE_URL}..."
# Fetch all APIs (handling default limit or retrieving all)
# Since there are 85 APIs, limit=100 is safe to fetch all of them.
APIS_JSON=$(curl -s "${APIM_BASE_URL}/api/am/publisher/v3/apis?limit=100" \
    -b "AM_ACC_TOKEN_DEFAULT_P2=${AM_ACC_TOKEN_DEFAULT_P2}" \
    -H "accept: application/json" \
    -H "authorization: Bearer ${WSO2_AM_TOKEN_1_Default}")

# Check if we got valid JSON
if ! echo "${APIS_JSON}" | jq -e '.list' >/dev/null 2>&1; then
    echo "Error: Failed to fetch API list. Response:" >&2
    echo "${APIS_JSON}" >&2
    exit 1
fi

# Initialize CSV file with headers
echo "API Name,Version,Deployed Environments,External" > "${OUTPUT_CSV}"

# Helper function to check if an array contains a value
contains_element() {
    local e match="$1"
    shift
    for e; do
        [[ "$e" == "$match" ]] && return 0
    done
    return 1
}

# Extract list of APIs
APIS=$(echo "${APIS_JSON}" | jq -c '.list[]')
TOTAL_APIS=$(echo "${APIS_JSON}" | jq '.list | length')
CURRENT=0

echo "Processing ${TOTAL_APIS} APIs..."

while read -r api; do
    if [ -z "$api" ]; then
        continue
    fi
    ((CURRENT++))
    API_ID=$(echo "$api" | jq -r '.id')
    API_NAME=$(echo "$api" | jq -r '.name')
    API_VER=$(echo "$api" | jq -r '.version')

    echo "[$CURRENT/$TOTAL_APIS] Checking: $API_NAME (v$API_VER)"

    # Get deployments for the API
    DEPLOYMENTS_JSON=$(curl -s "${APIM_BASE_URL}/api/am/publisher/v3/apis/${API_ID}/deployments" \
        -b "AM_ACC_TOKEN_DEFAULT_P2=${AM_ACC_TOKEN_DEFAULT_P2}" \
        -H "accept: application/json" \
        -H "authorization: Bearer ${WSO2_AM_TOKEN_1_Default}")

    # Check for empty response or error
    if echo "$DEPLOYMENTS_JSON" | jq -e 'has("code")' >/dev/null 2>&1; then
        ERR_MSG=$(echo "$DEPLOYMENTS_JSON" | jq -r '.message')
        echo "  Error fetching deployments for $API_NAME: $ERR_MSG" >&2
        # Record with empty environments
        echo "\"$API_NAME\",\"$API_VER\",\"\",\"no\"" >> "${OUTPUT_CSV}"
        continue
    fi

    # Extract deployed environments
    DEPLOYED_ENVS=($(echo "$DEPLOYMENTS_JSON" | jq -r '.[] | .name' 2>/dev/null || true))

    # Format the deployed environments for the CSV (comma-separated list inside the cell)
    DEPLOYED_ENVS_STR=$(echo "$DEPLOYMENTS_JSON" | jq -r '[.[] | .name] | join(", ")' 2>/dev/null || echo "")

    # Check if any deployed environment matches the target array
    MATCH_FOUND="no"
    for env in "${DEPLOYED_ENVS[@]}"; do
        if contains_element "$env" "${TARGET_ENVIRONMENTS[@]}"; then
            MATCH_FOUND="yes"
            break
        fi
    done

    # Write record to CSV (quoting values to handle commas in fields safely)
    echo "\"$API_NAME\",\"$API_VER\",\"$DEPLOYED_ENVS_STR\",\"$MATCH_FOUND\"" >> "${OUTPUT_CSV}"

done <<< "$APIS"

echo "----------------------------------------"
echo "Done! CSV report generated: ${OUTPUT_CSV}"
echo "----------------------------------------"
