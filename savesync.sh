#!/usr/bin/env bash
set -euo pipefail

declare -A LOCAL_SAVE_MTIME
declare -A LOCAL_MCR_MTIME
declare -A REMOTE_SAVE_MTIME
declare -A REMOTE_MCR_MTIME
declare -A LOCAL_STANDALONE_MTIME
declare -A REMOTE_STANDALONE_MTIME
declare -A SYSTEM_CACHE

if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi

# --- Self-background ---
if [ "${1:-}" != "--bg" ] && [ "${1:-}" != "--scan" ]; then
    nohup "$0" --bg >/dev/null 2>&1 &
    disown
    exit 0
fi

# --- Constants ---
CRD_FILE="/home/ark/.config/savesync.crd"
LOG_FILE="/home/ark/.config/savesync.log"
ES_SYSTEMS="/etc/emulationstation/es_systems.cfg"
RA_CFG="/home/ark/.config/retroarch/retroarch.cfg"
RA64_SAVES="/home/ark/.config/retroarch/saves"
RA32_SAVES="/home/ark/.config/retroarch32/saves"
MOUNT_POINT="/mnt/savesync"
PC_CFG_NAME="savesync.cfg"
CACHE_FILE="/home/ark/.config/savesync.cache"

MEDNAFEN_SYSTEMS="lynx wonderswancolor pcengine pcenginecd nes gb snes gbc gba mastersystem megadrive gamegear ngp ngpc"

STANDALONE_PATHS=(
	"/roms/bios/dc|vmu_save_*.bin *.state"
    "/roms/n64|*.sra *.eep *.fla"
    "/roms/nds/backup|*.dsv"
    "/roms/psp/ppsspp/PSP/SAVEDATA|"
    "/roms/psp/ppsspp/PSP/PPSSPP_STATE|*.ppst"
    "/roms/saturn|*.srm"
)


log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
}


