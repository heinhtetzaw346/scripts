#!/usr/bin/env bash
# ==============================================================================
# WSO2 API Manager API Migration Script
# Cross-Version (v4.1 -> v4.7) & Cross-Database (MySQL -> PostgreSQL)
#
# Automates the migration of APIs between WSO2 API Manager environments
# using apictl41 and apictl47.
# Preserves lifecycle statuses, endpoint credentials, revisions, and provider settings.
# ==============================================================================

set -uo pipefail

# ANSI Color Codes
declare -r WHITE="\033[0m"
declare -r RED="\033[1;31m"
declare -r GREEN="\033[1;32m"
declare -r YELLOW="\033[1;33m"
declare -r BLUE="\033[1;34m"
declare -r CYAN="\033[1;36m"
declare -r BOLD="\033[1m"

# Script Directory and Workspace Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/out"
AGENT_OUT_DIR="${SCRIPT_DIR}/../../.agent-files/out"
EXPORTED_BASE_DIR="${HOME}/.wso2apictl/exported/apis"

# Default Configuration
SRC_ENV=""
TGT_ENV=""
TARGET_PROVIDER=""
PRESERVE_PROVIDER="true"
SINGLE_API=""
SINGLE_VERSION=""
FILTER_PATTERN=""
SOURCE_PROVIDER_FILTER=""
STATUS_FILTER=""
LIMIT="10000"
USE_UPDATE="true"
ROTATE_REVISION="false"
SKIP_DEPLOYMENTS="false"
PRESERVE_STATUS="true"
PRESERVE_CREDENTIALS="true"
DRY_RUN="false"
KEEP_ARCHIVES="false"
INSECURE="true"
NON_INTERACTIVE="false"

# Binaries
APICTL41="${APICTL41:-}"
APICTL47="${APICTL47:-}"

# Logging helper
log() {
    local level="$1"
    local message="$2"
    case "$level" in
        success) echo -e "${GREEN}✔️  ${message}${WHITE}" ;;
        failure) echo -e "${RED}❌ ${message}${WHITE}" >&2 ;;
        progress) echo -e "${YELLOW}🚀 ${message}${WHITE}" ;;
        info) echo -e "${CYAN}ℹ️  ${message}${WHITE}" ;;
        warn) echo -e "${YELLOW}⚠️  ${message}${WHITE}" ;;
        header) echo -e "${BOLD}${BLUE}${message}${WHITE}" ;;
        *) echo -e "${message}" ;;
    esac
}

show_help() {
    cat <<EOF
==============================================================================
⚓ WSO2 API Migration Tool ⚓
Cross-Version (v4.1 -> v4.7) & Cross-Database (MySQL -> PostgreSQL)
==============================================================================

Usage:
  ./import-apis.sh [options]

Environment Options:
  -s, --source-env <env>        Source environment name in apictl41 (e.g. nonprod-io)
  -t, --target-env <env>        Target environment name in apictl47 (e.g. nonprod-io-new)

Provider Options:
      --preserve-provider       Preserve the original API provider/creator in target cluster (default: true)
  -r, --provider <provider>     Target provider for imported APIs (overrides provider, sets preserve-provider=false)

Filter Options:
  -a, --api <name>              Migrate only a single API matching exact name
  -v, --version <version>       Specify version when migrating single API or filtering
  -f, --filter <pattern>        Filter APIs whose name matches grep regex pattern
      --source-provider <name>  Migrate only APIs created by a specific source provider
      --status <status>         Filter by API lifecycle status (e.g. PUBLISHED, CREATED)
  -l, --limit <num>             Max APIs to retrieve from source (default: 10000)

Execution & Behavior:
      --dry-run                 Simulate migration: list APIs without exporting/importing
      --no-update               Do not pass --update to apictl47 import (fail if API exists)
      --rotate-revision         Rotate revisions with each update in target cluster
      --skip-deployments        Update only the working copy and skip deployment steps in target
      --no-preserve-status      Do not preserve API lifecycle status (imports as CREATED)
      --no-preserve-credentials Do not preserve endpoint security credentials
      --keep-archives           Preserve prepared ready zip archives after import
      --secure                  Enforce strict SSL verification (default is insecure -k)
  -y, --yes                     Non-interactive confirmation
  -h, --help                    Show this help manual

Examples:
  # Interactive mode with guided menus:
  ./import-apis.sh

  # Automated migration from nonprod-io to nonprod-io-new:
  ./import-apis.sh -s nonprod-io -t nonprod-io-new -y

  # Dry-run inspection:
  ./import-apis.sh -s nonprod-io -t nonprod-io-new --dry-run

  # Migrate a single specific API:
  ./import-apis.sh -s nonprod-io -t nonprod-io-new -a pocket-integration -v v1rc -y

  # Migrate only PUBLISHED APIs matching a regex pattern:
  ./import-apis.sh -s nonprod-io -t nonprod-io-new --filter "^abs-" --status PUBLISHED -y

  # Reassign all APIs to 'admin' provider in target cluster:
  ./import-apis.sh -s nonprod-io -t nonprod-io-new -r admin -y

EOF
}

