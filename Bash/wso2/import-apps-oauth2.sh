#!/usr/bin/env bash
# ==============================================================================
# WSO2 API Manager Application & OAuth2 Client Migration Script
# Cross-Version (v4.1 -> v4.7) & Cross-Database (MySQL -> PostgreSQL)
#
# Automates the migration of applications, subscriptions, and OAuth2 keys
# between WSO2 API Manager environments using apictl41 and apictl47.
# Reference: README-wso2-application-oauth2-import.md
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
EXPORTED_BASE_DIR="${HOME}/.wso2apictl/exported/apps"

# Default Configuration
SRC_ENV=""
TGT_ENV=""
TARGET_OWNER="admin"
PRESERVE_OWNER="false"
SINGLE_APP=""
FILTER_PATTERN=""
SOURCE_OWNER_FILTER=""
LIMIT="10000"
SKIP_DEFAULT_APP="true"
USE_UPDATE="true"
SKIP_SUBSCRIPTIONS="false"
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
⚓ WSO2 Application & OAuth2 Client Migration Tool ⚓
Cross-Version (v4.1 -> v4.7) & Cross-Database (MySQL -> PostgreSQL)
==============================================================================

Usage:
  ./import-apps-oauth2.sh [options]

Environment Options:
  -s, --source-env <env>        Source environment name in apictl41 (e.g. nonprod-io)
  -t, --target-env <env>        Target environment name in apictl47 (e.g. nonprod-io-new)

Owner Options:
  -o, --owner <owner>           Target owner for imported applications (default: "admin")
      --preserve-owner          Preserve the original application owner in target cluster
                                (Requires developer account in target user store)

Filter Options:
  -a, --app <name>              Migrate only a single application matching exact name
  -f, --filter <pattern>        Filter applications whose name matches grep regex pattern
      --source-owner <owner>    Migrate only applications owned by a specific source user
  -l, --limit <num>             Max applications to retrieve from source (default: 10000)
      --skip-default-app        Skip "DefaultApplication" (default: true)
      --include-default-app     Include "DefaultApplication" in migration

Execution & Behavior:
      --dry-run                 Simulate migration: list apps without exporting/importing
      --skip-subscriptions      Skip application subscriptions during target import
      --no-update               Do not pass --update to apictl47 import
      --keep-archives           Preserve prepared ready zip archives after import
      --secure                  Enforce strict SSL verification (default is insecure -k)
  -y, --yes                     Non-interactive confirmation
  -h, --help                    Show this help manual

Examples:
  # Interactive mode with guided menus:
  ./import-apps-oauth2.sh

  # Automated migration for nonprod-io to nonprod-io-new:
  ./import-apps-oauth2.sh -s nonprod-io -t nonprod-io-new -o admin -y

  # Dry-run inspection:
  ./import-apps-oauth2.sh -s nonprod-io -t nonprod-io-new --dry-run

  # Migrate a single specific application:
  ./import-apps-oauth2.sh -s nonprod-io -t nonprod-io-new -a wave2c2p-ir-service -o admin -y

  # Preserve original owners for matching apps:
  ./import-apps-oauth2.sh -s nonprod-io -t nonprod-io-new --filter "^abs-" --preserve-owner -y

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
            -o|--owner)
                TARGET_OWNER="$2"; PRESERVE_OWNER="false"; shift 2 ;;
            --preserve-owner)
                PRESERVE_OWNER="true"; TARGET_OWNER=""; shift ;;
            -a|--app)
                SINGLE_APP="$2"; shift 2 ;;
            -f|--filter)
                FILTER_PATTERN="$2"; shift 2 ;;
            --source-owner)
                SOURCE_OWNER_FILTER="$2"; shift 2 ;;
            -l|--limit)
                LIMIT="$2"; shift 2 ;;
            --skip-default-app)
                SKIP_DEFAULT_APP="true"; shift ;;
            --include-default-app)
                SKIP_DEFAULT_APP="false"; shift ;;
            --skip-subscriptions)
                SKIP_SUBSCRIPTIONS="true"; shift ;;
            --no-update)
                USE_UPDATE="false"; shift ;;
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

    # Owner Strategy Selection
    echo ""
    log header "--- Application Owner Strategy ---"
    echo "  1) Assign all applications to 'admin' (Recommended: avoids LDAP/user store lookup errors)"
    echo "  2) Preserve original application owners (--preserve-owner)"
    echo "  3) Specify custom target owner"
    local owner_choice
    read -rp "Select owner strategy [1-3, default 1]: " owner_choice
    owner_choice="${owner_choice:-1}"

    case "$owner_choice" in
        1) TARGET_OWNER="admin"; PRESERVE_OWNER="false" ;;
        2) TARGET_OWNER=""; PRESERVE_OWNER="true" ;;
        3)
            read -rp "Enter custom target username: " TARGET_OWNER
            PRESERVE_OWNER="false"
            ;;
        *) TARGET_OWNER="admin"; PRESERVE_OWNER="false" ;;
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

