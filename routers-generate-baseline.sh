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

SSH_OPTS=(
    -i "$SSH_KEY"
    -o IdentitiesOnly=yes
)

# ------------------------------------------------------------
# Functions
# ------------------------------------------------------------
error() {
    echo
    echo "ERROR: $*"
    echo
    exit 1
}

generate_baseline() {
    local ROUTER="$1"
    local NAME="$2"
    local DIR="$BASELINE/$NAME"

    mkdir -p "$DIR"

    echo
    echo "========================================"
    echo " Router:   $ROUTER"
    echo " Baseline: $DIR"
    echo "========================================"
    echo

    # --------------------------------------------------------
    # System information
    # --------------------------------------------------------
    echo "[1/6] System information"

    ssh "${SSH_OPTS[@]}" "$ROUTER" '
        echo "### /etc/openwrt_release"
        cat /etc/openwrt_release 2>/dev/null || true
        echo
        echo "### uname"
        uname -a
    ' > "$DIR/system.txt"

    # --------------------------------------------------------
    # Critical file hashes
    # --------------------------------------------------------
    echo "[2/6] Critical file hashes"

    ssh "${SSH_OPTS[@]}" "$ROUTER" '
        {
            find \
                /etc/config \
                /etc/init.d \
                /etc/rc.d \
                /etc/crontabs \
                /etc/dropbear \
                -type f -print 2>/dev/null

            printf "%s\n" \
                /etc/passwd \
                /etc/shadow \
                /etc/group \
                /etc/hosts \
                /etc/rc.local \
                /etc/firewall.user
        } |
        sort -u |
        while IFS= read -r file; do
            [ -n "$file" ] || continue

            if [ -f "$file" ]; then
                sha256sum -- "$file"
            fi
        done
    ' > "$DIR/files.sha256"

    # Verify that hashes were actually generated
    [[ -s "$DIR/files.sha256" ]] ||
        error "No file hashes were generated for $ROUTER."

    # --------------------------------------------------------
    # Installed packages
    # --------------------------------------------------------
    echo "[3/6] Installed packages"

    ssh "${SSH_OPTS[@]}" "$ROUTER" \
        'apk list --installed 2>/dev/null | sort' \
        > "$DIR/packages.txt"

    [[ -s "$DIR/packages.txt" ]] ||
        error "Could not obtain package list from $ROUTER."

    # --------------------------------------------------------
    # UID 0 accounts
    # --------------------------------------------------------
    echo "[4/6] UID 0 accounts"

    ssh "${SSH_OPTS[@]}" "$ROUTER" \
        "awk -F: '\$3 == 0 {print \$1}' /etc/passwd" \
        > "$DIR/uid0.txt"

    [[ -s "$DIR/uid0.txt" ]] ||
        error "Could not obtain UID 0 accounts from $ROUTER."

    # --------------------------------------------------------
    # SSH authorized keys
    # --------------------------------------------------------
    echo "[5/6] SSH authorized keys"

    ssh "${SSH_OPTS[@]}" "$ROUTER" '
        found=0

        for f in \
            /root/.ssh/authorized_keys \
            /etc/dropbear/authorized_keys
        do
            if [ -f "$f" ]; then
                echo "### $f"
                cat "$f"
                found=1
            fi
        done

        [ "$found" -eq 1 ] || true
    ' > "$DIR/authorized_keys"

    # --------------------------------------------------------
    # Cron configuration
    # --------------------------------------------------------
    echo "[6/6] Cron configuration"

    ssh "${SSH_OPTS[@]}" "$ROUTER" '
        for f in /etc/crontabs/*; do
            [ -f "$f" ] || continue

            echo "### $f"
            cat "$f"
        done
    ' > "$DIR/crontabs.txt"

    # --------------------------------------------------------
    # Summary
    # --------------------------------------------------------
    echo
    echo "✓ $NAME baseline complete"
    echo
    echo "Files:"
    ls -lh "$DIR"
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
echo "========================================"
echo " OpenWrt Multi-Router Baseline"
echo "========================================"
echo
echo "Baseline directory: $BASELINE"

mkdir -p "$BASELINE"

for i in "${!ROUTERS[@]}"; do
    generate_baseline \
        "${ROUTERS[$i]}" \
        "router-$((i + 1))"
done

echo
echo "========================================"
echo " All baselines generated"
echo "========================================"
echo

find "$BASELINE" -maxdepth 2 -type f -print | sort

echo
echo "IMPORTANT:"
echo "Only generate these baselines when the routers"
echo "are known to be clean."
echo
