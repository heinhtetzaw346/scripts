#!/usr/bin/env bash

set -e

# --- Configuration ---
declare TMP_DIR="/tmp/api-definitions"
declare BACKUP_DIR="./backups"

mkdir -p "${TMP_DIR}"
mkdir -p "${BACKUP_DIR}"

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "--- WSO2 API Backup Tool ---"

# --- Input Collection ---
read -p "Environment: " ENV
read -p "API Name:    " API_NAME
read -p "Version:     " API_VER

echo -e "\nProcessing $API_NAME:$API_VER in $ENV..."

# 1. Verify Environment
apictl get envs --format "{{ jsonPretty . }}" | jq -e --arg e "$ENV" 'select(.Name == $e or .name == $e)' > /dev/null 2>&1 \
    || { echo "Error: Environment '$ENV' not found." >&2; exit 1; }

# 2. Verify API Existence
API_JSON=$(apictl get apis -e "$ENV" -q "name:$API_NAME,version:$API_VER" --format "{{ jsonPretty . }}")
echo "$API_JSON" | jq -e --arg n "$API_NAME" --arg v "$API_VER" 'select((.Name == $n or .name == $n) and (.Version == $v or .version == $v))' > /dev/null 2>&1 \
    || { echo "Error: API '$API_NAME' version '$API_VER' not found in $ENV." >&2; exit 1; }

# 3. Export API Bundle
apictl export api -e "$ENV" -n "$API_NAME" -v "$API_VER" --preserve-status > /dev/null

API_ZIP="${API_NAME}_${API_VER}.zip"
EXPORTED_FILE="$HOME/.wso2apictl/exported/apis/$ENV/$API_ZIP"

if [ ! -f "$EXPORTED_FILE" ]; then
    echo "Error: Export failed. File not found at: $EXPORTED_FILE" >&2
    exit 1
fi

# 4. Extract and Save Backup
UNZIP_DEST="${TMP_DIR}/${API_NAME}_${API_VER}"
mkdir -p "$UNZIP_DEST"
unzip -o "$EXPORTED_FILE" -d "$UNZIP_DEST" > /dev/null

BACKUP_FILE="${BACKUP_DIR}/${API_NAME}-${API_VER}.yaml"
SOURCE_SWAGGER=$(find "$UNZIP_DEST" -name "swagger.yaml")

if [ -n "$SOURCE_SWAGGER" ]; then
    cp "$SOURCE_SWAGGER" "$BACKUP_FILE"
    echo "------------------------------------------------"
    echo "SUCCESS: API definition backed up to:"
    echo "$BACKUP_FILE"
    echo "------------------------------------------------"
else
    echo "Error: Could not find swagger.yaml in the exported bundle." >&2
    exit 1
fi
