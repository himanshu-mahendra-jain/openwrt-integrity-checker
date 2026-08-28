#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
ROUTERS=(
    "root@192.168.1.1"
    "root@192.168.1.2"
    "root@192.168.1.3"
)

BASELINE="${1:-./known-good}"

SSH_KEY="$HOME/.ssh/openwrt"

# Start SSH agent and load OpenWrt key
eval "$(ssh-agent -s)"
ssh-add "$SSH_KEY"

# OpenWrt SSH private key
SSH_OPTS=(
    -i "$SSH_KEY"
    -o IdentitiesOnly=yes
)

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_WARN=0

# ------------------------------------------------------------
# Functions
# ------------------------------------------------------------
pass() {
    echo "✓ PASS: $*"
    TOTAL_PASS=$((TOTAL_PASS + 1))
}

fail() {
    echo "✗ FAIL: $*"
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
}

warn() {
    echo "! WARN: $*"
    TOTAL_WARN=$((TOTAL_WARN + 1))
}

verify_router() {
    local ROUTER="$1"
    local NAME="$2"
    local DIR="$BASELINE/$NAME"

    echo
    echo "========================================"
    echo " Router:   $ROUTER"
    echo " Baseline: $DIR"
    echo "========================================"
    echo

    # --------------------------------------------------------
    # Check baseline
    # --------------------------------------------------------
    [[ -d "$DIR" ]] || {
        fail "$NAME: baseline directory does not exist"
        return
    }

    # --------------------------------------------------------
    # SSH connectivity
    # --------------------------------------------------------
    echo "[1/6] SSH connectivity"

    if ssh "${SSH_OPTS[@]}" \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        "$ROUTER" true 2>/dev/null; then

        echo "✓ SSH connection successful"
    else
        fail "$NAME: SSH connection failed"
        return
    fi

    # --------------------------------------------------------
    # System information
    # --------------------------------------------------------
    echo "[2/6] System information"

    if [[ -f "$DIR/system.txt" ]]; then

        CURRENT_SYSTEM="$(
            ssh "${SSH_OPTS[@]}" "$ROUTER" '
                echo "### /etc/openwrt_release"
                cat /etc/openwrt_release 2>/dev/null || true
                echo
                echo "### uname"
                uname -a
            '
        )"

        if diff -u "$DIR/system.txt" \
            <(printf '%s\n' "$CURRENT_SYSTEM") \
            > /tmp/openwrt-system-diff 2>&1; then

            pass "$NAME: system information"

        else
            fail "$NAME: system information differs"
            cat /tmp/openwrt-system-diff
        fi

    else
        warn "$NAME: system.txt baseline missing"
    fi

    # --------------------------------------------------------
    # Critical file hashes
    # --------------------------------------------------------
    echo "[3/6] Critical file hashes"

    if [[ -f "$DIR/files.sha256" ]]; then

        CURRENT_HASHES="$(
            ssh "${SSH_OPTS[@]}" "$ROUTER" '
                while IFS= read -r line; do
                    [ -n "$line" ] || continue

                    file="${line#*  }"

                    if [ -f "$file" ]; then
                        sha256sum -- "$file"
                    else
                        printf "%s  %s\n" \
                            "MISSING" \
                            "$file"
                    fi
                done
            ' < "$DIR/files.sha256"
        )"

        if diff -u "$DIR/files.sha256" \
            <(printf '%s\n' "$CURRENT_HASHES") \
            > /tmp/openwrt-hash-diff 2>&1; then

            pass "$NAME: critical file hashes"

        else
            fail "$NAME: critical file hash mismatch"
            cat /tmp/openwrt-hash-diff
        fi

    else
        warn "$NAME: files.sha256 baseline missing"
    fi

    # --------------------------------------------------------
    # Installed packages
    # --------------------------------------------------------
    echo "[4/6] Installed packages"

    if [[ -f "$DIR/packages.txt" ]]; then

        CURRENT_PACKAGES="$(
            ssh "${SSH_OPTS[@]}" "$ROUTER" \
                'apk list --installed 2>/dev/null | sort'
        )"

        if diff -u "$DIR/packages.txt" \
            <(printf '%s\n' "$CURRENT_PACKAGES") \
            > /tmp/openwrt-package-diff 2>&1; then

            pass "$NAME: installed packages"

        else
            fail "$NAME: installed packages differ"
            cat /tmp/openwrt-package-diff
        fi

    else
        warn "$NAME: packages.txt baseline missing"
    fi

    # --------------------------------------------------------
    # UID 0 accounts
    # --------------------------------------------------------
    echo "[5/6] UID 0 accounts"

    if [[ -f "$DIR/uid0.txt" ]]; then

        CURRENT_UID0="$(
            ssh "${SSH_OPTS[@]}" "$ROUTER" \
                "awk -F: '\$3 == 0 {print \$1}' /etc/passwd"
        )"

        if diff -u "$DIR/uid0.txt" \
            <(printf '%s\n' "$CURRENT_UID0") \
            > /tmp/openwrt-uid0-diff 2>&1; then

            pass "$NAME: UID 0 accounts"

        else
            fail "$NAME: UID 0 accounts differ"
            cat /tmp/openwrt-uid0-diff
        fi

    else
        warn "$NAME: uid0.txt baseline missing"
    fi

    # --------------------------------------------------------
    # SSH authorized keys
    # --------------------------------------------------------
    echo "[6/6] SSH authorized keys"

    if [[ -f "$DIR/authorized_keys" ]]; then

        CURRENT_KEYS="$(
            ssh "${SSH_OPTS[@]}" "$ROUTER" '
                for f in \
                    /root/.ssh/authorized_keys \
                    /etc/dropbear/authorized_keys
                do
                    if [ -f "$f" ]; then
                        echo "### $f"
                        cat "$f"
                    fi
                done
            '
        )"

        if diff -u "$DIR/authorized_keys" \
            <(printf '%s\n' "$CURRENT_KEYS") \
            > /tmp/openwrt-key-diff 2>&1; then

            pass "$NAME: SSH authorized keys"

        else
            fail "$NAME: SSH authorized keys differ"
            cat /tmp/openwrt-key-diff
        fi

    else
        warn "$NAME: authorized_keys baseline missing"
    fi

    # --------------------------------------------------------
    # Cron configuration
    # --------------------------------------------------------
    echo
    echo "[Persistence] Cron configuration"

    if [[ -f "$DIR/crontabs.txt" ]]; then

        CURRENT_CRON="$(
            ssh "${SSH_OPTS[@]}" "$ROUTER" '
                for f in /etc/crontabs/*; do
                    [ -f "$f" ] || continue

                    echo "### $f"
                    cat "$f"
                done
            '
        )"

        if diff -u "$DIR/crontabs.txt" \
            <(printf '%s' "$CURRENT_CRON") \
            > /tmp/openwrt-cron-diff 2>&1; then

            pass "$NAME: cron configuration"

        else
            fail "$NAME: cron configuration differs"
            cat /tmp/openwrt-cron-diff
        fi

    else
        warn "$NAME: crontabs.txt baseline missing"
    fi
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
echo "========================================"
echo " OpenWrt Multi-Router Integrity Check"
echo "========================================"
echo
echo "Baseline directory: $BASELINE"

[[ -d "$BASELINE" ]] || {
    echo
    echo "ERROR: Baseline directory not found: $BASELINE"
    exit 1
}

for i in "${!ROUTERS[@]}"; do
    verify_router \
        "${ROUTERS[$i]}" \
        "router-$((i + 1))"
done

echo
echo "========================================"
echo " Overall Result"
echo "========================================"
echo
echo "PASS: $TOTAL_PASS"
echo "FAIL: $TOTAL_FAIL"
echo "WARN: $TOTAL_WARN"
echo

if (( TOTAL_FAIL > 0 )); then
    echo "RESULT: MODIFICATION DETECTED"
    exit 2

elif (( TOTAL_WARN > 0 )); then
    echo "RESULT: BASELINE INCOMPLETE"
    exit 1

else
    echo "RESULT: ALL CHECKS PASSED"
    exit 0
fi
