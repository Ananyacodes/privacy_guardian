#!/bin/bash
# update-trackers.sh — Privacy Guardian v2.1
# Safely updates tracker IP sets in nftables with:
#   - Atomic swap (no protection gap during update)
#   - Full error handling (never wipes set on failure)
#   - Input validation (no shell injection from upstream)
#   - Logging via syslog
#   - Retry logic for transient network failures

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────
BLOCKLIST_URL="https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level1.netset"
TMPDIR_BASE="/tmp/pg-tracker-update"
LOG_TAG="privacy-guardian"
MAX_RETRIES=3
RETRY_DELAY=10  # seconds between retries
MIN_ENTRIES=100  # sanity check — abort if parsed list is suspiciously small
MIN_IPV6_ENTRIES=10  # keep existing IPv6 set if upstream provides too few entries

# ─── Logging ─────────────────────────────────────────────────────────────────
log()  { logger -t "$LOG_TAG" "$1"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
warn() { logger -t "$LOG_TAG" -p user.warning "WARNING: $1"; echo "[WARN] $1" >&2; }
die()  { logger -t "$LOG_TAG" -p user.error "ERROR: $1"; echo "[ERROR] $1" >&2; exit 1; }

# ─── Dependency check ─────────────────────────────────────────────────────────
for cmd in curl nft grep awk mktemp; do
    command -v "$cmd" &>/dev/null || die "Required command not found: $cmd"
done

# ─── Temp directory setup ─────────────────────────────────────────────────────
TMPDIR=$(mktemp -d "${TMPDIR_BASE}.XXXXXX")
trap 'rm -rf "$TMPDIR"' EXIT  # Always clean up temp files

BLOCKLIST_FILE="$TMPDIR/blocklist.txt"
IPV4_PARSED="$TMPDIR/ipv4_parsed.txt"
IPV6_PARSED="$TMPDIR/ipv6_parsed.txt"
NFT_BATCH="$TMPDIR/tracker_update_batch.nft"

# ─── Safe download with retry ─────────────────────────────────────────────────
safe_download() {
    local url="$1"
    local outfile="$2"
    local label="$3"
    local attempt=0

    while [ $attempt -lt $MAX_RETRIES ]; do
        attempt=$((attempt + 1))
        log "Downloading $label (attempt $attempt/$MAX_RETRIES)..."

        if curl \
            --silent \
            --show-error \
            --fail \
            --max-time 30 \
            --retry 2 \
            --output "$outfile" \
            "$url"; then

            # Validate file is non-empty
            if [ ! -s "$outfile" ]; then
                warn "$label download succeeded but file is empty"
                rm -f "$outfile"
            else
                log "$label downloaded successfully ($(wc -l < "$outfile") lines)"
                return 0
            fi
        else
            warn "$label download failed (attempt $attempt)"
        fi

        [ $attempt -lt $MAX_RETRIES ] && sleep $RETRY_DELAY
    done

    return 1
}

# ─── IP validation ────────────────────────────────────────────────────────────
is_valid_ipv4() {
    local ip="$1"
    # Strict IPv4 validation — no CIDR ranges in this check
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
        # Check each octet is <= 255
        local IFS='.'
        local -a octets
        read -ra octets <<< "${ip%%/*}"
        for octet in "${octets[@]}"; do
            [ "$octet" -gt 255 ] && return 1
        done
        # Reject private/loopback/multicast ranges — blocking these would break LAN
        [[ "$ip" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.|169\.254\.|224\.|240\.) ]] && return 1
        return 0
    fi
    return 1
}

is_valid_ipv6() {
    local ip="$1"
    # Basic IPv6 validation (including CIDR)
    [[ "$ip" =~ ^[0-9a-fA-F:]+(/[0-9]{1,3})?$ ]] || return 1
    # Reject loopback and link-local
    [[ "$ip" =~ ^(::1|fe80:) ]] && return 1
    return 0
}

# ─── Parse IPs from downloaded blocklists ─────────────────────────────────────

# NOTE: Steven Black hosts file is DOMAIN-based, not IP-based.
# We resolve a curated subset to IPs rather than parsing the hosts file directly.
# For pure IP-based blocking, we use the FireHOL Level 1 blocklist instead,
# which is maintained specifically as an IP reputation list.