scan_systems() {
    local system file paths=() s
    local exts=(zip chd bin gb gba gbc nes gg sms z64 ngp ngc pce iso 32x sfc wsc \
                n64 v64 nds smc md smd ws lnx cdi gdi cso pbp cue 7z)
    local find_args=() e system location ra64 ra32 hit

    for e in "${exts[@]}"; do
        find_args+=(-iname "*.$e" -o)
    done
    unset 'find_args[${#find_args[@]}-1]'

    : > "$CACHE_FILE"

    while IFS='|' read -r system location ra64 ra32; do
        [ -n "$system" ] && [ -n "$location" ] || continue

        hit=$(find "$location/$system" -mindepth 1 -maxdepth 2 -type f \
              \( "${find_args[@]}" \) -print -quit 2>/dev/null)

        [ -n "$hit" ] && printf '%s|%s\n' "$system" "$location" >> "$CACHE_FILE"
    done < <(awk '
        /<system>/ { name=""; path=""; ra64=0; ra32=0; in_emulators=0 }
        /<name>/ && name=="" { name=$0; sub(/.*<name>/, "", name); sub(/<\/name>.*/, "", name) }
        /<path>/ && path=="" { path=$0; sub(/.*<path>/, "", path); sub(/<\/path>.*/, "", path) }
        /<emulators>/ { in_emulators=1 }
        /<emulator name="retroarch">/ && in_emulators { ra64=1 }
        /<emulator name="retroarch32">/ && in_emulators { ra32=1 }
        /<\/emulators>/ { in_emulators=0 }
        /<\/system>/ {
            if (name != "" && path != "") {
                if (path ~ /^\/roms2\//) location="/roms2"
                else if (path ~ /^\/roms\//) location="/roms"
                else location=""
                print name "|" location "|" ra64 "|" ra32
            }
        }
    ' "$ES_SYSTEMS")
}

build_remote_mtime_cache() {
    local record path mtime rel system file maxdepth paths=() s

    REMOTE_SAVE_MTIME=()
    REMOTE_MCR_MTIME=()
	REMOTE_STANDALONE_MTIME=()
	
    if [ "$USECONTENTFOLDER" = "true" ]; then
        maxdepth=3
    else
        maxdepth=2
    fi

    for s in "${!SYSTEM_CACHE[@]}"; do
        paths+=("$MOUNT_POINT/$s")
    done

    if [ "${#paths[@]}" -eq 0 ]; then
        return 0
    fi

    while IFS= read -r -d '' record; do
        mtime="${record%% *}"
        path="${record#* }"

        rel="${path#"$MOUNT_POINT"/}"

        [[ "$rel" == */* ]] || continue

        system="${rel%%/*}"
        [ -n "$system" ] || continue

        file="${rel#*/}"

        # Normal saves must be directly inside the system directory,
        # or inside system/system when content-folder mode is enabled.
        if [ "$USECONTENTFOLDER" = "false" ]; then
            [[ "$file" != */* ]] || continue
        else
            [[ "$file" == "$system/"* ]] || continue
            file="${file#*/}"
            [[ "$file" != */* ]] || continue
        fi

        mtime="${mtime%.*}"

		if [[ "$file" == *.mcr ]]; then
			if (( ${REMOTE_MCR_MTIME[$system]:-0} < mtime )); then
				REMOTE_MCR_MTIME["$system"]="$mtime"
			fi

		elif [[ "$file" == *.srm || "$file" == *.sav || "$file" == *.state* ]]; then
			if (( ${REMOTE_SAVE_MTIME[$system]:-0} < mtime )); then
				REMOTE_SAVE_MTIME["$system"]="$mtime"
			fi

		elif [[ "$file" == *.sra || "$file" == *.eep || "$file" == *.fla ]]; then
			if (( ${REMOTE_STANDALONE_MTIME["$system|*.sra *.eep *.fla"]:-0} < mtime )); then
				REMOTE_STANDALONE_MTIME["$system|*.sra *.eep *.fla"]="$mtime"
			fi

		elif [[ "$file" == *.dsv ]]; then
			if (( ${REMOTE_STANDALONE_MTIME["$system|*.dsv"]:-0} < mtime )); then
				REMOTE_STANDALONE_MTIME["$system|*.dsv"]="$mtime"
			fi

		elif [[ "$file" == *.ppst ]]; then
			if (( ${REMOTE_STANDALONE_MTIME["$system|*.ppst"]:-0} < mtime )); then
				REMOTE_STANDALONE_MTIME["$system|*.ppst"]="$mtime"
			fi
		fi
    done < <(
        find "${paths[@]}" \
            -mindepth 1 \
            -maxdepth "$((maxdepth - 1))" \
			-type f \
            \( -name '*.srm' -o -name '*.sav' -o -name '*.state*' -o -name '*.mcr' \) \
            -printf '%T@ %p\0'
    )
}

build_local_mtime_cache() {
    local record path mtime rel system file current

    LOCAL_SAVE_MTIME=()
    LOCAL_MCR_MTIME=()
    LOCAL_STANDALONE_MTIME=()

    # Normal RetroArch saves
    while IFS= read -r -d '' record; do
        mtime="${record%% *}"
        path="${record#* }"

        rel="${path#/roms2/}"
        system="${rel%%/*}"

        [ -n "$system" ] || continue

        file="${rel#*/}"

        [[ "$file" == "$system/"* ]] || continue
        file="${file#*/}"
        [[ "$file" != */* ]] || continue

        mtime="${mtime%.*}"

        if [[ "$file" == *.mcr ]]; then
            current="${LOCAL_MCR_MTIME[$system]-0}"
            (( current < mtime )) && LOCAL_MCR_MTIME["$system"]="$mtime"
        elif [[ "$file" == *.srm || "$file" == *.sav || "$file" == *.state* ]]; then
            current="${LOCAL_SAVE_MTIME[$system]-0}"
            (( current < mtime )) && LOCAL_SAVE_MTIME["$system"]="$mtime"
        fi
    done < <(
        find /roms2 \
            -mindepth 3 -maxdepth 3 \
            \( -name '*.srm' -o -name '*.sav' -o -name '*.state*' -o -name '*.mcr' \) \
            -printf '%T@ %p\0'
    )

    # Standalone save locations
    local src patterns key

    while IFS='|' read -r src patterns; do
        [ -d "$src" ] || continue

        system="${src##*/}"
        key="$system|$patterns"

        while IFS= read -r -d '' record; do
            mtime="${record%% *}"
            mtime="${mtime%.*}"

            current="${LOCAL_STANDALONE_MTIME[$key]-0}"
            (( current < mtime )) && LOCAL_STANDALONE_MTIME["$key"]="$mtime"
        done < <(
            find "$src" \
                -maxdepth 1 \
                \( -name '*.sra' -o -name '*.eep' -o -name '*.fla' \
                   -o -name '*.dsv' \
                   -o -name '*.ppst' \
                   -o -name '*.mcr' \) \
                -printf '%T@ %p\0'
        )
    done < <(
        printf '%s\n' \
            '/roms/n64|*.sra *.eep *.fla' \
            '/roms/nds/backup|*.dsv' \
            '/roms/psp/ppsspp/PSP/PPSSPP_STATE|*.ppst'
    )
}

latest_mtime() {
    local dir="$1" patterns="$2" pat f latest=0 t

    [ -d "$dir" ] || {
        echo 0
        return
    }

    for pat in $patterns; do
        for f in "$dir"/$pat; do
            [ -e "$f" ] || continue
            t=$(stat -c '%Y' "$f" 2>/dev/null) || continue
            [ "$t" -gt "$latest" ] && latest="$t"
        done
    done

    echo "$latest"
}

remote_mtime() {
    local dir="$1" patterns="$2"
    local system="${dir#"$MOUNT_POINT"/}"

    system="${system%%/*}"

    if [ "$patterns" = "*.mcr" ]; then
        printf '%s\n' "${REMOTE_MCR_MTIME[$system]-0}"
    elif [ "$patterns" = "*.srm *.sav *.state*" ]; then
        printf '%s\n' "${REMOTE_SAVE_MTIME[$system]-0}"
    else
        latest_mtime "$dir" "$patterns"
    fi
}

local_mtime() {
    local dir="$1" patterns="$2"
    local system="${dir#/roms2/}"
    system="${system%%/*}"

    if [ "$patterns" = "*.mcr" ]; then
        if [[ -v "LOCAL_MCR_MTIME[$system]" ]]; then
            printf '%s\n' "${LOCAL_MCR_MTIME[$system]}"
        else
            printf '%s\n' 0
        fi
    elif [ "$patterns" = "*.srm *.sav *.state*" ]; then
        if [[ -v "LOCAL_SAVE_MTIME[$system]" ]]; then
            printf '%s\n' "${LOCAL_SAVE_MTIME[$system]}"
        else
            printf '%s\n' 0
        fi
    else
        latest_mtime "$dir" "$patterns"
    fi
}

sync_dir() {
    local src="$1" dst="$2" patterns="$3" filter="${4:-}"
    local src_m dst_m pat rsync_opts=()

    if [ -n "$filter" ]; then
        for pat in $filter; do
            rsync_opts+=(--include="$pat")
        done
        rsync_opts+=(--exclude='*')
    fi

    # Local filesystem: cheap direct stat/glob check.
    src_m=$(local_mtime "$src" "$patterns")

    # PC/SMB filesystem: use the cache built by one find pass.
    if [[ "$dst" == "$MOUNT_POINT/"* ]]; then
        dst_m=$(remote_mtime "$dst" "$patterns")
    else
        dst_m=$(latest_mtime "$dst" "$patterns")
    fi

    if [ "$src_m" -eq 0 ] && [ "$dst_m" -eq 0 ]; then
        return 0
    elif [ "$dst_m" -eq 0 ]; then
        mkdir -p "$dst" || {
            log "ERROR: mkdir failed for $dst"
            return
        }

        log "Copying (console->PC): $src -> $dst"

        rsync -au --no-owner --no-group \
            "${rsync_opts[@]}" \
            "$src/" "$dst/" >> "$LOG_FILE" 2>&1

    elif [ "$src_m" -eq 0 ]; then
        mkdir -p "$src" || {
            log "ERROR: mkdir failed for $src"
            return
        }

        log "Copying (PC->console): $dst -> $src"

        rsync -au --no-owner --no-group \
            "${rsync_opts[@]}" \
            "$dst/" "$src/" >> "$LOG_FILE" 2>&1

    elif [ "$src_m" -ne "$dst_m" ]; then
        log "Syncing (2 way): $src -> $dst, $dst -> $src"

        rsync -au --no-owner --no-group \
            "${rsync_opts[@]}" \
            "$src/" "$dst/" >> "$LOG_FILE" 2>&1

        rsync -au --no-owner --no-group \
            "${rsync_opts[@]}" \
            "$dst/" "$src/" >> "$LOG_FILE" 2>&1
    fi
}

sync_standalone() {
    local src="$1"
    local filter="$2"
    local rel="${src#/roms2/}"
    rel="${rel#/roms/}"
    local dst="$MOUNT_POINT/$rel"
    local src_m=0 dst_m=0
    local pat first=1
    local find_args

    [ -d "$src" ] || mkdir -p "$src"
    [ -d "$dst" ] || mkdir -p "$dst"

    # Build a shallow find for the requested standalone files.
    # Empty filter means the entire directory.
    find_args=("$src" -mindepth 1 -maxdepth 1)

    if [ -n "$filter" ]; then
        find_args+=(\( )
        for pat in $filter; do
            (( first )) || find_args+=(-o)
            find_args+=(-name "$pat")
            first=0
        done
        find_args+=(\))
    fi

    while IFS= read -r mtime; do
        mtime="${mtime%.*}"
        (( mtime > src_m )) && src_m="$mtime"
    done < <(find "${find_args[@]}" -printf '%T@\n' 2>/dev/null)

    # Same check on the remote directory.
    find_args=("$dst" -mindepth 1 -maxdepth 1)
    first=1

    if [ -n "$filter" ]; then
        find_args+=(\( )
        for pat in $filter; do
            (( first )) || find_args+=(-o)
            find_args+=(-name "$pat")
            first=0
        done
        find_args+=(\))
    fi

    while IFS= read -r mtime; do
        mtime="${mtime%.*}"
        (( mtime > dst_m )) && dst_m="$mtime"
    done < <(find "${find_args[@]}" -printf '%T@\n' 2>/dev/null)

    # Nothing exists on either side.
    if [ "$src_m" -eq 0 ] && [ "$dst_m" -eq 0 ]; then
        return 0
    fi

    # Only local exists.
    if [ "$dst_m" -eq 0 ]; then
        log "Syncing standalone: $src -> $dst (filter: ${filter:-all})"

        if [ -n "$filter" ]; then
            local include_args=()
            for pat in $filter; do
                include_args+=(--include="$pat")
            done
            rsync -au --no-owner --no-group \
                "${include_args[@]}" --exclude='*' \
                "$src/" "$dst/" >> "$LOG_FILE" 2>&1
        else
            rsync -au --no-owner --no-group \
                "$src/" "$dst/" >> "$LOG_FILE" 2>&1
        fi
        return
    fi

    # Only remote exists.
    if [ "$src_m" -eq 0 ]; then
        log "Syncing standalone: $dst -> $src (filter: ${filter:-all})"

        if [ -n "$filter" ]; then
            local include_args=()
            for pat in $filter; do
                include_args+=(--include="$pat")
            done
            rsync -au --no-owner --no-group \
                "${include_args[@]}" --exclude='*' \
                "$dst/" "$src/" >> "$LOG_FILE" 2>&1
        else
            rsync -au --no-owner --no-group \
                "$dst/" "$src/" >> "$LOG_FILE" 2>&1
        fi
        return
    fi

    # Newest timestamp differs: preserve the original two-way sync behavior.
    if [ "$src_m" -ne "$dst_m" ]; then
        log "Syncing standalone: $src <-> $dst (filter: ${filter:-all})"

        if [ -n "$filter" ]; then
            local include_args=()
            for pat in $filter; do
                include_args+=(--include="$pat")
            done

            rsync -au --no-owner --no-group \
                "${include_args[@]}" --exclude='*' \
                "$src/" "$dst/" >> "$LOG_FILE" 2>&1

            rsync -au --no-owner --no-group \
                "${include_args[@]}" --exclude='*' \
                "$dst/" "$src/" >> "$LOG_FILE" 2>&1
        else
            rsync -au --no-owner --no-group \
                "$src/" "$dst/" >> "$LOG_FILE" 2>&1

            rsync -au --no-owner --no-group \
                "$dst/" "$src/" >> "$LOG_FILE" 2>&1
        fi
    fi
}

mount_smb() {
    local network_ip mount_err

    if [[ "$HOST" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        network_ip="$HOST"
    else
        network_ip=$(nmblookup "$HOST" 2>/dev/null |
            grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' |
            head -n 1)
    fi

    if [[ -z "$network_ip" ]]; then
        log "ERROR: could not resolve NetBIOS name: $HOST"
        exit 1
    fi

    mount_err=$(mount -t cifs "//$network_ip/$NETWORKPATH" "$MOUNT_POINT" \
        -o username="$USERNAME",password="$PASSWORD",vers=3.0,uid=$(id -u),gid=$(id -g) \
        2>&1 1>/dev/null) || {
        case "$mount_err" in
            *"error(13)"*)  log "ERROR: authentication failed for //$HOST/$NETWORKPATH — check USERNAME/PASSWORD in $CRD_FILE" ;;
            *"error(2)"*)   log "ERROR: share or path not found at //$HOST/$NETWORKPATH — check NETWORKPATH in $CRD_FILE" ;;
            *"error(101)"*) log "ERROR: network unreachable — check HOST and console network connection" ;;
            *"error(110)"*) log "ERROR: connection timed out reaching $HOST — PC may be off or unreachable" ;;
            *"error(111)"*) log "ERROR: connection refused by $HOST — check SMB/file sharing is enabled on PC" ;;
            *)              log "ERROR: mount failed for //$HOST/$NETWORKPATH — $mount_err" ;;
        esac
        exit 1
    }

    log "Mounted //$HOST/$NETWORKPATH at $MOUNT_POINT"
}

mount_nfs() {
    local mount_err

    mount_err=$(LC_ALL=C mount -t nfs "$HOST:$NETWORKPATH" "$MOUNT_POINT" 2>&1 1>/dev/null) || {
        case "$mount_err" in
            *"access denied"*)              log "ERROR: access denied by NFS server $HOST — check export settings" ;;
            *"Connection refused"*)         log "ERROR: connection refused by $HOST — check the NFS service is running" ;;
            *"timed out"*|*"Timeout"*)      log "ERROR: connection timed out reaching $HOST — PC may be off or unreachable" ;;
            *"No such file or directory"*)  log "ERROR: NFS export not found at $HOST:$NETWORKPATH — check NETWORKPATH" ;;
            *)                              log "ERROR: NFS mount failed for $HOST:$NETWORKPATH — $mount_err" ;;
        esac
        exit 1
    }

    log "Mounted $HOST:$NETWORKPATH at $MOUNT_POINT"
}

