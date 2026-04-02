#!/usr/bin/env bash


set -e

declare TMP_DIR="/tmp/api-definitions"
mkdir -p "${TMP_DIR}"

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "--- WSO2 API Definition Comparator ---"

get_api_definition() {
    local ENV="$1"
    local API_NAME="$2"
    local API_VER="$3"

    echo "Checking $API_NAME:$API_VER in $ENV..." >&2


    apictl get envs --format "{{ jsonPretty . }}" | jq -e --arg e "$ENV" 'select(.Name == $e or .name == $e)' > /dev/null 2>&1 \
        || { echo "Error: Environment '$ENV' doesn't exist..." >&2; return 1; }



    local API_JSON
    API_JSON=$(apictl get apis -e "$ENV" -q "name:$API_NAME,version:$API_VER" --format "{{ jsonPretty . }}")
    
    echo "$API_JSON" | jq -e --arg n "$API_NAME" --arg v "$API_VER" 'select((.Name == $n or .name == $n) and (.Version == $v or .version == $v))' > /dev/null 2>&1 \
        || { echo "Error: API '$API_NAME' version '$API_VER' not found in $ENV" >&2; return 1; }

    local API_ZIP="${API_NAME}_${API_VER}.zip"
    local API_OUT_DIR="${TMP_DIR}/${API_NAME}-${API_VER}"
    

    apictl export api -e "$ENV" -n "$API_NAME" -v "$API_VER" --preserve-status > /dev/null

    local EXPORTED_FILE="$HOME/.wso2apictl/exported/apis/$ENV/$API_ZIP"
    
    if [ ! -f "$EXPORTED_FILE" ]; then
        echo "Error: Export failed. File not found at: $EXPORTED_FILE" >&2
        return 1
    fi

    unzip -o "$EXPORTED_FILE" -d "$TMP_DIR" > /dev/null

    echo "${API_OUT_DIR}/Definitions/swagger.yaml"
}

run_diff() {
    local S1="$1"
    local S2="$2"
    echo -e "\n>>> Comparing: Target vs Source\n"
    dyff between "$S1" "$S2"
}

interactive_mode() {
    while true; do
        echo -e "\n--- Target API (To Compare) ---"
        read -p "Environment: " E1
        read -p "API Name:    " N1
        read -p "Version:     " V1

        echo -e "\n--- Source API (Apply changes to target) ---"
        read -p "Environment: " E2
        read -p "API Name:    " N2
        read -p "Version:     " V2


        SWAGGER1=$(get_api_definition "$E1" "$N1" "$V1") || continue
        SWAGGER2=$(get_api_definition "$E2" "$N2" "$V2") || continue

        run_diff "$SWAGGER1" "$SWAGGER2"

        read -p "Compare another? (y/n): " CONT
        [[ "$CONT" != "y" ]] && break
    done
}

non_interactive_mode() {

    if [ "$#" -lt 6 ]; then
        echo "Usage: $0 --non-interactive <env1> <name1> <ver1> <env2> <name2> <ver2>"
        exit 1
    fi
    S1=$(get_api_definition "$1" "$2" "$3")
    S2=$(get_api_definition "$4" "$5" "$6")

    if [[ "$7" == "--output" && -n "$8" ]]; then
        OUTPUT_FILE="$8"
        echo "Saving diff output to: $OUTPUT_FILE"
        run_diff "$S1" "$S2" > "$OUTPUT_FILE"
    else    
    run_diff "$S1" "$S2"
    fi
}

if [[ "$1" == "--non-interactive" ]]; then
    shift
    non_interactive_mode "$@"
elif [[ "$1" == "--help" ]]; then
    echo "Usage: $0 --non-interactive <env1> <name1> <ver1> <env2> <name2> <ver2>"
    exit 0
else
    interactive_mode
fi