parse_firehol_ipv4() {
    local infile="$1"
    grep -v '^#' "$infile" \
        | grep -v '^$' \
        | awk '{print $1}' \
        | while IFS= read -r entry; do
            if is_valid_ipv4 "$entry"; then
                echo "$entry"
            fi
          done
}

parse_firehol_ipv6() {
    local infile="$1"
    grep -v '^#' "$infile" \
        | grep -v '^$' \
        | awk '{print $1}' \
        | while IFS= read -r entry; do
            if is_valid_ipv6 "$entry"; then
                echo "$entry"
            fi
          done
}

# ─── Build and apply one atomic nft batch ─────────────────────────────────────
build_and_apply_batch() {
    local ipv4_list="$1"
    local ipv6_list="$2"
    local update_ipv6="$3"

    {
        echo "# Privacy Guardian tracker update batch — generated $(date)"
        echo "flush set inet filter tracker_ips"
        echo "add element inet filter tracker_ips {"
        awk '
            BEGIN { c = 0; line = "    " }
            {
                line = line (c > 0 ? ", " : "") $0
                c++
                if (c == 4) {
                    print line
                    c = 0
                    line = "    "
                }
            }
            END {
                if (c > 0) print line
            }
        ' "$ipv4_list"
        echo "}"

        if [ "$update_ipv6" = "1" ]; then
            echo ""
            echo "flush set inet filter tracker_ips6"
            echo "add element inet filter tracker_ips6 {"
            awk '
                BEGIN { c = 0; line = "    " }
                {
                    line = line (c > 0 ? ", " : "") $0
                    c++
                    if (c == 4) {
                        print line
                        c = 0
                        line = "    "
                    }
                }
                END {
                    if (c > 0) print line
                }
            ' "$ipv6_list"
            echo "}"
        fi
    } > "$NFT_BATCH"

    log "Validating nft batch update..."
    nft --check -f "$NFT_BATCH" || die "nft batch validation failed — keeping existing sets"

    log "Applying nft batch update atomically..."
    nft -f "$NFT_BATCH" || die "Failed to apply nft batch"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    log "=== Privacy Guardian tracker update started ==="

    # Download FireHOL Level 1 IP blocklist (IP-native, well-maintained)
    if ! safe_download "$BLOCKLIST_URL" "$BLOCKLIST_FILE" "FireHOL Level 1"; then
        die "All download attempts failed. Keeping existing tracker set unchanged."
    fi

    # Parse and validate IPs
    parse_firehol_ipv4 "$BLOCKLIST_FILE" > "$IPV4_PARSED"
    parse_firehol_ipv6 "$BLOCKLIST_FILE" > "$IPV6_PARSED"

    local ipv4_count ipv6_count
    ipv4_count=$(wc -l < "$IPV4_PARSED")
    ipv6_count=$(wc -l < "$IPV6_PARSED")
    log "Parsed $ipv4_count valid IPv4 entries after validation"
    log "Parsed $ipv6_count valid IPv6 entries after validation"

    if [ "$ipv4_count" -lt "$MIN_ENTRIES" ]; then
        die "Too few valid IPv4 IPs parsed ($ipv4_count). Possible upstream issue. Aborting."
    fi

    local update_ipv6=0
    if [ "$ipv6_count" -ge "$MIN_IPV6_ENTRIES" ]; then
        update_ipv6=1
        log "IPv6 set update enabled ($ipv6_count entries)"
    else
        warn "IPv6 parsed entries too low ($ipv6_count < $MIN_IPV6_ENTRIES). Keeping existing tracker_ips6 unchanged."
    fi

    # Apply in one nft transaction to avoid protection gaps
    build_and_apply_batch "$IPV4_PARSED" "$IPV6_PARSED" "$update_ipv6"

    local final_v4 final_v6
    final_v4=$(nft list set inet filter tracker_ips | grep -c '\.' || echo 0)
    final_v6=$(nft list set inet filter tracker_ips6 | grep -c ':' || echo 0)
    log "Update complete. Live tracker_ips entries: ~$final_v4, tracker_ips6 entries: ~$final_v6"

    log "=== Privacy Guardian tracker update complete ==="
}

main "$@"