mount_sshfs() {
    local mount_err

    if ! command -v sshfs >/dev/null 2>&1 || ! command -v sshpass >/dev/null 2>&1; then
        log "ERROR: sshfs/sshpass not installed"
        exit 1
    fi

    mount_err=$(LC_ALL=C SSHPASS="$PASSWORD" sshfs "$USERNAME@$HOST:$NETWORKPATH" "$MOUNT_POINT" \
        -o "ssh_command=sshpass -e ssh,uid=$(id -u),gid=$(id -g),StrictHostKeyChecking=no,reconnect" \
        2>&1 1>/dev/null) || {
        case "$mount_err" in
            *"Permission denied"*|*"authentication failed"*) log "ERROR: authentication failed for $USERNAME@$HOST — check USERNAME/PASSWORD in $CRD_FILE" ;;
            *"Connection refused"*)                          log "ERROR: connection refused by $HOST — check the SSH service is running" ;;
            *"timed out"*|*"Timeout"*)                       log "ERROR: connection timed out reaching $HOST — PC may be off or unreachable" ;;
            *"No such file or directory"*)                   log "ERROR: remote path not found at $HOST:$NETWORKPATH — check NETWORKPATH" ;;
            *)                                                log "ERROR: SSHFS mount failed for $USERNAME@$HOST:$NETWORKPATH — $mount_err" ;;
        esac
        exit 1
    }

    log "Mounted $USERNAME@$HOST:$NETWORKPATH at $MOUNT_POINT"
}

