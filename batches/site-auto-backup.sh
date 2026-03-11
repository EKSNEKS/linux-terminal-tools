#!/usr/bin/env bash

set -u
set -o pipefail

DB_USER="${DB_USER:-root}"
MYSQL_BIN="${MYSQL_BIN:-mysql}"
MYSQLDUMP_BIN="${MYSQLDUMP_BIN:-mysqldump}"
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/var/backups/missiria-auto}"
BACKUP_RETENTION_RUNS="${BACKUP_RETENTION_RUNS:-${BACKUP_RETENTION_DAYS:-15}}"

if [[ -t 1 ]]; then
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    RED=$'\033[0;31m'
    CYAN=$'\033[0;36m'
    BLUE=$'\033[0;34m'
    NC=$'\033[0m'
else
    GREEN=""
    YELLOW=""
    RED=""
    CYAN=""
    BLUE=""
    NC=""
fi

declare -A ROOT_DOMAINS=()
declare -A ROOT_SOURCE=()
declare -A ROOT_SEEN=()

declare -a SUCCESS_SITES=()
declare -a FAILED_SITES=()
declare -a SKIPPED_SITES=()
declare -a REMOVED_BACKUP_RUNS=()
declare -a FAILED_BACKUP_REMOVALS=()

print_header() {
    printf '%b\n' "${CYAN}______  ____________________________________________________${NC}"
    printf '%b\n' "${CYAN}___   |/  /___  _/_  ___/_  ___/___  _/__  __ \\___  _/__    |${NC}"
    printf '%b\n' "${CYAN}__  /|_/ / __  / _____ \\_____ \\ __  / __  /_/ /__  / __  /| |${NC}"
    printf '%b\n' "${CYAN}_  /  / / __/ /  ____/ /____/ /__/ /  _  _, _/__/ /  _  ___ |${NC}"
    printf '%b\n' "${CYAN}/_/  /_/  /___/  /____/ /____/ /___/  /_/ |_| /___/  /_/  |_|${NC}"
    printf '%b\n' "${CYAN}                                                             v2${NC}"
    printf '%b\n' "${GREEN}ACTIVE SITE AUTO BACKUP${NC}"
}

log_info() {
    printf '%b\n' "${BLUE}$*${NC}"
}

log_ok() {
    printf '%b\n' "${GREEN}$*${NC}"
}

log_warn() {
    printf '%b\n' "${YELLOW}$*${NC}"
}

log_error() {
    printf '%b\n' "${RED}$*${NC}" >&2
}

sql_escape_literal() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\'/\'\'}"
    printf '%s' "$value"
}

mysql_exec() {
    "$MYSQL_BIN" -u "$DB_USER" "$@"
}

database_exists() {
    local db_name="$1"
    local db_escaped result

    db_escaped="$(sql_escape_literal "$db_name")"
    result="$(
        mysql_exec -N -s -e "
            SELECT SCHEMA_NAME
            FROM information_schema.SCHEMATA
            WHERE SCHEMA_NAME='${db_escaped}'
            LIMIT 1;
        " 2>/dev/null || true
    )"
    [[ "$result" == "$db_name" ]]
}

sanitize_name() {
    printf '%s' "$1" \
        | LC_ALL=C tr '[:upper:]' '[:lower:]' \
        | LC_ALL=C sed 's/[^[:alnum:]._-]/_/g'
}

primary_domain() {
    local domains_csv="$1"
    local domain

    IFS=',' read -r -a domain_list <<< "$domains_csv"
    for domain in "${domain_list[@]}"; do
        if [[ "$domain" != www.* ]]; then
            printf '%s\n' "$domain"
            return 0
        fi
    done

    printf '%s\n' "${domain_list[0]}"
}