# Helper to find existing target application with case-insensitive name match
find_target_app_by_case_insensitive_name() {
    local tgt_env="$1"
    local tgt_owner="$2"
    local search_name="$3"

    python3 - "$tgt_env" "$tgt_owner" "$search_name" <<'PYEOF'
import subprocess
import sys

tgt_env = sys.argv[1]
target_owner = sys.argv[2]
search_name = sys.argv[3]

try:
    out = subprocess.check_output(["apictl47", "get", "apps", "-e", tgt_env, "-l", "1000", "-k"], stderr=subprocess.DEVNULL).decode("utf-8")
    for line in out.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 4:
            owner = parts[-2]
            name = " ".join(parts[1:-2])
            if owner == target_owner and name.lower() == search_name.lower() and name != search_name:
                print(name)
                sys.exit(0)
except Exception:
    pass
sys.exit(0)
PYEOF
}

# Python Helper to unpack, patch metadata, and repack application archive
transform_metadata_and_repack() {
    local zip_in="$1"
    local zip_out="$2"
    local target_owner="$3"
    local preserve_owner="$4"
    local override_name="${5:-}"

    python3 - "$zip_in" "$zip_out" "$target_owner" "$preserve_owner" "$override_name" <<'PYEOF'
import sys
import os
import tempfile
import zipfile
import yaml

zip_in = sys.argv[1]
zip_out = sys.argv[2]
target_owner = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
preserve_owner = (sys.argv[4].lower() == 'true') if len(sys.argv) > 4 else False
override_name = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] else None

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

    meta_files = [os.path.join(r, f) for r, _, files in os.walk(tmp_dir) for f in files if f == 'application_meta.yaml']
    if not meta_files:
        sys.stderr.write(f"application_meta.yaml not found inside archive: {zip_in}\n")
        sys.exit(1)

    for meta_path in meta_files:
        try:
            with open(meta_path, 'r', encoding='utf-8') as f:
                meta = yaml.safe_load(f) or {}
        except Exception as e:
            sys.stderr.write(f"Failed to parse {meta_path}: {e}\n")
            sys.exit(1)

        deploy = meta.setdefault('deploy', {})
        imp = deploy.setdefault('import', {})
        # Ensure keys are NOT skipped during target import
        imp['skipKeys'] = False
        imp['update'] = True
        meta['skipKeys'] = False

        if override_name:
            meta['name'] = override_name

        if preserve_owner:
            imp['preserveOwner'] = True
            meta['preserveOwner'] = True
        elif target_owner:
            imp['preserveOwner'] = False
            meta['preserveOwner'] = False
            meta['owner'] = target_owner

        try:
            with open(meta_path, 'w', encoding='utf-8') as f:
                yaml.safe_dump(meta, f, sort_keys=False)
        except Exception as e:
            sys.stderr.write(f"Failed to write {meta_path}: {e}\n")
            sys.exit(1)

    if override_name:
        for r, _, files in os.walk(tmp_dir):
            for f in files:
                if f == 'application.yaml':
                    app_yaml_path = os.path.join(r, f)
                    try:
                        with open(app_yaml_path, 'r', encoding='utf-8') as f:
                            app_data = yaml.safe_load(f) or {}
                        if 'data' in app_data and 'applicationInfo' in app_data['data']:
                            app_data['data']['applicationInfo']['name'] = override_name
                        with open(app_yaml_path, 'w', encoding='utf-8') as f:
                            yaml.safe_dump(app_data, f, sort_keys=False)
                    except Exception as e:
                        sys.stderr.write(f"Failed to update app name in {app_yaml_path}: {e}\n")
                        sys.exit(1)

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
    log header "⚓ WSO2 Application & OAuth2 Client Migration Tool ⚓"
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
    echo -e "  ${BOLD}Source Environment${WHITE} : ${CYAN}${SRC_ENV}${WHITE} (via apictl41)"
    echo -e "  ${BOLD}Target Environment${WHITE} : ${CYAN}${TGT_ENV}${WHITE} (via apictl47)"
    if [ "$PRESERVE_OWNER" = "true" ]; then
        echo -e "  ${BOLD}Target Owner Strategy${WHITE} : ${YELLOW}Preserve original owners (--preserve-owner)${WHITE}"
    else
        echo -e "  ${BOLD}Target Owner Strategy${WHITE} : ${GREEN}Assign to '${TARGET_OWNER}'${WHITE}"
    fi
    echo -e "  ${BOLD}Update Existing Apps${WHITE}  : ${USE_UPDATE}"
    echo -e "  ${BOLD}Skip Subscriptions${WHITE}    : ${SKIP_SUBSCRIPTIONS}"
    echo -e "  ${BOLD}Skip DefaultApp${WHITE}       : ${SKIP_DEFAULT_APP}"
    [ -n "$SINGLE_APP" ] && echo -e "  ${BOLD}Single App Target${WHITE}     : ${CYAN}${SINGLE_APP}${WHITE}"
    [ -n "$FILTER_PATTERN" ] && echo -e "  ${BOLD}Name Regex Filter${WHITE}     : ${CYAN}${FILTER_PATTERN}${WHITE}"
    [ -n "$SOURCE_OWNER_FILTER" ] && echo -e "  ${BOLD}Source Owner Filter${WHITE}   : ${CYAN}${SOURCE_OWNER_FILTER}${WHITE}"
    echo -e "  ${BOLD}Dry-Run Simulation${WHITE}    : ${DRY_RUN}"
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

    # Fetch applications list from source environment
    log progress "Fetching application catalog from source environment '$SRC_ENV' (limit: $LIMIT)..."
    local get_apps_cmd=( "$APICTL41" get apps -e "$SRC_ENV" -l "$LIMIT" --format "{{ jsonPretty . }}" )
    if [ "$INSECURE" = "true" ]; then
        get_apps_cmd+=( -k )
    fi

    local raw_apps_json
    raw_apps_json=$("${get_apps_cmd[@]}" 2>/dev/null) || {
        log failure "Failed to query applications from $SRC_ENV via apictl41."
        exit 1
    }

    # Verify JSON structure
    if [ -z "$raw_apps_json" ]; then
        log warn "No applications found in $SRC_ENV."
        exit 0
    fi

    local total_raw_count
    total_raw_count=$(echo "$raw_apps_json" | jq -s 'length' 2>/dev/null || echo "0")
    if [ "$total_raw_count" -eq 0 ]; then
        log warn "Zero applications returned from $SRC_ENV."
        exit 0
    fi

    log success "Retrieved ${total_raw_count} applications from $SRC_ENV."

    # Prepare directories and audit report
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$AGENT_OUT_DIR" 2>/dev/null || true

    local audit_csv="${OUTPUT_DIR}/wso2_app_migration_${SRC_ENV}_to_${TGT_ENV}_${timestamp}.csv"
    echo "Index,Application Name,Source Owner,Target Owner,Status,Message" > "$audit_csv"

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
    log header "🚀 Beginning Application Migration..."
    log header "============================================================"

    # Process applications stream
    while IFS= read -r app_entry; do
        ((count_discovered++))
        local app_name app_owner app_id
        app_name=$(echo "$app_entry" | jq -r '.Name // empty')
        app_owner=$(echo "$app_entry" | jq -r '.Owner // empty')
        app_id=$(echo "$app_entry" | jq -r '.Id // empty')

        [ -z "$app_name" ] && continue

        # Filter check: Single App
        if [ -n "$SINGLE_APP" ] && [ "$app_name" != "$SINGLE_APP" ]; then
            continue
        fi

        # Filter check: Regex pattern
        if [ -n "$FILTER_PATTERN" ] && ! echo "$app_name" | grep -qE "$FILTER_PATTERN"; then
            continue
        fi

        # Filter check: Source owner
        if [ -n "$SOURCE_OWNER_FILTER" ] && [ "$app_owner" != "$SOURCE_OWNER_FILTER" ]; then
            continue
        fi

        # Skip DefaultApplication if requested
        if [ "$SKIP_DEFAULT_APP" = "true" ] && [ "$app_name" = "DefaultApplication" ]; then
            log info "[$count_discovered/$total_raw_count] Skipping built-in 'DefaultApplication'."
            ((count_skipped++))
            echo "${count_discovered},\"${app_name}\",\"${app_owner}\",\"${TARGET_OWNER}\",SKIPPED,\"Skipped DefaultApplication\"" >> "$audit_csv"
            continue
        fi

        local effective_target_owner
        if [ "$PRESERVE_OWNER" = "true" ]; then
            effective_target_owner="$app_owner"
        else
            effective_target_owner="$TARGET_OWNER"
        fi

        if [ "$DRY_RUN" = "true" ]; then
            log info "[$count_discovered/$total_raw_count] [DRY-RUN] Would migrate '$app_name' (Owner: $app_owner -> $effective_target_owner)"
            ((count_success++))
            echo "${count_discovered},\"${app_name}\",\"${app_owner}\",\"${effective_target_owner}\",DRY_RUN,\"Simulated migration\"" >> "$audit_csv"
            continue
        fi

        echo ""
        log progress "[$count_discovered/$total_raw_count] Processing '$app_name' (Owner: $app_owner -> $effective_target_owner)..."

        # -------------------------------------------------------------
        # Step 1: Export Application from Source Environment with Keys
        # -------------------------------------------------------------
        local export_cmd=( "$APICTL41" export app -n "$app_name" -o "$app_owner" -e "$SRC_ENV" --with-keys )
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
            log failure "Export failed for '$app_name': $err_msg"
            ((count_failed++))
            echo "${count_discovered},\"${app_name}\",\"${app_owner}\",\"${effective_target_owner}\",FAILED,\"Export error: ${err_msg}\"" >> "$audit_csv"
            continue
        fi

        # Resolve exported zip file
        local src_zip_path=""
        if echo "$export_out" | grep -q "Find the exported Application at "; then
            src_zip_path=$(echo "$export_out" | grep "Find the exported Application at " | sed 's/.*Find the exported Application at //')
        fi

        if [ -z "$src_zip_path" ] || [ ! -f "$src_zip_path" ]; then
            src_zip_path="${EXPORTED_BASE_DIR}/${SRC_ENV}/${app_owner}_${app_name}.zip"
        fi

        if [ ! -f "$src_zip_path" ]; then
            log failure "Exported archive file not found at: $src_zip_path"
            ((count_failed++))
            echo "${count_discovered},\"${app_name}\",\"${app_owner}\",\"${effective_target_owner}\",FAILED,\"Archive missing at: ${src_zip_path}\"" >> "$audit_csv"
            continue
        fi

        # -------------------------------------------------------------
        # Step 2: Ensure Keys are Enabled (skipKeys: false) & Repack
        # -------------------------------------------------------------
        local ready_zip_full="${ready_base_dir}/${app_owner}_${app_name}_ready.zip"
        local ready_zip_rel="${ready_subdir}/${app_owner}_${app_name}_ready.zip"

        if ! transform_metadata_and_repack "$src_zip_path" "$ready_zip_full" "$TARGET_OWNER" "$PRESERVE_OWNER"; then
            log failure "Failed to transform metadata for '$app_name'."
            ((count_failed++))
            echo "${count_discovered},\"${app_name}\",\"${app_owner}\",\"${effective_target_owner}\",FAILED,\"Metadata transform failed\"" >> "$audit_csv"
            continue
        fi

        # -------------------------------------------------------------
        # Step 4: Import Application into Target Environment with apictl47
        # -------------------------------------------------------------
        local import_cmd=( "$APICTL47" import app -f "$ready_zip_rel" -e "$TGT_ENV" )

        if [ "$PRESERVE_OWNER" = "true" ]; then
            import_cmd+=( --preserve-owner )
        elif [ -n "$TARGET_OWNER" ]; then
            import_cmd+=( -o "$TARGET_OWNER" )
        fi

        if [ "$USE_UPDATE" = "true" ]; then
            import_cmd+=( --update )
        fi

        if [ "$SKIP_SUBSCRIPTIONS" = "true" ]; then
            import_cmd+=( --skip-subscriptions )
        fi

        if [ "$INSECURE" = "true" ]; then
            import_cmd+=( -k )
        fi

        local import_out import_rc
        import_out=$("${import_cmd[@]}" 2>&1)
        import_rc=$?

        # Validate import output
        if [ $import_rc -eq 0 ] && echo "$import_out" | grep -qi "Successfully imported\|Successfully updated"; then
            log success "Successfully migrated '$app_name' into '$TGT_ENV'."
            ((count_success++))
            echo "${count_discovered},\"${app_name}\",\"${app_owner}\",\"${effective_target_owner}\",SUCCESS,\"Imported successfully\"" >> "$audit_csv"
        elif echo "$import_out" | grep -qi "Status: 500"; then
            # Check for case collision under the same target owner
            local target_existing_name
            target_existing_name=$(find_target_app_by_case_insensitive_name "$TGT_ENV" "$effective_target_owner" "$app_name")

            if [ -n "$target_existing_name" ]; then
                log warn "Case collision detected: '$app_name' matches existing '$target_existing_name' under owner '$effective_target_owner'. Retrying with aligned casing..."
                if transform_metadata_and_repack "$src_zip_path" "$ready_zip_full" "$TARGET_OWNER" "$PRESERVE_OWNER" "$target_existing_name"; then
                    import_out=$("${import_cmd[@]}" 2>&1)
                    import_rc=$?
                fi
            fi

            if [ $import_rc -eq 0 ] && echo "$import_out" | grep -qi "Successfully imported\|Successfully updated"; then
                log success "Successfully migrated '$app_name' into '$TGT_ENV' (aligned casing with '$target_existing_name')."
                ((count_success++))
                echo "${count_discovered},\"${app_name}\",\"${app_owner}\",\"${effective_target_owner}\",SUCCESS,\"Imported successfully with aligned casing (${target_existing_name})\"" >> "$audit_csv"
            else
                local imp_err
                imp_err=$(echo "$import_out" | grep -iE "error|reason|failed" | head -n 2 | tr '\n' ' ' | sed 's/"/""/g')
                [ -z "$imp_err" ] && imp_err=$(echo "$import_out" | head -n 2 | tr '\n' ' ' | sed 's/"/""/g')
                log failure "Import failed for '$app_name': $imp_err"
                ((count_failed++))
                echo "${count_discovered},\"${app_name}\",\"${app_owner}\",\"${effective_target_owner}\",FAILED,\"Import error: ${imp_err}\"" >> "$audit_csv"
            fi
        else
            local imp_err
            if echo "$import_out" | grep -qi "207 Multi-Status"; then
                imp_err="Subscribed APIs missing in target cluster (207 Multi-Status)"
            else
                imp_err=$(echo "$import_out" | grep -iE "error|reason|failed" | head -n 2 | tr '\n' ' ' | sed 's/"/""/g')
                [ -z "$imp_err" ] && imp_err=$(echo "$import_out" | head -n 2 | tr '\n' ' ' | sed 's/"/""/g')
            fi
            log failure "Import failed for '$app_name': $imp_err"
            ((count_failed++))
            echo "${count_discovered},\"${app_name}\",\"${app_owner}\",\"${effective_target_owner}\",FAILED,\"Import error: ${imp_err}\"" >> "$audit_csv"
        fi

        # Cleanup ready zip if requested
        if [ "$KEEP_ARCHIVES" != "true" ] && [ -f "$ready_zip_full" ]; then
            rm -f "$ready_zip_full"
        fi

    done < <(echo "$raw_apps_json" | jq -s -c '.[]')

    # Copy audit log to agent out directory if present
    if [ -d "$AGENT_OUT_DIR" ]; then
        cp -f "$audit_csv" "${AGENT_OUT_DIR}/" 2>/dev/null || true
    fi

    # Display Final Migration Summary
    echo ""
    log header "============================================================"
    log header "📊 Migration Run Summary (${SRC_ENV} -> ${TGT_ENV})"
    log header "============================================================"
    echo -e "  Total Applications Discovered : ${BOLD}${count_discovered}${WHITE}"
    echo -e "  Skipped Applications          : ${CYAN}${count_skipped}${WHITE}"
    echo -e "  Successfully Migrated         : ${GREEN}${count_success}${WHITE}"
    echo -e "  Failed Migrations             : ${RED}${count_failed}${WHITE}"
    echo -e "  Audit Log File                : ${BOLD}${audit_csv}${WHITE}"
    log header "============================================================"

    if [ "$count_failed" -gt 0 ]; then
        log warn "Some applications failed to migrate. Review $audit_csv for failure details."
        exit 1
    else
        log success "All eligible applications migrated successfully!"
        exit 0
    fi
}

main "$@"