mount_webdav() {
    local base webdav_url secrets="/etc/davfs2/secrets" tmp="/etc/davfs2/secrets.tmp" conf="/etc/davfs2/davfs2.conf" mount_err

    if ! command -v mount.davfs >/dev/null 2>&1; then
        log "ERROR: mount.davfs not installed"
        exit 1
    fi

    case "$HOST" in
        http://*|https://*) base="$HOST" ;;
        *)                  base="http://$HOST" ;;
    esac
    webdav_url="${base%/}/${NETWORKPATH#/}"

    mkdir -p "$(dirname "$secrets")"
    touch "$secrets"
    grep -v "^${MOUNT_POINT} " "$secrets" > "$tmp" 2>/dev/null || true
    printf '%s "%s" "%s"\n' "$MOUNT_POINT" "$USERNAME" "$PASSWORD" >> "$tmp"
    mv -f "$tmp" "$secrets"
    chmod 600 "$secrets"

    if [ -f "$conf" ] && grep -q '^use_locks' "$conf"; then
        sed -i 's/^use_locks.*/use_locks 0/' "$conf"
    else
        printf 'use_locks 0\n' >> "$conf"
    fi

    mount_err=$(LC_ALL=C mount -t davfs "$webdav_url" "$MOUNT_POINT" \
        -o uid=$(id -u),gid=$(id -g) 2>&1 1>/dev/null) || {
        case "$mount_err" in
            *"authentication"*|*"401"*)                                    log "ERROR: authentication failed for $webdav_url — check USERNAME/PASSWORD in $CRD_FILE" ;;
            *"could not connect"*|*"Connection refused"*|*"timed out"*|*"Timeout"*) log "ERROR: connection failed reaching $HOST — PC may be off or unreachable" ;;
            *"resolved"*|*"not known"*)                                    log "ERROR: could not resolve host $HOST — check HOST in $CRD_FILE" ;;
            *"404"*|*"not found"*)                                         log "ERROR: WebDAV path not found at $webdav_url — check NETWORKPATH" ;;
            *)                                                              log "ERROR: WebDAV mount failed for $webdav_url — $mount_err" ;;
        esac
        exit 1
    }

    log "Mounted $webdav_url at $MOUNT_POINT"
}

