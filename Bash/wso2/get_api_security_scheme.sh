#!/usr/bin/env bash

# Make the APIM base URL a variable and inputable
if [ -n "$APIM_BASE_URL" ]; then
    echo "Using APIM_BASE_URL from environment: $APIM_BASE_URL"
else
    read -p "Enter APIM Base URL [https://nonprod-apim.yomabank.org]: " INPUT_URL
    APIM_BASE_URL=${INPUT_URL:-https://nonprod-apim.yomabank.org}
fi

# Load environment variables
if [ -f ".env.tokens" ]; then
    export $(grep -v '^#' .env.tokens | xargs)
fi

check_and_ask_tokens() {
    if [ -z "${AM_ACC_TOKEN_DEFAULT_P2}" ]; then
        read -p "Enter AM_ACC_TOKEN_DEFAULT_P2 (Cookie): " AM_ACC_TOKEN_DEFAULT_P2
    fi

    if [ -z "${WSO2_AM_TOKEN_1_Default}" ]; then
        read -p "Enter WSO2_AM_TOKEN_1_Default (Bearer Token): " WSO2_AM_TOKEN_1_Default
    fi
}

check_and_ask_tokens

fetch_apis() {
    curl -s -w "\n%{http_code}" "${APIM_BASE_URL}/api/am/publisher/v3/apis?limit=500" \
        -b "AM_ACC_TOKEN_DEFAULT_P2=${AM_ACC_TOKEN_DEFAULT_P2}" \
        -H "accept: application/json" \
        -H "authorization: Bearer ${WSO2_AM_TOKEN_1_Default}"
}

echo "Fetching all APIs from ${APIM_BASE_URL}. This may take a few moments..."
APIS_JSON=$(fetch_apis)
HTTP_CODE=$(echo "$APIS_JSON" | tail -n1)
BODY=$(echo "$APIS_JSON" | sed '$ d')

if [ "$HTTP_CODE" == "403" ] || [ "$HTTP_CODE" == "401" ]; then
    echo "Authorization failed (HTTP $HTTP_CODE). Tokens might be expired or invalid." >&2
    
    # Prompt for tokens again
    AM_ACC_TOKEN_DEFAULT_P2=""
    WSO2_AM_TOKEN_1_Default=""
    check_and_ask_tokens
    
    echo "Retrying..."
    APIS_JSON=$(fetch_apis)
    HTTP_CODE=$(echo "$APIS_JSON" | tail -n1)
    BODY=$(echo "$APIS_JSON" | sed '$ d')
    
    if [ "$HTTP_CODE" == "403" ] || [ "$HTTP_CODE" == "401" ]; then
        echo "Error: Authorization failed again. Exiting." >&2
        exit 1
    fi
fi

if ! echo "$BODY" | jq -e '.list' >/dev/null 2>&1; then
    echo "Error: Failed to fetch API list." >&2
    echo "$BODY" >&2
    exit 1
fi

read -p "Enter output CSV file name [api_security_schemes.csv]: " INPUT_CSV
OUTPUT_CSV=${INPUT_CSV:-api_security_schemes.csv}

# Generate CSV with headers
echo "No,API NAME,API Version,context path,security scheme (api_key; oauth2 or both),security off (yes; no),subscriptions" > "${OUTPUT_CSV}"

APIS=$(echo "$BODY" | jq -c '.list[]')
TOTAL_APIS=$(echo "$BODY" | jq '.list | length')
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
    API_CONTEXT=$(echo "$api" | jq -r '.context')

    echo "[$CURRENT/$TOTAL_APIS] Fetching details for: $API_NAME (v$API_VER)"

    API_DETAIL_JSON=$(curl -s "${APIM_BASE_URL}/api/am/publisher/v3/apis/${API_ID}" \
        -b "AM_ACC_TOKEN_DEFAULT_P2=${AM_ACC_TOKEN_DEFAULT_P2}" \
        -H "accept: application/json" \
        -H "authorization: Bearer ${WSO2_AM_TOKEN_1_Default}")

    SECURITY_SCHEMES=$(echo "$API_DETAIL_JSON" | jq -r '.securityScheme[]?' 2>/dev/null)
    
    HAS_API_KEY=false
    HAS_OAUTH2=false
    
    while IFS= read -r scheme; do
        if [ "$scheme" == "api_key" ]; then
            HAS_API_KEY=true
        elif [ "$scheme" == "oauth2" ]; then
            HAS_OAUTH2=true
        fi
    done <<< "$SECURITY_SCHEMES"

    if [ "$HAS_API_KEY" = true ] && [ "$HAS_OAUTH2" = true ]; then
        SCHEME_STR="both"
    elif [ "$HAS_API_KEY" = true ]; then
        SCHEME_STR="api_key"
    elif [ "$HAS_OAUTH2" = true ]; then
        SCHEME_STR="oauth2"
    else
        SCHEME_STR="none"
    fi

    SECURITY_OFF_CHECK=$(echo "$API_DETAIL_JSON" | jq -r '.operations[]?.authType' 2>/dev/null)
    SECURITY_OFF="yes"
    if [ -z "$SECURITY_OFF_CHECK" ]; then
        SECURITY_OFF="no"
    else
        while IFS= read -r auth; do
            if [ -n "$auth" ] && [ "$auth" != "None" ]; then
                SECURITY_OFF="no"
                break
            fi
        done <<< "$SECURITY_OFF_CHECK"
    fi

    SUBSCRIPTIONS_JSON=$(curl -s "${APIM_BASE_URL}/api/am/publisher/v3/subscriptions?apiId=${API_ID}&limit=2000&offset=0" \
        -b "AM_ACC_TOKEN_DEFAULT_P2=${AM_ACC_TOKEN_DEFAULT_P2}" \
        -H "accept: application/json" \
        -H "authorization: Bearer ${WSO2_AM_TOKEN_1_Default}")

    SUBS=$(echo "$SUBSCRIPTIONS_JSON" | jq -r '.list[]? | "\(.applicationInfo.name), \(.applicationInfo.subscriber)"' 2>/dev/null)

    echo "$CURRENT,\"$API_NAME\",\"$API_VER\",\"$API_CONTEXT\",\"$SCHEME_STR\",\"$SECURITY_OFF\",\"$SUBS\"" >> "${OUTPUT_CSV}"

done <<< "$APIS"

echo "----------------------------------------"
echo "Done! CSV report generated: ${OUTPUT_CSV}"
echo "----------------------------------------"
