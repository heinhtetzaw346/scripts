#!/usr/bin/env bash

# --- Configuration ---
# You can modify the target environments to filter for in this array.
# Endpoints / Environments to check:
TARGET_ENVIRONMENTS=("apim-gw-v4-ext" "new-nga-apigwc")

# Script directory so .env can be found regardless of the CWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables (username / password / base URL)
if [ -f "${SCRIPT_DIR}/.env" ]; then
    # Load and export envs to make them available to subshells / commands
    set -a
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/.env"
    set +a
else
    echo "Error: .env file not found at ${SCRIPT_DIR}/.env!" >&2
    exit 1
fi

# APIM Base URL (from .env, overridable via environment)
if [ -z "${APIM_BASE_URL}" ]; then
    read -p "Enter APIM Base URL [https://nonprod-apim.yomabank.org]: " INPUT_URL
    APIM_BASE_URL=${INPUT_URL:-https://nonprod-apim.yomabank.org}
fi

# Ensure required credentials are present
check_and_ask_credentials() {
    if [ -z "${APIM_USERNAME}" ]; then
        read -p "Enter APIM username: " APIM_USERNAME
    fi

    if [ -z "${APIM_PASSWORD}" ]; then
        read -s -p "Enter APIM password: " APIM_PASSWORD
        echo
    fi
}

check_and_ask_credentials

# Output CSV Path
OUTPUT_CSV="deployed_apis.csv"

PUBLISHER_API="${APIM_BASE_URL}/api/am/publisher/v3"

# Fetch a publisher REST API resource using username/password authentication.
# Uses HTTP Basic auth, retrying once with a fresh login session on 401/403.
publisher_api_get() {
    local PATH_AND_QUERY="$1"
    local RESPONSE HTTP_CODE BODY

    RESPONSE=$(curl -s -w "\n%{http_code}" "${PUBLISHER_API}${PATH_AND_QUERY}" \
        -u "${APIM_USERNAME}:${APIM_PASSWORD}" \
        -H "accept: application/json")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$ d')

    if [ "$HTTP_CODE" == "401" ] || [ "$HTTP_CODE" == "403" ]; then
        echo "Authorization failed (HTTP $HTTP_CODE). Re-checking credentials..." >&2
        APIM_USERNAME=""
        APIM_PASSWORD=""
        check_and_ask_credentials

        RESPONSE=$(curl -s -w "\n%{http_code}" "${PUBLISHER_API}${PATH_AND_QUERY}" \
            -u "${APIM_USERNAME}:${APIM_PASSWORD}" \
            -H "accept: application/json")
        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        BODY=$(echo "$RESPONSE" | sed '$ d')

        if [ "$HTTP_CODE" == "401" ] || [ "$HTTP_CODE" == "403" ]; then
            echo "Error: Authorization failed again (HTTP $HTTP_CODE)." >&2
            echo "$BODY" >&2
            return 1
        fi
    fi

    echo "$BODY"
}

echo "Fetching all APIs from ${APIM_BASE_URL}..."
# Fetch all APIs (handling default limit or retrieving all)
# Since there are 85 APIs, limit=100 is safe to fetch all of them.
APIS_JSON=$(publisher_api_get "/apis?limit=100")

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
    DEPLOYMENTS_JSON=$(publisher_api_get "/apis/${API_ID}/deployments")

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