if [ "${1:-}" = "--scan" ]; then
    scan_systems
    exit 0
fi

[ -f "$CACHE_FILE" ] || scan_systems

# --- Network check ---
if ! ip route show default 2>/dev/null | grep -q default; then
    log "ERROR: no network connection detected (no default route)"
    exit 1
fi

# --- Load console credentials (parsed, not sourced: values may
#     contain shell metacharacters) ---
if [ ! -f "$CRD_FILE" ]; then
    log "ERROR: credential file not found at $CRD_FILE"
    exit 1
fi

PROTOCOL="" HOST="" USERNAME="" PASSWORD="" NETWORKPATH=""
while IFS= read -r line || [ -n "$line" ]; do
    key="${line%%=*}"
    [ "$key" = "$line" ] && continue
    value="${line#*=}"
    case "$key" in
        PROTOCOL|HOST|USERNAME|PASSWORD|NETWORKPATH)
            printf -v "$key" '%s' "$value"
            ;;
    esac
done < "$CRD_FILE"

[ -n "$PROTOCOL" ] || PROTOCOL="smb"

case "$PROTOCOL" in
    smb|nfs|sshfs|webdav) ;;
    *)
        log "ERROR: unsupported protocol: $PROTOCOL (expected smb, nfs, sshfs or webdav)"
        exit 1
        ;;