# Parse Command-Line Arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--source-env)
                SRC_ENV="$2"; shift 2 ;;
            -t|--target-env)
                TGT_ENV="$2"; shift 2 ;;
            -r|--provider)
                TARGET_PROVIDER="$2"; PRESERVE_PROVIDER="false"; shift 2 ;;
            --preserve-provider)
                PRESERVE_PROVIDER="true"; TARGET_PROVIDER=""; shift ;;
            -a|--api|--name)
                SINGLE_API="$2"; shift 2 ;;
            -v|--version)
                SINGLE_VERSION="$2"; shift 2 ;;
            -f|--filter)
                FILTER_PATTERN="$2"; shift 2 ;;
            --source-provider)
                SOURCE_PROVIDER_FILTER="$2"; shift 2 ;;
            --status|--status-filter)
                STATUS_FILTER="$2"; shift 2 ;;
            -l|--limit)
                LIMIT="$2"; shift 2 ;;
            --no-update)
                USE_UPDATE="false"; shift ;;
            --rotate-revision)
                ROTATE_REVISION="true"; shift ;;
            --skip-deployments)
                SKIP_DEPLOYMENTS="true"; shift ;;
            --no-preserve-status)
                PRESERVE_STATUS="false"; shift ;;
            --no-preserve-credentials)
                PRESERVE_CREDENTIALS="false"; shift ;;
            --dry-run)
                DRY_RUN="true"; shift ;;
            --keep-archives)
                KEEP_ARCHIVES="true"; shift ;;
            --secure)
                INSECURE="false"; shift ;;
            -y|--yes)
                NON_INTERACTIVE="true"; shift ;;
            -h|--help)
                show_help; exit 0 ;;
            *)
                log failure "Unknown parameter: $1"
                echo "Use --help for usage instructions."
                exit 1 ;;
        esac
    done
}

# Discover and Verify Required Tools
check_tools() {
    log progress "Verifying required tools in \$PATH"

    # Locate apictl41
    if [ -z "$APICTL41" ]; then
        if command -v apictl41 >/dev/null 2>&1; then
            APICTL41="$(command -v apictl41)"
        elif [ -x "${HOME}/.local/bin/apictl41" ]; then
            APICTL41="${HOME}/.local/bin/apictl41"
        else
            log failure "apictl41 binary not found. Please ensure apictl41 is in \$PATH or ~/.local/bin/."
            exit 1
        fi
    fi

    # Locate apictl47
    if [ -z "$APICTL47" ]; then
        if command -v apictl47 >/dev/null 2>&1; then
            APICTL47="$(command -v apictl47)"
        elif [ -x "${HOME}/.local/bin/apictl47" ]; then
            APICTL47="${HOME}/.local/bin/apictl47"
        else
            log failure "apictl47 binary not found. Please ensure apictl47 is in \$PATH or ~/.local/bin/."
            exit 1
        fi
    fi

    local -a required_bins=("python3" "jq" "unzip" "zip")
    for bin in "${required_bins[@]}"; do
        if ! command -v "$bin" >/dev/null 2>&1; then
            log failure "Missing required utility: $bin. Please install it."
            exit 1
        fi
    done

    # Verify Python PyYAML module
    if ! python3 -c "import yaml" >/dev/null 2>&1; then
        log failure "Python package 'pyyaml' is required. Run: pip install pyyaml"
        exit 1
    fi

    log success "Tools verified: apictl41 ($APICTL41), apictl47 ($APICTL47), python3, jq, unzip, zip"
}

# Fetch environment lists
get_apictl_envs() {
    local cmd="$1"
    "$cmd" get envs 2>/dev/null | awk 'NR>1 {print $1}' | grep -v '^$' || true
}

