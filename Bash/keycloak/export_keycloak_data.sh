#!/bin/bash

# Default configurations, can be overridden by first script argument
KEYCLOAK_URL=${1:-"https://auth.example.com"}
REALM=${REALM:-"master"}
CLIENT_ID=${CLIENT_ID:-"admin-cli"}

# Load environment variables (USERNAME and PASSWORD)
if [ -f .env ]; then
  source .env
fi

# Check if required credentials are set
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  echo "Error: USERNAME and PASSWORD must be set in .env"
  exit 1
fi

echo "Fetching admin token from ${KEYCLOAK_URL} for realm '${REALM}'..."
TOKEN_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${USERNAME}" \
  -d "password=${PASSWORD}" \
  -d "grant_type=password" \
  -d "client_id=${CLIENT_ID}")

# Extract the access token using jq
TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
  echo "Failed to obtain token. Response from Keycloak:"
  echo "$TOKEN_RESPONSE"
  exit 1
fi
echo "Token obtained successfully."

# 1. Fetching Users
echo "Fetching users list..."
USERS_JSON=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/users" \
  -H "Authorization: Bearer $TOKEN")

echo "Saving users to users.csv..."
# Extract relevant fields and format as CSV
echo "$USERS_JSON" | jq -r '
  ["id", "username", "email", "firstName", "lastName", "enabled"], 
  (.[]? | [.id, .username, .email, .firstName, .lastName, .enabled]) | @csv
' > users.csv
echo "users.csv created."

# 2. Fetching Events
echo "Fetching events list..."
EVENTS_JSON=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/events" \
  -H "Authorization: Bearer $TOKEN")

echo "Saving events to events.csv..."
# Extract relevant fields and format as CSV
echo "$EVENTS_JSON" | jq -r '
  ["time", "type", "realmId", "clientId", "userId", "ipAddress", "error"], 
  (.[]? | [.time, .type, .realmId, .clientId, .userId, .ipAddress, .error]) | @csv
' > events.csv
echo "events.csv created."

echo "Data extraction complete!"