esac

if [ -z "$HOST" ] || [ -z "$NETWORKPATH" ]; then
    log "ERROR: missing required field(s) HOST/NETWORKPATH in $CRD_FILE"
    exit 1
fi
if [ "$PROTOCOL" != "nfs" ] && { [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; }; then
    log "ERROR: missing required field(s) USERNAME/PASSWORD in $CRD_FILE"
    exit 1
fi

# --- Mount PC share ---
mkdir -p "$MOUNT_POINT"

if ! mountpoint -q "$MOUNT_POINT"; then
    case "$PROTOCOL" in
        smb)    mount_smb ;;
        nfs)    mount_nfs ;;
        sshfs)  mount_sshfs ;;
        webdav) mount_webdav ;;
    esac
fi

# --- Read PC-side config ---
PC_CFG="$MOUNT_POINT/$PC_CFG_NAME"

if [ ! -f "$PC_CFG" ]; then
    log "ERROR: PC config not found at $PC_CFG"
    umount "$MOUNT_POINT"
    exit 1
fi

USECONTENTFOLDER=$( { grep -E '^USECONTENTFOLDER=' "$PC_CFG" || true; } | cut -d'=' -f2 | tr -d '[:space:]')

if [[ "$USECONTENTFOLDER" != "true" && "$USECONTENTFOLDER" != "false" ]]; then
    log "ERROR: invalid or missing UseContentFolder in $PC_CFG — expected true or false"
    umount "$MOUNT_POINT"
    exit 1