# Interactive Environment Selection
select_environments_interactively() {
    echo ""
    log header "--- Environment Selection ---"
    echo "Common preset migration pairs:"
    echo "  1) nonprod-io   -> nonprod-io-new  (Recommended for nonprod io)"
    echo "  2) nonprod-org  -> nonprod-org-new (Recommended for nonprod org)"
    echo "  3) nonprod-apix -> nonprod-apix"
    echo "  4) prod-io      -> prod-io"
    echo "  5) prod-org     -> prod-org"
    echo "  6) prod-apix    -> prod-apix"
    echo "  7) Custom selection from available environments"
    echo ""

    local choice
    read -rp "Select option [1-7, default 1]: " choice
    choice="${choice:-1}"

    case "$choice" in
        1) SRC_ENV="nonprod-io"; TGT_ENV="nonprod-io-new" ;;
        2) SRC_ENV="nonprod-org"; TGT_ENV="nonprod-org-new" ;;
        3) SRC_ENV="nonprod-apix"; TGT_ENV="nonprod-apix" ;;
        4) SRC_ENV="prod-io"; TGT_ENV="prod-io" ;;
        5) SRC_ENV="prod-org"; TGT_ENV="prod-org" ;;
        6) SRC_ENV="prod-apix"; TGT_ENV="prod-apix" ;;
        7)
            # Custom selection
            local src_envs tgt_envs
            mapfile -t src_envs < <(get_apictl_envs "$APICTL41")
            mapfile -t tgt_envs < <(get_apictl_envs "$APICTL47")

            echo ""
            echo "Available Source Environments (apictl41):"
            for i in "${!src_envs[@]}"; do
                echo "  $((i+1))) ${src_envs[$i]}"
            done
            local src_choice
            read -rp "Select source environment [1-${#src_envs[@]}]: " src_choice
            if [[ "$src_choice" =~ ^[0-9]+$ ]] && [ "$src_choice" -ge 1 ] && [ "$src_choice" -le "${#src_envs[@]}" ]; then
                SRC_ENV="${src_envs[$((src_choice-1))]}"
            else
                read -rp "Enter source environment name manually: " SRC_ENV
            fi

            echo ""
            echo "Available Target Environments (apictl47):"
            for i in "${!tgt_envs[@]}"; do
                echo "  $((i+1))) ${tgt_envs[$i]}"
            done
            local tgt_choice
            read -rp "Select target environment [1-${#tgt_envs[@]}]: " tgt_choice
            if [[ "$tgt_choice" =~ ^[0-9]+$ ]] && [ "$tgt_choice" -ge 1 ] && [ "$tgt_choice" -le "${#tgt_envs[@]}" ]; then
                TGT_ENV="${tgt_envs[$((tgt_choice-1))]}"
            else
                read -rp "Enter target environment name manually: " TGT_ENV
            fi
            ;;
        *)
            log failure "Invalid selection."
            exit 1
            ;;
    esac

    # Provider Strategy Selection
    echo ""
    log header "--- API Provider Strategy ---"
    echo "  1) Preserve original API providers (--preserve-provider, Recommended)"
    echo "  2) Reassign all APIs to 'admin'"
    echo "  3) Specify custom target provider"
    local provider_choice
    read -rp "Select provider strategy [1-3, default 1]: " provider_choice
    provider_choice="${provider_choice:-1}"

    case "$provider_choice" in
        1) TARGET_PROVIDER=""; PRESERVE_PROVIDER="true" ;;
        2) TARGET_PROVIDER="admin"; PRESERVE_PROVIDER="false" ;;
        3)
            read -rp "Enter custom target provider username: " TARGET_PROVIDER
            PRESERVE_PROVIDER="false"
            ;;
        *) TARGET_PROVIDER=""; PRESERVE_PROVIDER="true" ;;
    esac
}

# Validate Source & Target Environments
validate_environments() {
    log progress "Validating environment configuration"

    local src_envs tgt_envs
    mapfile -t src_envs < <(get_apictl_envs "$APICTL41")
    mapfile -t tgt_envs < <(get_apictl_envs "$APICTL47")

    local src_found=0 tgt_found=0
    for e in "${src_envs[@]}"; do
        [ "$e" == "$SRC_ENV" ] && src_found=1 && break
    done

    for e in "${tgt_envs[@]}"; do
        [ "$e" == "$TGT_ENV" ] && tgt_found=1 && break
    done

    if [ "$src_found" -eq 0 ]; then
        log failure "Source environment '$SRC_ENV' was not found in apictl41 environments."
        echo "Available apictl41 environments: ${src_envs[*]}"
        exit 1
    fi

    if [ "$tgt_found" -eq 0 ]; then
        log failure "Target environment '$TGT_ENV' was not found in apictl47 environments."
        echo "Available apictl47 environments: ${tgt_envs[*]}"
        exit 1
    fi

    log success "Source environment '$SRC_ENV' and Target environment '$TGT_ENV' are valid."
}