collect_nginx_files() {
    local -n out_files_ref="$1"

    shopt -s nullglob
    out_files_ref=(/etc/nginx/sites-enabled/*)
    shopt -u nullglob

    if ((${#out_files_ref[@]} == 0)); then
        log_error "No Nginx files found in /etc/nginx/sites-enabled/."
        return 1
    fi
}

collect_domain_root_pairs() {
    local -a nginx_files=()

    collect_nginx_files nginx_files || return 1

    awk '
        function clean(v) {
            gsub(/;|"/, "", v)
            gsub(/\047/, "", v)
            return v
        }
        function count_char(str, ch,    tmp) {
            tmp = str
            return gsub(ch, "", tmp)
        }
        function flush_block() {
            if (!in_server) {
                return
            }
            if (root != "" && domain_count > 0) {
                for (i = 1; i <= domain_count; i++) {
                    print root "|" domains[i] "|" FILENAME
                }
            }
            delete domains
            domain_count = 0
            root = ""
        }
        /^[[:space:]]*server[[:space:]]*\{/ {
            flush_block()
            in_server = 1
            depth = 1
            next
        }
        in_server {
            if ($0 ~ /^[[:space:]]*server_name[[:space:]]+/) {
                for (i = 2; i <= NF; i++) {
                    d = clean($i)
                    if (d != "" && d != "_" && d !~ /^~/) {
                        domains[++domain_count] = d
                    }
                }
            } else if ($0 ~ /^[[:space:]]*root[[:space:]]+/) {
                r = clean($2)
                if (r ~ /^\//) {
                    root = r
                }
            }

            depth += count_char($0, "{")
            depth -= count_char($0, "}")
            if (depth <= 0) {
                flush_block()
                in_server = 0
                depth = 0
            }
            next
        }
        END {
            flush_block()
        }
    ' "${nginx_files[@]}" | sort -u
}

extract_wp_db_name() {
    local wp_config="$1"

    LC_ALL=C sed -nE "s/^[[:space:]]*define[[:space:]]*\([[:space:]]*['\"]DB_NAME['\"][[:space:]]*,[[:space:]]*['\"]([^'\"]+)['\"][[:space:]]*\)[[:space:]]*;?.*$/\1/p" "$wp_config" | head -n 1
}

write_metadata() {
    local metadata_file="$1"
    local backup_time="$2"
    local root="$3"
    local domains="$4"
    local nginx_conf="$5"
    local app_type="$6"
    local files_archive="$7"
    local db_name="$8"
    local db_archive="$9"

    {
        printf 'backup_time=%s\n' "$backup_time"
        printf 'site_root=%s\n' "$root"
        printf 'domains=%s\n' "$domains"
        printf 'nginx_conf=%s\n' "$nginx_conf"
        printf 'type=%s\n' "$app_type"
        printf 'files_archive=%s\n' "$files_archive"
        printf 'database_name=%s\n' "$db_name"
        printf 'database_archive=%s\n' "$db_archive"
    } > "$metadata_file"
}

cleanup_old_backups() {
    local backup_dir backup_name remove_count
    local -a all_runs=()
    local -a sorted_runs=()

    if ! [[ "$BACKUP_RETENTION_RUNS" =~ ^[0-9]+$ ]]; then
        log_warn "Skipping retention cleanup: BACKUP_RETENTION_RUNS must be numeric."
        return 0
    fi

    if ((BACKUP_RETENTION_RUNS < 1)); then
        log_warn "Skipping retention cleanup: BACKUP_RETENTION_RUNS must be at least 1."
        return 0
    fi

    while IFS= read -r -d '' backup_dir; do
        backup_name="$(basename "$backup_dir")"
        [[ "$backup_name" =~ ^[0-9]{8}_[0-9]{6}$ ]] || continue
        all_runs+=("$backup_dir")
    done < <(
        find "$BACKUP_BASE_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null
    )

    if ((${#all_runs[@]} <= BACKUP_RETENTION_RUNS)); then
        log_info "Retention cleanup: keeping ${#all_runs[@]} backup run(s), limit is ${BACKUP_RETENTION_RUNS}."
        return 0
    fi

    mapfile -t sorted_runs < <(
        for backup_dir in "${all_runs[@]}"; do
            printf '%s\t%s\n' "$(basename "$backup_dir")" "$backup_dir"
        done | sort | cut -f2-
    )

    remove_count=$((${#sorted_runs[@]} - BACKUP_RETENTION_RUNS))
    log_warn "Retention cleanup: keeping the latest ${BACKUP_RETENTION_RUNS} backup run(s), removing ${remove_count} older run(s)..."

    for ((i = 0; i < remove_count; i++)); do
        backup_dir="${sorted_runs[$i]}"
        if rm -rf "$backup_dir"; then
            REMOVED_BACKUP_RUNS+=("$backup_dir")
            log_ok "✓ Removed old backup: $backup_dir"
        else
            FAILED_BACKUP_REMOVALS+=("$backup_dir")
            log_error "✗ Failed to remove old backup: $backup_dir"
        fi
    done
}

backup_site() {
    local root="$1"
    local domains="$2"
    local nginx_conf="$3"
    local run_dir="$4"
    local site_start site_end duration backup_time
    local label safe_label site_dir files_archive metadata_file
    local app_type="app"
    local db_name=""
    local db_archive=""
    local db_status="Not applicable"
    local file_status="FAILED"
    local status_ok=0

    if [[ ! -d "$root" ]]; then
        SKIPPED_SITES+=("$root | Missing directory | Domains: $domains")
        log_warn "[SKIP] $root (directory does not exist)"
        return 0
    fi

    label="$(primary_domain "$domains")"
    safe_label="$(sanitize_name "$label")"
    site_dir="${run_dir}/${safe_label}"
    files_archive="${site_dir}/files.tar.gz"
    metadata_file="${site_dir}/backup-info.txt"

    site_start=$(date +%s)
    backup_time=$(date '+%Y/%m/%d %H:%M:%S')

    log_warn ""
    log_warn "▶ Backing up: ${label}"
    log_info "Root: ${root}"
    log_info "Domains: ${domains}"

    if ! mkdir -p "$site_dir"; then
        FAILED_SITES+=("$root | Cannot create backup directory $site_dir")
        log_error "✗ Backup failed: cannot create $site_dir"
        return 0
    fi

    if tar -czf "$files_archive" -C "$(dirname "$root")" "$(basename "$root")"; then
        file_status="OK"
        status_ok=1
    else
        FAILED_SITES+=("$label | Files backup failed for $root")
        log_error "✗ Files backup failed for ${root}"
        write_metadata "$metadata_file" "$backup_time" "$root" "$domains" "$nginx_conf" "$app_type" "$files_archive" "$db_name" "$db_archive"
        return 0
    fi

    if [[ -f "$root/wp-config.php" ]]; then
        app_type="wordpress"
        db_name="$(extract_wp_db_name "$root/wp-config.php")"

        if [[ -z "$db_name" ]]; then
            db_status="FAILED (DB_NAME not found in wp-config.php)"
            status_ok=0
        elif ! database_exists "$db_name"; then
            db_status="FAILED (database ${db_name} not found)"
            status_ok=0
        else
            db_archive="${site_dir}/${db_name}.sql.gz"
            if "$MYSQLDUMP_BIN" -u "$DB_USER" "$db_name" | gzip -c > "$db_archive"; then
                db_status="OK (${db_name})"
            else
                db_status="FAILED (mysqldump error for ${db_name})"
                status_ok=0
            fi
        fi
    fi

    write_metadata "$metadata_file" "$backup_time" "$root" "$domains" "$nginx_conf" "$app_type" "$files_archive" "$db_name" "$db_archive"

    site_end=$(date +%s)
    duration=$((site_end - site_start))

    if [[ "$status_ok" -eq 1 ]]; then
        SUCCESS_SITES+=("$label | ${root} | Files: ${file_status} | DB: ${db_status}")
        log_ok "✓ BACKUP DONE in ${duration}s | Files: ${file_status} | DB: ${db_status}"
        printf '  Backed up at: %s\n' "$backup_time"
    else
        FAILED_SITES+=("$label | ${root} | Files: ${file_status} | DB: ${db_status}")
        log_error "✗ BACKUP INCOMPLETE in ${duration}s | Files: ${file_status} | DB: ${db_status}"
        printf '  Attempted at: %s\n' "$backup_time"
    fi
}

main() {
    local global_start global_end total_time
    local run_stamp run_dir
    local pair root domain source
    local domains_csv

    print_header
    printf '\n'

    global_start=$(date +%s)
    run_stamp="$(date +%Y%m%d_%H%M%S)"
    run_dir="${BACKUP_BASE_DIR%/}/${run_stamp}"

    if ! mkdir -p "$run_dir"; then
        log_error "Cannot create backup base directory: $run_dir"
        return 1
    fi

    while IFS='|' read -r root domain source; do
        [[ -z "$root" || -z "$domain" || -z "$source" ]] && continue

        if [[ "$root" != /var/www/* && "$root" != "/var/www" ]]; then
            SKIPPED_SITES+=("$root | Outside /var/www | Domains: $domain")
            continue
        fi

        if [[ -z "${ROOT_SEEN[$root]:-}" ]]; then
            ROOT_SEEN[$root]=1
            ROOT_DOMAINS[$root]="$domain"
            ROOT_SOURCE[$root]="$source"
            continue
        fi

        domains_csv="${ROOT_DOMAINS[$root]}"
        case ",${domains_csv}," in
            *,"$domain",*) ;;
            *) ROOT_DOMAINS[$root]="${domains_csv},${domain}" ;;
        esac
    done < <(collect_domain_root_pairs)

    if ((${#ROOT_SEEN[@]} == 0)); then
        log_warn "No active Nginx roots found under /var/www."
        return 0
    fi

    log_info "Backup directory: ${run_dir}"
    log_info "Detected ${#ROOT_SEEN[@]} active root(s) from Nginx under /var/www."

    while IFS= read -r root; do
        backup_site "$root" "${ROOT_DOMAINS[$root]}" "${ROOT_SOURCE[$root]}" "$run_dir"
    done < <(printf '%s\n' "${!ROOT_SEEN[@]}" | sort)

    cleanup_old_backups

    global_end=$(date +%s)
    total_time=$((global_end - global_start))

    printf '\n'
    log_ok "======================================================"
    log_ok " BACKUP RUN FINISHED IN ${total_time} SECONDS"
    log_ok " Run folder: ${run_dir}"
    log_ok "======================================================"

    if ((${#SUCCESS_SITES[@]} > 0)); then
        printf '\n'
        log_ok "Successful backups:"
        printf '%s\n' "${SUCCESS_SITES[@]}"
    fi

    if ((${#FAILED_SITES[@]} > 0)); then
        printf '\n'
        log_error "Failed or incomplete backups:"
        printf '%s\n' "${FAILED_SITES[@]}"
    fi

    if ((${#SKIPPED_SITES[@]} > 0)); then
        printf '\n'
        log_warn "Skipped roots:"
        printf '%s\n' "${SKIPPED_SITES[@]}"
    fi

    if ((${#REMOVED_BACKUP_RUNS[@]} > 0)); then
        printf '\n'
        log_ok "Removed old backup runs:"
        printf '%s\n' "${REMOVED_BACKUP_RUNS[@]}"
    fi

    if ((${#FAILED_BACKUP_REMOVALS[@]} > 0)); then
        printf '\n'
        log_error "Failed old backup removals:"
        printf '%s\n' "${FAILED_BACKUP_REMOVALS[@]}"
    fi
}

main "$@"