fi

while IFS='|' read -r system location; do
    [ -n "$system" ] || continue
    SYSTEM_CACHE["$system"]="$location"
done < "$CACHE_FILE"

# --- Build the PC-side mtime cache once ---
build_local_mtime_cache
build_remote_mtime_cache

# --- Determine console's current active save mode ---
CONTENT_MODE=$( { grep '^savefiles_in_content_dir' "$RA_CFG" || true; } | grep -o 'true\|false')

# --- Sync every system listed in es_systems.cfg ---
while IFS='|' read -r SYSTEM LOCATION RA64_ENABLED RA32_ENABLED; do
    [[ -v "SYSTEM_CACHE[$SYSTEM]" ]] || continue
		
    # Resolve console source dir
    if [ "$CONTENT_MODE" = "true" ]; then
        [ -n "$LOCATION" ] || continue
        SRC_DIR="$LOCATION/$SYSTEM/$SYSTEM"
    else
        if [ "$RA64_ENABLED" = "1" ]; then
            SRC_DIR="$RA64_SAVES/$SYSTEM"
        elif [ "$RA32_ENABLED" = "1" ]; then
            SRC_DIR="$RA32_SAVES/$SYSTEM"
        else
            continue
        fi
    fi

    # Resolve PC target dir
    if [ "$USECONTENTFOLDER" = "true" ]; then
        DST_DIR="$MOUNT_POINT/$SYSTEM/$SYSTEM"
    else
        DST_DIR="$MOUNT_POINT/$SYSTEM"
    fi

    sync_dir "$SRC_DIR" "$DST_DIR" "*.srm *.sav *.state*"

    # Mednafen save sync (.mcr, same dir as ROMs, flat mirror)
    if [ -n "$LOCATION" ] && [[ " $MEDNAFEN_SYSTEMS " == *" $SYSTEM "* ]]; then
        sync_standalone "$LOCATION/$SYSTEM" "*.mcr"
    fi

done < <(awk '
    /<system>/ { name=""; path=""; ra64=0; ra32=0; in_emulators=0 }
    /<name>/ && name=="" {
        name=$0; sub(/.*<name>/, "", name); sub(/<\/name>.*/, "", name)
    }
    /<path>/ && path=="" {
        path=$0; sub(/.*<path>/, "", path); sub(/<\/path>.*/, "", path)
    }
    /<emulators>/ { in_emulators=1 }
    /<emulator name="retroarch">/ && in_emulators { ra64=1 }
    /<emulator name="retroarch32">/ && in_emulators { ra32=1 }
    /<\/emulators>/ { in_emulators=0 }
    /<\/system>/ {
        if (name != "" && path != "") {
            if (path ~ /^\/roms2\//) location="/roms2"
            else if (path ~ /^\/roms\//) location="/roms"
            else location=""
            print name "|" location "|" ra64 "|" ra32
        }
    }
' "$ES_SYSTEMS")

# --- Sync standalone emulator saves (flat mirror) ---
for entry in "${STANDALONE_PATHS[@]}"; do
    SA_SRC="${entry%%|*}"
    SA_FILTER="${entry#*|}"
    sync_standalone "$SA_SRC" "$SA_FILTER"
done

# --- Unmount ---
umount "$MOUNT_POINT"
log "Sync complete, unmounted $MOUNT_POINT"