# Python Helper to unpack, patch metadata, and repack API archive
transform_api_metadata_and_repack() {
    local zip_in="$1"
    local zip_out="$2"
    local target_provider="$3"
    local preserve_provider="$4"
    local use_update="$5"
    local rotate_revision="$6"
    local preserve_status="${7:-true}"

    python3 - "$zip_in" "$zip_out" "$target_provider" "$preserve_provider" "$use_update" "$rotate_revision" "$preserve_status" <<'PYEOF'
import sys
import os
import re
import tempfile
import zipfile
import yaml

zip_in = sys.argv[1]
zip_out = sys.argv[2]
target_provider = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
preserve_provider = (sys.argv[4].lower() == 'true') if len(sys.argv) > 4 else True
use_update = (sys.argv[5].lower() == 'true') if len(sys.argv) > 5 else True
rotate_revision = (sys.argv[6].lower() == 'true') if len(sys.argv) > 6 else False
preserve_status = (sys.argv[7].lower() == 'true') if len(sys.argv) > 7 else True

if not os.path.isfile(zip_in):
    sys.stderr.write(f"Source archive does not exist: {zip_in}\n")
    sys.exit(1)

with tempfile.TemporaryDirectory() as tmp_dir:
    try:
        with zipfile.ZipFile(zip_in, 'r') as z:
            z.extractall(tmp_dir)
    except Exception as e:
        sys.stderr.write(f"Failed to unpack {zip_in}: {e}\n")
        sys.exit(1)

    # 1. Update api_meta.yaml
    for r, _, files in os.walk(tmp_dir):
        for f in files:
            if f == 'api_meta.yaml':
                meta_path = os.path.join(r, f)
                try:
                    with open(meta_path, 'r', encoding='utf-8') as fp:
                        meta = yaml.safe_load(fp) or {}
                except Exception as e:
                    sys.stderr.write(f"Failed to parse {meta_path}: {e}\n")
                    sys.exit(1)

                deploy = meta.setdefault('deploy', {})
                imp = deploy.setdefault('import', {})
                imp['update'] = use_update
                imp['rotateRevision'] = rotate_revision
                imp['preserveProvider'] = preserve_provider

                if not preserve_provider and target_provider:
                    meta['provider'] = target_provider

                try:
                    with open(meta_path, 'w', encoding='utf-8') as fp:
                        yaml.safe_dump(meta, fp, sort_keys=False)
                except Exception as e:
                    sys.stderr.write(f"Failed to write {meta_path}: {e}\n")
                    sys.exit(1)

            elif f.endswith('.wsdl'):
                wsdl_path = os.path.join(r, f)
                try:
                    with open(wsdl_path, 'r', encoding='utf-8') as fp:
                        wsdl_content = fp.read()
                    # Compatibility Fix: Strip schemaLocation attributes from <xs:import> and <xsd:import>
                    # This prevents 400 Bad Request (900907) when unbundled local XSDs or unreachable private URLs are referenced
                    new_wsdl = re.sub(r'schemaLocation="[^"]*"', '', wsdl_content)
                    with open(wsdl_path, 'w', encoding='utf-8') as fp:
                        fp.write(new_wsdl)
                except Exception as e:
                    sys.stderr.write(f"Failed to process WSDL {wsdl_path}: {e}\n")
                    sys.exit(1)

            elif f == 'api.yaml':
                api_yaml_path = os.path.join(r, f)
                try:
                    with open(api_yaml_path, 'r', encoding='utf-8') as fp:
                        api_data = yaml.safe_load(fp) or {}
                except Exception as e:
                    sys.stderr.write(f"Failed to parse {api_yaml_path}: {e}\n")
                    sys.exit(1)

                data_block = api_data.get('data', {})

                # Compatibility Fix: Empty apiThrottlingPolicy causes 400 Bad Request in WSO2 AM 4.7
                if data_block.get('apiThrottlingPolicy') == '':
                    data_block['apiThrottlingPolicy'] = None

                # Compatibility Fix: Clear legacy Carbon Registry wsdlUrl paths
                wsdl_url = data_block.get('wsdlUrl')
                if wsdl_url and ('_system/governance' in wsdl_url or '/registry/' in wsdl_url):
                    data_block['wsdlUrl'] = None

                # Compatibility Fix: Remove empty additionalProperties (which WSO2 AM 4.7 rejects)
                if 'additionalProperties' in data_block and isinstance(data_block['additionalProperties'], list):
                    new_props = []
                    for p in data_block['additionalProperties']:
                        if isinstance(p, dict) and p.get('value', '') != '':
                            new_props.append(p)
                        elif isinstance(p, str) and p != '':
                            new_props.append(p)
                    data_block['additionalProperties'] = new_props

                if 'additionalPropertiesMap' in data_block and isinstance(data_block['additionalPropertiesMap'], dict):
                    filtered_map = {}
                    for k, v in data_block['additionalPropertiesMap'].items():
                        if isinstance(v, dict):
                            if v.get('value', '') != '':
                                filtered_map[k] = v
                        elif v != '':
                            filtered_map[k] = v
                    data_block['additionalPropertiesMap'] = filtered_map

                # Role normalization mapping: map legacy/case-mismatched roles to canonical Carbon roles
                ROLE_MAP = {
                    'yoma_developer': 'YOMA_Developer',
                    'wm_developer': 'WM_Developer',
                    'yoma_publisher': 'YOMA_Publisher',
                    'wm_publisher': 'WM_Publisher',
                }

                def normalize_roles(roles):
                    if not roles:
                        return []
                    normalized = []
                    for r in roles:
                        if not r:
                            continue
                        canonical = ROLE_MAP.get(r.lower(), r)
                        if canonical not in normalized:
                            normalized.append(canonical)
                    return normalized

                if 'visibleRoles' in data_block and isinstance(data_block['visibleRoles'], list):
                    data_block['visibleRoles'] = normalize_roles(data_block['visibleRoles'])

                if 'accessControlRoles' in data_block and isinstance(data_block['accessControlRoles'], list):
                    data_block['accessControlRoles'] = normalize_roles(data_block['accessControlRoles'])

                if not preserve_status:
                    data_block['lifeCycleStatus'] = 'CREATED'

                if not preserve_provider and target_provider:
                    data_block['provider'] = target_provider

                try:
                    with open(api_yaml_path, 'w', encoding='utf-8') as fp:
                        yaml.safe_dump(api_data, fp, sort_keys=False)
                except Exception as e:
                    sys.stderr.write(f"Failed to write {api_yaml_path}: {e}\n")
                    sys.exit(1)

    # 2. Repack into ready zip
    os.makedirs(os.path.dirname(os.path.abspath(zip_out)), exist_ok=True)
    try:
        with zipfile.ZipFile(zip_out, 'w', compression=zipfile.ZIP_DEFLATED) as z:
            for root, dirs, files in os.walk(tmp_dir):
                for f in files:
                    fp = os.path.join(root, f)
                    arcname = os.path.relpath(fp, tmp_dir)
                    z.write(fp, arcname)
    except Exception as e:
        sys.stderr.write(f"Failed to create ready archive {zip_out}: {e}\n")
        sys.exit(1)

sys.exit(0)
PYEOF
}

