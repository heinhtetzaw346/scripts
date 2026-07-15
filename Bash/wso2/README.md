# WSO2 API Utilities

This repository contains a collection of bash scripts designed to automate, inspect, and manage APIs within a WSO2 API Manager ecosystem.

---

## Available Scripts

### 1. `get_api_security_scheme.sh`
**Purpose**: Extracts the security schemes (e.g., `api_key`, `oauth2`) and active subscriptions for all APIs deployed on the WSO2 API Manager.  
**Output**: Generates a CSV file (`api_security_schemes.csv`) containing the API Name, Version, Context, enabled security schemes, whether security is disabled (`authType` set to `None`), and a grouped list of its subscriptions.  
**Requirements**: Requires WSO2 API Manager web session tokens (`AM_ACC_TOKEN_DEFAULT_P2` cookie and `WSO2_AM_TOKEN_1_Default` bearer token). See usage below.

### 2. `check-deployed-apis.sh`
**Purpose**: Scans the API Manager to determine which APIs are deployed to specific gateway environments (e.g., `apim-gw-v4-ext`, `new-nga-apigwc`).  
**Output**: Generates a CSV file (`deployed_apis.csv`) listing each API, its version, the environments it's deployed to, and a boolean check on whether it matches the target environments.  
**Requirements**: Requires the same web session tokens as the security scheme script.

### 3. `backup-api-definitions.sh`
**Purpose**: Connects to an environment using `apictl` and extracts a backup of an API's OpenAPI/Swagger definition (`swagger.yaml`).  
**Output**: Saves a backup of the swagger definition inside the local `./backups` directory.  
**Requirements**: Requires the WSO2 API Controller (`apictl`) installed and configured with your environments.

### 4. `compare-api-definitions.sh`
**Purpose**: Compares the `swagger.yaml` definitions of two APIs (or the same API across two different environments) to identify changes or drifts in the OpenAPI spec. Uses `dyff` for a clean YAML comparison.  
**Usage**: Can be run interactively (prompts for source and target APIs) or non-interactively via arguments.  
**Requirements**: Requires `apictl` and `dyff`.

---

## Usage Guide for `get_api_security_scheme.sh` and `check-deployed-apis.sh`

These scripts interact with the WSO2 API Manager Publisher v3 REST APIs.

### Prerequisites

You will need the following authentication tokens to interact with the WSO2 Publisher API:
- `AM_ACC_TOKEN_DEFAULT_P2`: Your active session Cookie.
- `WSO2_AM_TOKEN_1_Default`: Your active Bearer Token.

*Tip: You can find these by opening your browser's Developer Tools (Network Tab) while logged into the WSO2 Publisher Portal and inspecting any of the API requests.*

Ensure you also have `jq` and `curl` installed on your machine.

### 1. (Optional) Set up Environment Variables
To avoid entering your tokens manually every time you run the script, create a `.env.tokens` file in the same directory:
```bash
AM_ACC_TOKEN_DEFAULT_P2="your_cookie_value_here"
WSO2_AM_TOKEN_1_Default="your_bearer_token_here"

# You can optionally hardcode the target environment URL here as well:
# APIM_BASE_URL="https://nonprod-apim.yomabank.org"
```

### 2. Run the Script
Make sure the scripts are executable, then run them from your terminal:
```bash
chmod +x get_api_security_scheme.sh check-deployed-apis.sh
./get_api_security_scheme.sh
```

### 3. Follow the Prompts
- **Base URL**: If `APIM_BASE_URL` is not set, it will prompt you for the environment URL.
- **Missing/Expired Tokens**: If tokens are absent or expired, you will be prompted in the terminal to paste them.
- **Output File**: It will ask you for the desired CSV filename.

---

## Usage Guide for `apictl` Scripts (`backup-api-definitions.sh` & `compare-api-definitions.sh`)

These scripts rely on WSO2's `apictl` CLI tool rather than raw curl commands. 

1. Ensure `apictl` is installed and the environments are correctly mapped (`apictl add-env`).
2. Login to the environment: `apictl login <env_name>`
3. Run the scripts interactively:
   ```bash
   ./backup-api-definitions.sh
   # It will prompt for: Environment, API Name, and Version
   
   ./compare-api-definitions.sh
   # It will prompt for the Target API and the Source API to compare against
   ```
4. Non-interactive comparison:
   ```bash
   ./compare-api-definitions.sh --non-interactive <env1> <name1> <ver1> <env2> <name2> <ver2> [--output diff.txt]
   ```