# Main Execution Flow
main() {
    parse_args "$@"

    echo ""
    log header "============================================================"
    log header "⚓ WSO2 API Migration Tool ⚓"
    log header "Cross-Version (v4.1 -> v4.7) & Cross-Database (MySQL -> PostgreSQL)"
    log header "============================================================"

    check_tools

    # Prompt interactively if environments were not passed
    if [ -z "$SRC_ENV" ] || [ -z "$TGT_ENV" ]; then
        select_environments_interactively
    fi

    validate_environments

    # Print Planned Settings
    echo ""
    log header "--- Migration Plan Configuration ---"
    echo -e "  ${BOLD}Source Environment${WHITE}     : ${CYAN}${SRC_ENV}${WHITE} (via apictl41)"
    echo -e "  ${BOLD}Target Environment${WHITE}     : ${CYAN}${TGT_ENV}${WHITE} (via apictl47)"
    if [ "$PRESERVE_PROVIDER" = "true" ]; then
        echo -e "  ${BOLD}Target Provider Strategy${WHITE} : ${YELLOW}Preserve original provider (--preserve-provider)${WHITE}"
    else
        echo -e "  ${BOLD}Target Provider Strategy${WHITE} : ${GREEN}Assign to '${TARGET_PROVIDER}'${WHITE}"
    fi
    echo -e "  ${BOLD}Update Existing APIs${WHITE}    : ${USE_UPDATE}"
    echo -e "  ${BOLD}Rotate Revisions${WHITE}        : ${ROTATE_REVISION}"
    echo -e "  ${BOLD}Skip Deployments${WHITE}        : ${SKIP_DEPLOYMENTS}"
    echo -e "  ${BOLD}Preserve Status${WHITE}         : ${PRESERVE_STATUS}"
    echo -e "  ${BOLD}Preserve Credentials${WHITE}    : ${PRESERVE_CREDENTIALS}"
    [ -n "$SINGLE_API" ] && echo -e "  ${BOLD}Single API Target${WHITE}       : ${CYAN}${SINGLE_API}${WHITE}"
    [ -n "$SINGLE_VERSION" ] && echo -e "  ${BOLD}Version Target${WHITE}          : ${CYAN}${SINGLE_VERSION}${WHITE}"
    [ -n "$FILTER_PATTERN" ] && echo -e "  ${BOLD}Name Regex Filter${WHITE}       : ${CYAN}${FILTER_PATTERN}${WHITE}"
    [ -n "$SOURCE_PROVIDER_FILTER" ] && echo -e "  ${BOLD}Source Provider Filter${WHITE}  : ${CYAN}${SOURCE_PROVIDER_FILTER}${WHITE}"
    [ -n "$STATUS_FILTER" ] && echo -e "  ${BOLD}Status Filter${WHITE}           : ${CYAN}${STATUS_FILTER}${WHITE}"
    echo -e "  ${BOLD}Dry-Run Simulation${WHITE}      : ${DRY_RUN}"
    echo ""

    if [ "$NON_INTERACTIVE" != "true" ] && [ "$DRY_RUN" != "true" ]; then
        local confirm
        read -rp "Proceed with migration? [Y/n]: " confirm
        confirm="${confirm:-Y}"
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log info "Migration aborted by user."
            exit 0
        fi
    fi

    # Fetch API list from source environment
    log progress "Fetching API catalog from source environment '$SRC_ENV' (limit: $LIMIT)..."
    local get_apis_cmd=( "$APICTL41" get apis -e "$SRC_ENV" -l "$LIMIT" --format "{{ jsonPretty . }}" )
    if [ "$INSECURE" = "true" ]; then
        get_apis_cmd+=( -k )
    fi

    local raw_apis_json
    raw_apis_json=$("${get_apis_cmd[@]}" 2>/dev/null) || {
        log failure "Failed to query APIs from $SRC_ENV via apictl41."
        exit 1
    }

    # Verify JSON structure
    if [ -z "$raw_apis_json" ]; then
        log warn "No APIs found in $SRC_ENV."
        exit 0
    fi

    local total_raw_count
    total_raw_count=$(echo "$raw_apis_json" | jq -s 'length' 2>/dev/null || echo "0")
    if [ "$total_raw_count" -eq 0 ]; then
        log warn "Zero APIs returned from $SRC_ENV."
        exit 0
    fi

    log success "Retrieved ${total_raw_count} APIs from $SRC_ENV."

    # Prepare directories and audit report
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$AGENT_OUT_DIR" 2>/dev/null || true

    local audit_csv="${OUTPUT_DIR}/wso2_api_migration_${SRC_ENV}_to_${TGT_ENV}_${timestamp}.csv"
    echo "Index,API Name,Version,Source Provider,Target Provider,Lifecycle Status,Status,Message" > "$audit_csv"

    # Counters
    local count_discovered=0
    local count_skipped=0
    local count_success=0
    local count_failed=0

    # Ready archives directory for apictl47 import
    local ready_subdir="ready/${SRC_ENV}"
    local ready_base_dir="${EXPORTED_BASE_DIR}/${ready_subdir}"
    mkdir -p "$ready_base_dir"

    echo ""
    log header "============================================================"
    log header "🚀 Beginning API Migration..."
    log header "============================================================"

    # Process APIs stream
    while IFS= read -r api_entry; do
        ((count_discovered++))
        local api_name api_version api_provider api_status api_context
        api_name=$(echo "$api_entry" | jq -r '.Name // empty')
        api_version=$(echo "$api_entry" | jq -r '.Version // empty')
        api_provider=$(echo "$api_entry" | jq -r '.Provider // empty')
        api_status=$(echo "$api_entry" | jq -r '.LifeCycleStatus // empty')
        api_context=$(echo "$api_entry" | jq -r '.Context // empty')

        [ -z "$api_name" ] && continue

        # Filter check: Single API
        if [ -n "$SINGLE_API" ] && [ "$api_name" != "$SINGLE_API" ]; then
            continue
        fi

        # Filter check: Single Version
        if [ -n "$SINGLE_VERSION" ] && [ "$api_version" != "$SINGLE_VERSION" ]; then
            continue
        fi

        # Filter check: Regex pattern
        if [ -n "$FILTER_PATTERN" ] && ! echo "$api_name" | grep -qE "$FILTER_PATTERN"; then
            continue
        fi

        # Filter check: Source provider
        if [ -n "$SOURCE_PROVIDER_FILTER" ] && [ "$api_provider" != "$SOURCE_PROVIDER_FILTER" ]; then
            continue
        fi

        # Filter check: Status filter
        if [ -n "$STATUS_FILTER" ] && [ "$api_status" != "$STATUS_FILTER" ]; then
            continue
        fi

        local effective_target_provider
        if [ "$PRESERVE_PROVIDER" = "true" ]; then
            effective_target_provider="$api_provider"
        else
            effective_target_provider="$TARGET_PROVIDER"
        fi

        if [ "$DRY_RUN" = "true" ]; then
            log info "[$count_discovered/$total_raw_count] [DRY-RUN] Would migrate '$api_name' ($api_version) (Provider: $api_provider -> $effective_target_provider, Status: $api_status)"
            ((count_success++))
            echo "${count_discovered},\"${api_name}\",\"${api_version}\",\"${api_provider}\",\"${effective_target_provider}\",\"${api_status}\",DRY_RUN,\"Simulated migration\"" >> "$audit_csv"
            continue
        fi

        echo ""
        log progress "[$count_discovered/$total_raw_count] Processing '$api_name' ($api_version) (Provider: $api_provider -> $effective_target_provider, Status: $api_status)..."

        # -------------------------------------------------------------
        # Step 1: Export API from Source Environment with apictl41
        # -------------------------------------------------------------
        local export_cmd=( "$APICTL41" export api -n "$api_name" -v "$api_version" -r "$api_provider" -e "$SRC_ENV" )
        if [ "$PRESERVE_STATUS" = "true" ]; then
            export_cmd+=( --preserve-status )
        fi
        if [ "$PRESERVE_CREDENTIALS" = "true" ]; then
            export_cmd+=( --preserve-credentials )
        fi
        if [ "$INSECURE" = "true" ]; then
            export_cmd+=( -k )
        fi

        local export_out export_rc
        export_out=$("${export_cmd[@]}" 2>&1)
        export_rc=$?

        # Validate export output and exit status
        if [ $export_rc -ne 0 ] || echo "$export_out" | grep -qiE "^Error |Exit status "; then
            local err_msg
            err_msg=$(echo "$export_out" | head -n 2 | tr '\n' ' ' | sed 's/"/""/g')
            log failure "Export failed for '$api_name' ($api_version): $err_msg"
            ((count_failed++))
            echo "${count_discovered},\"${api_name}\",\"${api_version}\",\"${api_provider}\",\"${effective_target_provider}\",\"${api_status}\",FAILED,\"Export error: ${err_msg}\"" >> "$audit_csv"
            continue
        fi

        # Resolve exported zip file
        local src_zip_path=""
        if echo "$export_out" | grep -q "Find the exported API at "; then
            src_zip_path=$(echo "$export_out" | grep "Find the exported API at " | sed 's/.*Find the exported API at //')
        fi

        if [ -z "$src_zip_path" ] || [ ! -f "$src_zip_path" ]; then
            src_zip_path="${EXPORTED_BASE_DIR}/${SRC_ENV}/${api_name}_${api_version}.zip"
        fi

        if [ ! -f "$src_zip_path" ]; then
            log failure "Exported archive file not found at: $src_zip_path"
            ((count_failed++))
            echo "${count_discovered},\"${api_name}\",\"${api_version}\",\"${api_provider}\",\"${effective_target_provider}\",\"${api_status}\",FAILED,\"Archive missing at: ${src_zip_path}\"" >> "$audit_csv"
            continue
        fi

        # -------------------------------------------------------------
        # Step 2: Sanitize & Transform Metadata (Fix empty throttling policy, provider, updates)
        # -------------------------------------------------------------
        local ready_zip_full="${ready_base_dir}/${api_name}_${api_version}_ready.zip"

        if ! transform_api_metadata_and_repack "$src_zip_path" "$ready_zip_full" "$TARGET_PROVIDER" "$PRESERVE_PROVIDER" "$USE_UPDATE" "$ROTATE_REVISION" "$PRESERVE_STATUS"; then
            log failure "Failed to transform metadata for '$api_name' ($api_version)."
            ((count_failed++))
            echo "${count_discovered},\"${api_name}\",\"${api_version}\",\"${api_provider}\",\"${effective_target_provider}\",\"${api_status}\",FAILED,\"Metadata transform failed\"" >> "$audit_csv"
            continue
        fi

        # -------------------------------------------------------------
        # Step 3: Import API into Target Environment with apictl47
        # -------------------------------------------------------------
        local import_cmd=( "$APICTL47" import api -f "$ready_zip_full" -e "$TGT_ENV" )

        if [ "$PRESERVE_PROVIDER" = "true" ]; then
            import_cmd+=( --preserve-provider )
        else
            import_cmd+=( --preserve-provider=false )
        fi

        if [ "$USE_UPDATE" = "true" ]; then
            import_cmd+=( --update )
        fi

        if [ "$ROTATE_REVISION" = "true" ]; then
            import_cmd+=( --rotate-revision )
        fi

        if [ "$SKIP_DEPLOYMENTS" = "true" ]; then
            import_cmd+=( --skip-deployments )
        fi

        if [ "$INSECURE" = "true" ]; then
            import_cmd+=( -k )
        fi

        local import_out import_rc
        import_out=$("${import_cmd[@]}" 2>&1)
        import_rc=$?

        # Validate import output
        if [ $import_rc -eq 0 ] && echo "$import_out" | grep -qi "Successfully imported\|Successfully updated"; then
            log success "Successfully migrated '$api_name' ($api_version) into '$TGT_ENV'."
            ((count_success++))
            echo "${count_discovered},\"${api_name}\",\"${api_version}\",\"${api_provider}\",\"${effective_target_provider}\",\"${api_status}\",SUCCESS,\"Imported successfully\"" >> "$audit_csv"
        else
            local imp_err
            imp_err=$(echo "$import_out" | grep -iE "error|reason|failed" | head -n 2 | tr '\n' ' ' | sed 's/"/""/g')
            [ -z "$imp_err" ] && imp_err=$(echo "$import_out" | head -n 2 | tr '\n' ' ' | sed 's/"/""/g')
            log failure "Import failed for '$api_name' ($api_version): $imp_err"
            ((count_failed++))
            echo "${count_discovered},\"${api_name}\",\"${api_version}\",\"${api_provider}\",\"${effective_target_provider}\",\"${api_status}\",FAILED,\"Import error: ${imp_err}\"" >> "$audit_csv"
        fi

        # Cleanup ready zip if requested
        if [ "$KEEP_ARCHIVES" != "true" ] && [ -f "$ready_zip_full" ]; then
            rm -f "$ready_zip_full"
        fi

    done < <(echo "$raw_apis_json" | jq -s -c '.[]')

    # Copy audit log to agent out directory if present
    if [ -d "$AGENT_OUT_DIR" ]; then
        cp -f "$audit_csv" "${AGENT_OUT_DIR}/" 2>/dev/null || true
    fi

    # Display Final Migration Summary
    echo ""
    log header "============================================================"
    log header "📊 Migration Run Summary (${SRC_ENV} -> ${TGT_ENV})"
    log header "============================================================"
    echo -e "  Total APIs Discovered         : ${BOLD}${count_discovered}${WHITE}"
    echo -e "  Skipped APIs                  : ${CYAN}${count_skipped}${WHITE}"
    echo -e "  Successfully Migrated         : ${GREEN}${count_success}${WHITE}"
    echo -e "  Failed Migrations             : ${RED}${count_failed}${WHITE}"
    echo -e "  Audit Log File                : ${BOLD}${audit_csv}${WHITE}"
    log header "============================================================"

    if [ "$count_failed" -gt 0 ]; then
        log warn "Some APIs failed to migrate. Review $audit_csv for failure details."
        exit 1
    else
        log success "All eligible APIs migrated successfully!"
        exit 0
    fi
}

main "$@"
