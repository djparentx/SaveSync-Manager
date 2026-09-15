#!/bin/bash

# =======================================
# SaveSync Manager v1.1
# by djparent
# =======================================

# Copyright (c) 2026 djparent
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# =======================================================
# Root privileges check
# =======================================================
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi

# =======================================================
# Initialization
# =======================================================
export TERM=linux

# =======================================================
# Variables
# =======================================================
GPTOKEYB_PID=""
CURR_TTY="/dev/tty1"
TMP_KEYS="/tmp/keys.gptk.$$"
ES_SYSTEMS="/etc/emulationstation/es_systems.cfg"
CRD_FILE="/home/ark/.config/savesync.crd"
SYNC_SCRIPT="/usr/local/bin/savesync.sh"
FLAG_FILE="/home/ark/.savesync"
FS_FLAG="/home/ark/.config/.fastsync"
GAMEEND_HOOK="/home/ark/.emulationstation/scripts/game-end/savesync.sh"
GAMESTART_HOOK="/home/ark/.emulationstation/scripts/game-start/savesync.sh"
SERVICE_FILE="/etc/systemd/system/savesync.service"
LOG_FILE="/home/ark/.config/savesync.log"
RA64="/home/ark/.config/retroarch"
RA32="/home/ark/.config/retroarch32"
RA64_CFG="$RA64/retroarch.cfg"
RA32_CFG="$RA32/retroarch.cfg"

T_BACKTITLE="SaveSync Manager v1.1 by djparent"
T_STARTING="Starting $T_BACKTITLE please wait..."
T_MAIN_TITLE="Main Menu"
T_LOG_TITLE="Log Menu"
T_WAIT="Please wait..."
T_EXIT="Exit"
T_SSYNC="SaveSync"
T_CRED="Enter Credentials"
T_MANUAL="Synchronize Now"
T_VIEW_LOG="View Log"
T_CLEAR_LOG="Clear Log"
T_LOG_CLEARED="Log cleared."
T_NO_LOG="No log file found."
T_IP="Host"
T_NAME="Username"
T_PASS="Password"
T_PATH="Network Path"
T_SELECT="Please make a selection:"
T_UNINSTALL="Uninstall SaveSync"
T_INSTALL="Install SaveSync"
T_SS_INSTALL="SaveSync installed."
T_SS_UNINSTALL="SaveSync uninstalled."
T_NO_INSTALL="Unable to install required network support."
T_SUCCESS="Success!"
T_FAILED="Failed."
T_NO_DETAILS="No error details were recorded."
T_PROTOCOL="Protocol Menu"
T_CACHE="Rebuild Folder Cache"
T_SAVE_LOCATION="Save Location"
T_LOCATION="Current location:"
T_CONTENT_FOLDER="content folders"
T_SAVE_FOLDER="saves folder"
T_SAVE="Retroarch Folder (/retroarch/saves)"
T_FOLDER="Game Content Folders (/roms/gb)"
T_MIGRATION_COMPLETE="Save migration complete"
T_NO_MIGRATE="Nothing to migrate."
T_MIGRATE="Migrate from ArkOS"
T_STATUS="Choose new location for game saves:"
T_SURE="Are you sure?"
T_COPY="Copying files..."
T_FS_ON="Fast Sync On"
T_FS_OFF="Fast Sync Off"

# =======================================================
# Start gamepad input
# =======================================================
Start_GPTKeyb() {
    pkill -9 -f gptokeyb 2>/dev/null || true
    if [ -n "${GPTOKEYB_PID:-}" ]; then
        kill "$GPTOKEYB_PID" 2>/dev/null
    fi
    sleep 0.1
	/opt/inttools/gptokeyb -1 "$0" -c "$TMP_KEYS" > /dev/null 2>&1 &
    GPTOKEYB_PID=$!
}

# =======================================================
# Stop gamepad input
# =======================================================
Stop_GPTKeyb() {
    if [ -n "$GPTOKEYB_PID" ]; then
        kill "$GPTOKEYB_PID" 2>/dev/null
        GPTOKEYB_PID=""
    fi
}

# =======================================================
# Font Selection
# =======================================================
ORIGINAL_FONT=$(setfont -v 2>&1 | grep -o '/.*\.psf.*')
setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz

# =======================================================
# Display Management
# =======================================================
printf "\e[?25l" > "$CURR_TTY"
dialog --clear
Stop_GPTKeyb
pgrep -f osk.py | xargs kill -9
printf "\033[H\033[2J" > "$CURR_TTY"
printf "$T_STARTING" > "$CURR_TTY"
sleep 0.5

# =======================================================
# Exit the script
# =======================================================
Exit_Menu() {
	trap - EXIT
    printf "\033[H\033[2J" > "$CURR_TTY"
    printf "\e[?25h" > "$CURR_TTY"
	Stop_GPTKeyb
    rm -f "$TMP_KEYS"
    if [[ ! -e "/dev/input/by-path/platform-odroidgo2-joypad-event-joystick" ]]; then
        [ -n "$ORIGINAL_FONT" ] && setfont "$ORIGINAL_FONT"
    fi

    exit 0
}

# =======================================================
# Saves Folder
# =======================================================
Saves_Folder() {
	dialog --backtitle "$T_BACKTITLE" --infobox "\n    $T_WAIT" 5 40 2>&1 > "$CURR_TTY"

	sed -i \
	  -e 's|^[[:space:]]*savefiles_in_content_dir[[:space:]]*=.*|savefiles_in_content_dir = "false"|' \
	  -e 's|^[[:space:]]*savestates_in_content_dir[[:space:]]*=.*|savestates_in_content_dir = "false"|' \
	  -e 's|^[[:space:]]*screenshots_in_content_dir[[:space:]]*=.*|screenshots_in_content_dir = "false"|' \
	  -e 's|^[[:space:]]*sort_savefiles_by_content_enable[[:space:]]*=.*|sort_savefiles_by_content_enable = "true"|' \
	  -e 's|^[[:space:]]*sort_savestates_by_content_enable[[:space:]]*=.*|sort_savestates_by_content_enable = "true"|' \
	  -e 's|^[[:space:]]*sort_screenshots_by_content_enable[[:space:]]*=.*|sort_screenshots_by_content_enable = "true"|' \
	  "$RA64_CFG"

    mkdir -p "$RA64/saves" "$RA64/states"
    mkdir -p "$RA32/saves" "$RA32/states"

    awk '
        /<system>/ {
            name=""
            path=""
            ra64=0
            ra32=0
            in_emulators=0
        }

        /<name>/ && name=="" {
            name=$0
            sub(/.*<name>/, "", name)
            sub(/<\/name>.*/, "", name)
        }

        /<path>/ && path=="" {
            path=$0
            sub(/.*<path>/, "", path)
            sub(/<\/path>.*/, "", path)
        }

        /<emulators>/ {
            in_emulators=1
        }

        /<emulator name="retroarch">/ && in_emulators {
            ra64=1
        }

        /<emulator name="retroarch32">/ && in_emulators {
            ra32=1
        }

        /<\/emulators>/ {
            in_emulators=0
        }

        /<\/system>/ {
            if (name != "" && path != "") {

                if (path ~ /^\/roms2\//)
                    location="/roms2"
                else if (path ~ /^\/roms\//)
                    location="/roms"
                else
                    location=""

                if (location != "")
                    print name "|" location "|" ra64 "|" ra32
            }
        }
    ' "$ES_SYSTEMS" |
    while IFS='|' read -r SYSTEM LOCATION RA64_ENABLED RA32_ENABLED; do

        SYSTEM_DIR="$LOCATION/$SYSTEM/$SYSTEM"

        [ -d "$SYSTEM_DIR" ] || continue

		dialog --backtitle "$T_BACKTITLE" --infobox "\n    $T_COPY" 5 40 2>&1 > "$CURR_TTY"
		# sleep 0.05
		
        # RA64
        if [ "$RA64_ENABLED" = "1" ]; then
            for FILE in "$SYSTEM_DIR"/*.srm; do
                [ -f "$FILE" ] || continue
                mkdir -p "$RA64/saves/$SYSTEM"
                cp -au "$FILE" "$RA64/saves/$SYSTEM/"
            done
            for FILE in "$SYSTEM_DIR"/*.state "$SYSTEM_DIR"/*.state.auto; do
                [ -f "$FILE" ] || continue
                mkdir -p "$RA64/states/$SYSTEM"
                cp -au "$FILE" "$RA64/states/$SYSTEM/"
            done
        fi

        # RA32
        if [ "$RA32_ENABLED" = "1" ]; then
            for FILE in "$SYSTEM_DIR"/*.srm; do
                [ -f "$FILE" ] || continue
                mkdir -p "$RA32/saves/$SYSTEM"
                cp -au "$FILE" "$RA32/saves/$SYSTEM/"
            done
            for FILE in "$SYSTEM_DIR"/*.state "$SYSTEM_DIR"/*.state.auto; do
                [ -f "$FILE" ] || continue
                mkdir -p "$RA32/states/$SYSTEM"
                cp -au "$FILE" "$RA32/states/$SYSTEM/"
            done
        fi
    done
}

# =======================================================
# Content Folder
# =======================================================
Content_Folders() {
	dialog --backtitle "$T_BACKTITLE" --infobox "\n    $T_WAIT" 5 40 2>&1 > "$CURR_TTY"
	  
	sed -i \
	  -e 's|^[[:space:]]*savefiles_in_content_dir[[:space:]]*=.*|savefiles_in_content_dir = "true"|' \
	  -e 's|^[[:space:]]*savestates_in_content_dir[[:space:]]*=.*|savestates_in_content_dir = "true"|' \
	  -e 's|^[[:space:]]*screenshots_in_content_dir[[:space:]]*=.*|screenshots_in_content_dir = "true"|' \
	  -e 's|^[[:space:]]*sort_savefiles_by_content_enable[[:space:]]*=.*|sort_savefiles_by_content_enable = "true"|' \
	  -e 's|^[[:space:]]*sort_savestates_by_content_enable[[:space:]]*=.*|sort_savestates_by_content_enable = "true"|' \
	  -e 's|^[[:space:]]*sort_screenshots_by_content_enable[[:space:]]*=.*|sort_screenshots_by_content_enable = "true"|' \
	  "$RA64_CFG"

    for RA_DIR in "$RA64" "$RA32"; do
        for TYPE in saves states; do

            [ -d "$RA_DIR/$TYPE" ] || continue

            for SYSTEM_DIR in "$RA_DIR/$TYPE"/*; do
                [ -d "$SYSTEM_DIR" ] || continue

                SYSTEM="$(basename "$SYSTEM_DIR")"

				LOCATION=$(awk -v sys="$SYSTEM" '
					/<path>/ {
						path=$0
						sub(/.*<path>/, "", path)
						sub(/<\/path>.*/, "", path)

						gsub(/\/+$/, "", path)

						if (tolower(path) ~ "/roms2/" tolower(sys) "$") {
							print "/roms2"
							exit
						}

						if (tolower(path) ~ "/roms/" tolower(sys) "$") {
							print "/roms"
							exit
						}
					}
				' "$ES_SYSTEMS")

                [ -n "$LOCATION" ] || continue
				
				dialog --backtitle "$T_BACKTITLE" --infobox "\n    $T_COPY" 5 40 2>&1 > "$CURR_TTY"
				# sleep 0.05
				
				DEST="$LOCATION/$SYSTEM/$SYSTEM"
				mkdir -p "$DEST"
                cp -au "$SYSTEM_DIR/." "$DEST/"
				
            done
        done
    done
}

# =======================================================
# Migrate Saves
# =======================================================
Migrate_Saves() {
    local checks=(
        'sort_savefiles_by_content_enable = "false"'
        'sort_savestates_by_content_enable = "false"'
        'sort_screenshots_by_content_enable = "false"'
        'savefiles_in_content_dir = "true"'
        'savestates_in_content_dir = "true"'
        'screenshots_in_content_dir = "true"'
    )

    for check in "${checks[@]}"; do
        grep -qF "$check" "$RA64_CFG" || { dialog --msgbox "$T_NO_MIGRATE" 6 30; return 1; }
    done

    dialog --yesno "$T_SURE" 6 30 || return 0

    while IFS= read -r -d '' block; do
        local name path subdir
        name=$(grep -oP '(?<=<name>).*?(?=</name>)' <<< "$block" | head -1)
        path=$(grep -oP '(?<=<path>).*?(?=</path>)' <<< "$block" | head -1)
        path="${path/#\~/$HOME}"
        [ -z "$name" ] && continue
        [ -d "$path" ] || continue

        subdir="$path/$name"
        mkdir -p "$subdir"

        find "$path" -maxdepth 1 -type f \( \
            -name "*.srm" -o -name "*.state" -o -name "*.state[0-9]*" \
            -o -name "*.state.auto" -o -name "*.png" -o -name "*.rtc" \
            -o -name "*.bsv" \) -print0 | \
        while IFS= read -r -d '' f; do
            mv -n "$f" "$subdir/"
        done
    done < <(awk 'BEGIN{RS="<system>";ORS=""} NR>1{n=index($0,"</system>"); print substr($0,1,n+9) "\x00"}' "$ES_SYSTEMS")

    sed -i \
        -e 's/sort_savefiles_by_content_enable = "false"/sort_savefiles_by_content_enable = "true"/' \
        -e 's/sort_savestates_by_content_enable = "false"/sort_savestates_by_content_enable = "true"/' \
        -e 's/sort_screenshots_by_content_enable = "false"/sort_screenshots_by_content_enable = "true"/' \
        "$RA64_CFG" "$RA32_CFG"

    dialog --msgbox "$T_MIGRATION_COMPLETE" 6 30
}

# =======================================================
# Credential file helpers (KEY=VALUE lines)
# =======================================================
OSK_VALUE=""
OSK_RC=0

OSK_Prompt() {
    pkill -9 -f gptokeyb 2>/dev/null || true
    OSK_VALUE=$(osk "$1" | tail -n 1)
    OSK_RC=${PIPESTATUS[0]}
    Start_GPTKeyb
    setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz
}

CRD_Prompt() {
    local key="$1" prompt="$2" mode="${3:-empty_ok}"
    OSK_Prompt "$prompt"
    if [[ "$mode" == "cancel_ok" ]]; then
        [[ $OSK_RC -eq 0 ]] || return 0
    else
        [[ -n "$OSK_VALUE" ]] || return 0
    fi
    CRD_Set "$key" "$OSK_VALUE"
}

CRD_Get() {
    local key="$1"
    [[ -f "$CRD_FILE" ]] || return 0
    sed -n "s/^${key}=//p" "$CRD_FILE"
}

CRD_Set() {
    local key="$1" value="$2"
    awk -v key="$key" -v value="$value" '
        $0 ~ "^" key "=" {
            print key "=" value
            found = 1
            next
        }
        { print }
        END {
            if (!found)
                print key "=" value
        }
    ' "$CRD_FILE" > "${CRD_FILE}.tmp" &&
	chmod 600 "${CRD_FILE}.tmp" &&
    mv -f "${CRD_FILE}.tmp" "$CRD_FILE"
}

# =======================================================
# Check Dependencies
# =======================================================
Check_Dependencies() {
	local protocol need_pkgs=""
	protocol="$(CRD_Get PROTOCOL)"
	[[ -n "$protocol" ]] || protocol="smb"

	case "$protocol" in
		smb)
			command -v mount.cifs >/dev/null 2>&1 || need_pkgs="cifs-utils"
			;;
		nfs)
			command -v mount.nfs >/dev/null 2>&1 || need_pkgs="nfs-common"
			;;
		sshfs)
			{ command -v sshfs >/dev/null 2>&1 && command -v sshpass >/dev/null 2>&1; } || need_pkgs="sshfs sshpass"
			;;
		webdav)
			command -v mount.davfs >/dev/null 2>&1 || need_pkgs="davfs2"
			;;
	esac

	if [[ -n "$need_pkgs" ]]; then
		if ! apt update >/tmp/savesync_apt.log 2>&1 ||
		   ! apt -y install $need_pkgs >>/tmp/savesync_apt.log 2>&1; then
			dialog \
				--backtitle "$T_BACKTITLE" \
				--title "$T_SSYNC" \
				--msgbox "\n$T_NO_INSTALL" \
				8 45 \
				2>&1 > "$CURR_TTY"
			return
		fi
	fi
}

# =======================================================
# Install SaveSync
# =======================================================
Install_SaveSync() {
	dialog --backtitle "$T_BACKTITLE" --infobox "\n    $T_WAIT" 5 40 2>&1 > "$CURR_TTY"

	Check_Dependencies

	# --- Credential file ---
	if [[ ! -f "$CRD_FILE" ]]; then
		mkdir -p "$(dirname "$CRD_FILE")"
		cat > "$CRD_FILE" <<-EOF
PROTOCOL=
HOST=
USERNAME=
PASSWORD=
NETWORKPATH=
EOF
		chmod 600 "$CRD_FILE"
	fi

	# --- Sync script  ---
	if [[ ! -f "$FLAG_FILE" ]]; then
		cat >  "$SYNC_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "$(date "+%Y-%m-%d %H:%M:%S") - CRASH: line $LINENO, exit $?, cmd: $BASH_COMMAND" >> /home/ark/.config/savesync.log' ERR

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

# --- Argument handling ---
GAME_END_SYSTEM=""

if [ "${1:-}" = "--game-end" ]; then
    GAME_END_SYSTEM="${2:-}"

    if [ -z "$GAME_END_SYSTEM" ]; then
        log "ERROR: --game-end requires a system name"
        exit 1
    fi
fi

# --- Self-background ---
if [ "${1:-}" != "--bg" ] && [ "${1:-}" != "--scan" ]; then
    if [ "${1:-}" = "--game-end" ]; then
        nohup "$0" --bg --game-end "$GAME_END_SYSTEM" >/dev/null 2>&1 &
    else
        nohup "$0" --bg >>/home/ark/.config/savesync.log 2>&1 &
    fi
    disown
    exit 0
fi

# Recover game-end argument after self-backgrounding.
if [ "${2:-}" = "--game-end" ]; then
    GAME_END_SYSTEM="${3:-}"

    if [ -z "$GAME_END_SYSTEM" ]; then
        log "ERROR: --game-end requires a system name"
        exit 1
    fi
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
MTIME_CACHE_FILE="$MOUNT_POINT/mtime.cache"
FASTSYNC_FILE="/home/ark/.config/.fastsync"
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

		if [ ! -d "$location/$system" ]; then
			continue
		fi

        hit=$(find "$location/$system" -mindepth 1 -maxdepth 2 -type f \
              \( "${find_args[@]}" \) -print -quit 2>/dev/null)

        [ -n "$hit" ] && printf 'SYSTEM|%s|%s\n' "$system" "$location" >> "$CACHE_FILE"
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

standalone_cache_entries()
{
    local entry system location

    for entry in "${STANDALONE_PATHS[@]}"; do
        printf '%s\n' "$entry"
    done

    for system in "${!SYSTEM_CACHE[@]}"; do
        if [[ " $MEDNAFEN_SYSTEMS " == *" $system "* ]]; then
            location="${SYSTEM_CACHE[$system]}"
            [[ -n "$location" ]] || continue
            printf '%s|*.mcr\n' "$location/$system"
        fi
    done
}

build_remote_mtime_cache()
{
    REMOTE_SAVE_MTIME=()
    REMOTE_MCR_MTIME=()
    REMOTE_STANDALONE_MTIME=()
	local today
	local cache_date
	local entry path patterns key latest rel dst
	local system
	local pat m
	local -a find_args

    today=$(date +%F)

    # FastSync: today's mtime.cache is authoritative.
    if [[ -f "$FASTSYNC_FILE" && -f "$MTIME_CACHE_FILE" ]]; then
        cache_date=$(awk -F'|' '$1=="DATE"{print $2; exit}' "$MTIME_CACHE_FILE")

        if [[ "$cache_date" == "$today" ]]; then
            while IFS='|' read -r type key1 key2 val; do
                case "$type" in
                    SAVE) REMOTE_SAVE_MTIME["$key1"]="$val" ;;
                    MCR)  REMOTE_MCR_MTIME["$key1"]="$val" ;;
                    SA)   REMOTE_STANDALONE_MTIME["$key1|$key2"]="$val" ;;
                esac
            done < "$MTIME_CACHE_FILE"

            return 0
        fi
    fi

    log "Building remote mtime cache..."

    # Normal saves.
    while IFS= read -r file; do
        [[ -f "$file" ]] || continue

        system=$(basename "$(dirname "$file")")
        mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)
        [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0

        if [[ "$file" == *.mcr ]]; then
            REMOTE_MCR_MTIME["$system"]="${REMOTE_MCR_MTIME[$system]:-0}"
            (( mtime > REMOTE_MCR_MTIME["$system"] )) &&
                REMOTE_MCR_MTIME["$system"]="$mtime"
        else
            REMOTE_SAVE_MTIME["$system"]="${REMOTE_SAVE_MTIME[$system]:-0}"
            (( mtime > REMOTE_SAVE_MTIME["$system"] )) &&
                REMOTE_SAVE_MTIME["$system"]="$mtime"
        fi
    done < <(
        find "$MOUNT_POINT" \
            -type f \
            \( -name '*.srm' -o -name '*.sav' -o -name '*.state*' -o -name '*.mcr' \) \
            2>/dev/null
    )

    # All standalone locations.

    while IFS= read -r entry; do
        path="${entry%%|*}"
        patterns="${entry#*|}"
        key="$path|$patterns"
        latest=0

        rel="${path#/roms2/}"
        rel="${rel#/roms/}"
        dst="$MOUNT_POINT/$rel"

        if [[ -d "$dst" ]]; then
            if [[ -n "$patterns" ]]; then
                find_args=()
                for pat in $patterns; do
                    find_args+=( -name "$pat" -o )
                done
                unset 'find_args[${#find_args[@]}-1]'

                while IFS= read -r file; do
                    [[ -f "$file" ]] || continue
                    m=$(stat -c %Y "$file" 2>/dev/null || echo 0)
                    [[ "$m" =~ ^[0-9]+$ ]] || m=0
                    (( m > latest )) && latest=$m
                done < <(find "$dst" -type f \( "${find_args[@]}" \) 2>/dev/null)
            else
                while IFS= read -r file; do
                    [[ -f "$file" ]] || continue
                    m=$(stat -c %Y "$file" 2>/dev/null || echo 0)
                    [[ "$m" =~ ^[0-9]+$ ]] || m=0
                    (( m > latest )) && latest=$m
                done < <(find "$dst" -type f 2>/dev/null)
            fi
        fi

        REMOTE_STANDALONE_MTIME["$key"]="$latest"
    done < <(standalone_cache_entries)

    # FastSync persists the complete remote cache.
    if [[ -f "$FASTSYNC_FILE" ]]; then
        {
            printf 'DATE|%s\n' "$today"

            for system in "${!REMOTE_SAVE_MTIME[@]}"; do
                printf 'SAVE|%s||%s\n' "$system" "${REMOTE_SAVE_MTIME[$system]}"
            done

            for system in "${!REMOTE_MCR_MTIME[@]}"; do
                printf 'MCR|%s||%s\n' "$system" "${REMOTE_MCR_MTIME[$system]}"
            done

            for key in "${!REMOTE_STANDALONE_MTIME[@]}"; do
                IFS='|' read -r path patterns <<< "$key"
                printf 'SA|%s|%s|%s\n' "$path" "$patterns" "${REMOTE_STANDALONE_MTIME[$key]}"
            done
        } > "${MTIME_CACHE_FILE}.tmp"

        mv -f "${MTIME_CACHE_FILE}.tmp" "$MTIME_CACHE_FILE"
    fi
}

build_local_mtime_cache()
{
    LOCAL_SAVE_MTIME=()
    LOCAL_MCR_MTIME=()
    LOCAL_STANDALONE_MTIME=()
    local tmp_cache
    local entry path patterns key latest
    local system location
    local pat m
    local -a find_args
    local today cache_date

    today=$(date +%F)

    # Existing local cache is valid only for the current day.
    if [[ -f "$FASTSYNC_FILE" && -f "$CACHE_FILE" ]]; then
        cache_date=$(awk -F'|' '$1=="DATE"{print $2; exit}' "$CACHE_FILE" 2>/dev/null || true)

        if [[ "$cache_date" == "$today" ]]; then
            while IFS='|' read -r type key1 key2 val; do
                case "$type" in
                    SYSTEM)
                        SYSTEM_CACHE["$key1"]="$key2"
                        ;;
                    SAVE)
                        LOCAL_SAVE_MTIME["$key1"]="$val"
                        ;;
                    MCR)
                        LOCAL_MCR_MTIME["$key1"]="$val"
                        ;;
                    SA)
                        LOCAL_STANDALONE_MTIME["$key1|$key2"]="$val"
                        ;;
                esac
            done < "$CACHE_FILE"

            return 0
        fi

        log "Local mtime cache is from $cache_date — rebuilding..."
    fi

    log "Building local mtime cache..."

    tmp_cache="${CACHE_FILE}.tmp"
    : > "$tmp_cache"

    printf 'DATE|%s\n' "$today" >> "$tmp_cache"

    # Cache system locations.
    for system in "${!SYSTEM_CACHE[@]}"; do
        printf 'SYSTEM|%s|%s\n' "$system" "${SYSTEM_CACHE[$system]}" >> "$tmp_cache"
    done

    # Content-folder saves.
    if [[ "$USECONTENTFOLDER" == "true" ]]; then
        while IFS= read -r file; do
            [[ -f "$file" ]] || continue

            system=$(basename "$(dirname "$file")")
            mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)

            [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0

            if [[ "$file" == *.mcr ]]; then
                LOCAL_MCR_MTIME["$system"]="${LOCAL_MCR_MTIME[$system]:-0}"
                (( mtime > LOCAL_MCR_MTIME["$system"] )) &&
                    LOCAL_MCR_MTIME["$system"]="$mtime"
            else
                LOCAL_SAVE_MTIME["$system"]="${LOCAL_SAVE_MTIME[$system]:-0}"
                (( mtime > LOCAL_SAVE_MTIME["$system"] )) &&
                    LOCAL_SAVE_MTIME["$system"]="$mtime"
            fi
        done < <(
            find /roms /roms2 \
                -type f \
                \( -name '*.srm' -o -name '*.sav' -o -name '*.state*' -o -name '*.mcr' \) \
                2>/dev/null
        )
    fi

    # RetroArch save directories.
    for save_dir in "$RA64_SAVES" "$RA32_SAVES"; do
        [[ -d "$save_dir" ]] || continue

        while IFS= read -r file; do
            [[ -f "$file" ]] || continue

            system=$(basename "$(dirname "$file")")
            mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)

            [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0

            if [[ "$file" == *.mcr ]]; then
                LOCAL_MCR_MTIME["$system"]="${LOCAL_MCR_MTIME[$system]:-0}"
                (( mtime > LOCAL_MCR_MTIME["$system"] )) &&
                    LOCAL_MCR_MTIME["$system"]="$mtime"
            else
                LOCAL_SAVE_MTIME["$system"]="${LOCAL_SAVE_MTIME[$system]:-0}"
                (( mtime > LOCAL_SAVE_MTIME["$system"] )) &&
                    LOCAL_SAVE_MTIME["$system"]="$mtime"
            fi
        done < <(
            find "$save_dir" -type f 2>/dev/null
        )
    done

    # Standalone saves.
    # Every entry is cached, including directories/files with mtime 0.

    for entry in "${STANDALONE_PATHS[@]}"; do
        path="${entry%%|*}"
        patterns="${entry#*|}"
        key="$path|$patterns"
        latest=0

        if [[ -d "$path" ]]; then
            if [[ -n "$patterns" ]]; then
                find_args=()
                for pat in $patterns; do
                    find_args+=( -name "$pat" -o )
                done
                unset 'find_args[${#find_args[@]}-1]'

                while IFS= read -r file; do
                    [[ -f "$file" ]] || continue
                    m=$(stat -c %Y "$file" 2>/dev/null || echo 0)
                    [[ "$m" =~ ^[0-9]+$ ]] || m=0
                    (( m > latest )) && latest=$m
                done < <(find "$path" -type f \( "${find_args[@]}" \) 2>/dev/null)
            else
                while IFS= read -r file; do
                    [[ -f "$file" ]] || continue
                    m=$(stat -c %Y "$file" 2>/dev/null || echo 0)
                    [[ "$m" =~ ^[0-9]+$ ]] || m=0
                    (( m > latest )) && latest=$m
                done < <(find "$path" -type f 2>/dev/null)
            fi
        fi

        LOCAL_STANDALONE_MTIME["$key"]="$latest"

        printf 'SA|%s|%s|%s\n' "$path" "$patterns" "$latest" >> "$tmp_cache"
    done

    # Mednafen .mcr standalone locations.
    for system in "${!SYSTEM_CACHE[@]}"; do
        if [[ " $MEDNAFEN_SYSTEMS " == *" $system "* ]]; then
            location="${SYSTEM_CACHE[$system]}"
            path="$location/$system"
            patterns="*.mcr"
            key="$path|$patterns"
            latest=0

            if [[ -d "$path" ]]; then
                while IFS= read -r file; do
                    [[ -f "$file" ]] || continue
                    m=$(stat -c %Y "$file" 2>/dev/null || echo 0)
                    [[ "$m" =~ ^[0-9]+$ ]] || m=0
                    (( m > latest )) && latest=$m
                done < <(find "$path" -type f -name '*.mcr' 2>/dev/null)
            fi

            LOCAL_STANDALONE_MTIME["$key"]="$latest"

            printf 'SA|%s|%s|%s\n' "$path" "$patterns" "$latest" >> "$tmp_cache"
        fi
    done

    # Normal cached mtimes.
    for system in "${!LOCAL_SAVE_MTIME[@]}"; do
        printf 'SAVE|%s||%s\n' "$system" "${LOCAL_SAVE_MTIME[$system]}" >> "$tmp_cache"
    done

    for system in "${!LOCAL_MCR_MTIME[@]}"; do
        printf 'MCR|%s||%s\n' "$system" "${LOCAL_MCR_MTIME[$system]}" >> "$tmp_cache"
    done

    mv -f "$tmp_cache" "$CACHE_FILE"
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

refresh_game_end_local_cache()
{
    local system="$1"
    local latest="$2"
    local type="$3"
    local tmp="${CACHE_FILE}.tmp"

    {
        while IFS= read -r line; do
            case "$line" in
                "$type|$system||"*)
                    printf '%s|%s||%s\n' "$type" "$system" "$latest"
                    ;;
                *)
                    printf '%s\n' "$line"
                    ;;
            esac
        done < "$CACHE_FILE"

        if ! grep -q "^${type}|${system}||" "$CACHE_FILE"; then
            printf '%s|%s||%s\n' "$type" "$system" "$latest"
        fi
    } > "$tmp"

    mv -f "$tmp" "$CACHE_FILE"

    if [ "$type" = "MCR" ]; then
        LOCAL_MCR_MTIME["$system"]="$latest"
    else
        LOCAL_SAVE_MTIME["$system"]="$latest"
    fi
}

remote_mtime() {
    local dir="$1" patterns="$2"
    local system="${dir#"$MOUNT_POINT"/}"

    system="${system%%/*}"

    if [ "$patterns" = "*.mcr" ]; then
        printf '%s\n' "${REMOTE_MCR_MTIME[$system]-0}"
    elif [ "$patterns" = "*.srm *.sav *.state* *.auto" ]; then
        printf '%s\n' "${REMOTE_SAVE_MTIME[$system]-0}"
    else
        latest_mtime "$dir" "$patterns"
    fi
}

local_mtime() {
    local dir="$1" patterns="$2"
    local system

    if [[ "$dir" == /roms2/* ]]; then
        system="${dir#/roms2/}"
    elif [[ "$dir" == /roms/* ]]; then
        system="${dir#/roms/}"
    elif [[ "$dir" == "$RA64_SAVES"/* ]]; then
        system="${dir#"$RA64_SAVES"/}"
    elif [[ "$dir" == "$RA32_SAVES"/* ]]; then
        system="${dir#"$RA32_SAVES"/}"
    else
        system=""
    fi

    system="${system%%/*}"
	
    if [ "$patterns" = "*.mcr" ]; then
        printf '%s\n' "${LOCAL_MCR_MTIME[$system]-0}"
    elif [ "$patterns" = "*.srm *.sav *.state* *.auto" ]; then
        printf '%s\n' "${LOCAL_SAVE_MTIME[$system]-0}"
    else
        latest_mtime "$dir" "$patterns"
    fi
}

sync_dir() {
    local src="$1" dst="$2" patterns="$3" filter="${4:-}"
    local src_m dst_m pat rsync_opts=()
    local system tmp_cache

    if [ -n "$filter" ]; then
        for pat in $filter; do
            rsync_opts+=(--include="$pat")
        done
        rsync_opts+=(--exclude='*')
    fi

    src_m=$(local_mtime "$src" "$patterns")

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

        log "Copying (console->PC): $src"

        rsync -au --no-owner --no-group \
            "${rsync_opts[@]}" \
            "$src/" "$dst/" >> "$LOG_FILE" 2>&1

        if [[ "$dst" == "$MOUNT_POINT/"* ]]; then
            local rc_system="${dst#"$MOUNT_POINT"/}"
            rc_system="${rc_system%%/*}"

            if [ "$patterns" = "*.mcr" ]; then
                REMOTE_MCR_MTIME["$rc_system"]="$src_m"
            elif [ "$patterns" = "*.srm *.sav *.state* *.auto" ]; then
                REMOTE_SAVE_MTIME["$rc_system"]="$src_m"
            fi
        fi

    elif [ "$src_m" -eq 0 ]; then
        mkdir -p "$src" || {
            log "ERROR: mkdir failed for $src"
            return
        }

        log "Copying (PC->console): $src"

        rsync -au --no-owner --no-group \
            "${rsync_opts[@]}" \
            "$dst/" "$src/" >> "$LOG_FILE" 2>&1

        system="${src##*/}"
        LOCAL_SAVE_MTIME["$system"]="$dst_m"

    elif [ "$src_m" -ne "$dst_m" ]; then

        if [ "$src_m" -gt "$dst_m" ]; then
            log "Syncing (console->PC): $src"

            rsync -au --no-owner --no-group \
                "${rsync_opts[@]}" \
                "$src/" "$dst/" >> "$LOG_FILE" 2>&1

            if [[ "$dst" == "$MOUNT_POINT/"* ]]; then
                local rc_system="${dst#"$MOUNT_POINT"/}"
                rc_system="${rc_system%%/*}"

                if [ "$patterns" = "*.mcr" ]; then
                    REMOTE_MCR_MTIME["$rc_system"]="$src_m"
                elif [ "$patterns" = "*.srm *.sav *.state* *.auto" ]; then
                    REMOTE_SAVE_MTIME["$rc_system"]="$src_m"
                fi
            fi

        else
            log "Syncing (PC->console): $src"

            rsync -au --no-owner --no-group \
                "${rsync_opts[@]}" \
                "$dst/" "$src/" >> "$LOG_FILE" 2>&1

            system="${src##*/}"
            LOCAL_SAVE_MTIME["$system"]="$dst_m"
        fi
    fi
}

game_end_sync()
{
    local system="$1"
    local src="$2"
    local dst="$3"
    local type="$4"
    local patterns="$5"
    local src_m rc=0
    local rsync_opts=()

    for pat in $patterns; do
        rsync_opts+=(--include="$pat")
    done
    rsync_opts+=(--exclude='*')

    # The one live scan for game-end.
    src_m=$(latest_mtime "$src" "$patterns")

    mkdir -p "$dst" || {
        log "ERROR: mkdir failed for $dst"
        refresh_game_end_local_cache "$system" "$src_m" "$type"
        return 1
    }

    log "Game-end sync (console->PC): $src"

    if rsync -au --no-owner --no-group \
        "${rsync_opts[@]}" \
        "$src/" "$dst/" >> "$LOG_FILE" 2>&1; then
        if [ "$type" = "MCR" ]; then
            REMOTE_MCR_MTIME["$system"]="$src_m"
        else
            REMOTE_SAVE_MTIME["$system"]="$src_m"
        fi
    else
        log "ERROR: game-end rsync failed for $system"
        rc=1
    fi

    # Local cache reflects the live scan regardless of rsync outcome,
    # so a stale cache can't mask the change from a future sync.
    refresh_game_end_local_cache "$system" "$src_m" "$type"

    return "$rc"
}

sync_standalone()
{
    local src="$1"
    local filter="$2"

    local key="$src|$filter"
    local src_m="${LOCAL_STANDALONE_MTIME[$key]:-0}"
    local dst_m="${REMOTE_STANDALONE_MTIME[$key]:-0}"

    local rel="${src#/roms2/}"
    rel="${rel#/roms/}"

    local dst="$MOUNT_POINT/$rel"
    local rsync_opts=()
    local pat

    for pat in $filter; do
        rsync_opts+=(--include="$pat")
    done
    rsync_opts+=(--exclude='*')

    mkdir -p "$dst"

    if (( src_m > dst_m )); then
        log "Syncing (console->PC): $src"

        rsync -a --update \
            --include='*/' \
            "${rsync_opts[@]}" \
            "$src/" "$dst/" >> "$LOG_FILE" 2>&1

        REMOTE_STANDALONE_MTIME["$key"]="$src_m"

    elif (( dst_m > src_m )); then
        log "Syncing (PC->console): $src"

        rsync -a --update \
            --include='*/' \
            "${rsync_opts[@]}" \
            "$dst/" "$src/" >> "$LOG_FILE" 2>&1

        LOCAL_STANDALONE_MTIME["$key"]="$dst_m"
    fi
}


game_end_standalone_sync()
{
    local src="$1"
    local filter="$2"

    local key="$src|$filter"
    local dst_m
    local src_m
    local dst
    local rel
    local tmp
    local pat
    local rsync_opts=()
    local rc=0

    for pat in $filter; do
        rsync_opts+=(--include="$pat")
    done
    rsync_opts+=(--exclude='*')

    rel="${src#/roms2/}"
    rel="${rel#/roms/}"
    dst="$MOUNT_POINT/$rel"

    # The ONLY live scan for this targeted standalone folder.
    src_m=$(latest_mtime "$src" "$filter")

    mkdir -p "$dst" || {
        log "ERROR: mkdir failed for $dst"
        return 1
    }

    log "Game-end standalone sync (console->PC): $src"

    if rsync -a --update \
        --include='*/' \
        "${rsync_opts[@]}" \
        "$src/" "$dst/" >> "$LOG_FILE" 2>&1; then

        # Remote cache gets the targeted live result.
        REMOTE_STANDALONE_MTIME["$key"]="$src_m"

        # Local cache gets the same targeted live result.
        LOCAL_STANDALONE_MTIME["$key"]="$src_m"

        # Update ONLY this standalone entry in the local cache.
        if [[ -f "$CACHE_FILE" ]]; then
            tmp="${CACHE_FILE}.tmp"

            {
                while IFS= read -r line; do
                    case "$line" in
                        "SA|$src|$filter|"*)
                            printf 'SA|%s|%s|%s\n' \
                                "$src" "$filter" "$src_m" ;;
                        *)
                            printf '%s\n' "$line" ;;
                    esac
                done < "$CACHE_FILE"

                if ! grep -Fq "SA|$src|$filter|" "$CACHE_FILE"; then
                    printf 'SA|%s|%s|%s\n' \
                        "$src" "$filter" "$src_m"
                fi
            } > "$tmp"

            mv -f "$tmp" "$CACHE_FILE"
        fi

    else
        log "ERROR: game-end standalone rsync failed for $src"
        rc=1
    fi

    return "$rc"
}

mount_smb() {
    local network_ip mount_err

    if [[ "$HOST" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        network_ip="$HOST"
    else
        network_ip=""

        for attempt in 1 2 3; do
            network_ip=$(nmblookup "$HOST" 2>/dev/null |
                grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' |
                head -n 1) || true

            if [[ -n "$network_ip" ]]; then
                break
            fi

            log "NetBIOS lookup failed for $HOST (attempt $attempt/3)"

            if [[ "$attempt" -lt 3 ]]; then
                sleep 1
            fi
        done
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
    log "PC config not found at $PC_CFG — creating default (USECONTENTFOLDER=false)"
    printf 'USECONTENTFOLDER=false\n' > "$PC_CFG" || {
        log "ERROR: failed to create default PC config at $PC_CFG"
        umount "$MOUNT_POINT"
        exit 1
    }
fi

USECONTENTFOLDER=$( { grep -E '^USECONTENTFOLDER=' "$PC_CFG" || true; } | cut -d'=' -f2 | tr -d '[:space:]')

if [[ "$USECONTENTFOLDER" != "true" && "$USECONTENTFOLDER" != "false" ]]; then
    log "ERROR: invalid or missing UseContentFolder in $PC_CFG — expected true or false"
    umount "$MOUNT_POINT"
    exit 1
fi

# --- Load persistent local/system cache ---
SYSTEM_CACHE=()

if [ -f "$CACHE_FILE" ]; then
	while IFS='|' read -r type key value extra; do
		case "$type" in
			SYSTEM)
				SYSTEM_CACHE["$key"]="$value" ;;
			SAVE)
				LOCAL_SAVE_MTIME["$key"]="$value" ;;
			MCR)
				LOCAL_MCR_MTIME["$key"]="$value" ;;
			SA)
				LOCAL_STANDALONE_MTIME["$key|$value"]="$extra" ;;
		esac
	done < "$CACHE_FILE"
fi

# --- Build/load caches ---
if [ -z "$GAME_END_SYSTEM" ]; then
    build_local_mtime_cache
    build_remote_mtime_cache
fi

if [ -n "$GAME_END_SYSTEM" ] && [ -f "$FASTSYNC_FILE" ] && [ -f "$MTIME_CACHE_FILE" ]; then
    while IFS='|' read -r type key1 key2 val; do
        case "$type" in
            SAVE) REMOTE_SAVE_MTIME["$key1"]="$val" ;;
            MCR) REMOTE_MCR_MTIME["$key1"]="$val" ;;
            SA) REMOTE_STANDALONE_MTIME["$key1|$key2"]="$val" ;;
        esac
    done < "$MTIME_CACHE_FILE"
fi

# --- Determine console's current active save mode ---
CONTENT_MODE=$( { grep '^savefiles_in_content_dir' "$RA_CFG" || true; } | grep -o 'true\|false')

# --- Sync every system listed in es_systems.cfg ---
while IFS='|' read -r SYSTEM LOCATION RA64_ENABLED RA32_ENABLED; do

    # Game-end mode syncs only the system that just closed.
    if [ -n "$GAME_END_SYSTEM" ] && [ "$SYSTEM" != "$GAME_END_SYSTEM" ]; then
        continue
    fi

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

	if [ -n "$GAME_END_SYSTEM" ]; then
		game_end_sync "$SYSTEM" "$SRC_DIR" "$DST_DIR" SAVE "*.srm *.sav *.state* *.auto"
		if [ -n "$LOCATION" ] && [[ " $MEDNAFEN_SYSTEMS " == *" $SYSTEM "* ]]; then
			game_end_sync "$SYSTEM" "$LOCATION/$SYSTEM" "$MOUNT_POINT/$SYSTEM" MCR "*.mcr"
		fi
		continue
	else
		sync_dir "$SRC_DIR" "$DST_DIR" "*.srm *.sav *.state* *.auto"
	fi
	
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

    if [ -n "$GAME_END_SYSTEM" ]; then

        # Map standalone paths to their actual emulator/system.
        case "$SA_SRC" in
            /roms/bios/dc)
                SA_SYSTEM="dc" ;;
            /roms/n64)
                SA_SYSTEM="n64" ;;
            /roms/nds/backup)
                SA_SYSTEM="nds" ;;
            /roms/psp/ppsspp/PSP/SAVEDATA|\
            /roms/psp/ppsspp/PSP/PPSSPP_STATE)
                SA_SYSTEM="psp" ;;
            /roms/saturn)
                SA_SYSTEM="saturn" ;;
            *)
                continue ;;
        esac

        [ "$SA_SYSTEM" = "$GAME_END_SYSTEM" ] || continue

        game_end_standalone_sync "$SA_SRC" "$SA_FILTER"
    else
        sync_standalone "$SA_SRC" "$SA_FILTER"
    fi
done

# --- Persist local cache (FastSync normal sync only) ---
if [ -f "$FASTSYNC_FILE" ] && [ -z "$GAME_END_SYSTEM" ]; then
    {
        printf 'DATE|%s\n' "$(date '+%Y-%m-%d')"

        for system in "${!SYSTEM_CACHE[@]}"; do
            printf 'SYSTEM|%s|%s\n' "$system" "${SYSTEM_CACHE[$system]}"
        done

        for system in "${!LOCAL_SAVE_MTIME[@]}"; do
            printf 'SAVE|%s||%s\n' "$system" "${LOCAL_SAVE_MTIME[$system]}"
        done

        for system in "${!LOCAL_MCR_MTIME[@]}"; do
            printf 'MCR|%s||%s\n' "$system" "${LOCAL_MCR_MTIME[$system]}"
        done

        for key in "${!LOCAL_STANDALONE_MTIME[@]}"; do
            IFS='|' read -r path patterns <<< "$key"

            printf 'SA|%s|%s|%s\n' \
                "$path" \
                "$patterns" \
                "${LOCAL_STANDALONE_MTIME[$key]}"
        done
    } > "${CACHE_FILE}.tmp"

    mv -f "${CACHE_FILE}.tmp" "$CACHE_FILE"
fi

# --- Persist incremental remote cache updates (fast-sync mode only) ---
if [ -f "$FASTSYNC_FILE" ]; then
    {
        printf 'DATE|%s\n' "$(date '+%Y-%m-%d')"
        for s in "${!REMOTE_SAVE_MTIME[@]}"; do
            printf 'SAVE|%s||%s\n' "$s" "${REMOTE_SAVE_MTIME[$s]}"
        done
        for s in "${!REMOTE_MCR_MTIME[@]}"; do
            printf 'MCR|%s||%s\n' "$s" "${REMOTE_MCR_MTIME[$s]}"
        done
		for key in "${!REMOTE_STANDALONE_MTIME[@]}"; do
			IFS='|' read -r path patterns <<< "$key"

			printf 'SA|%s|%s|%s\n' \
				"$path" \
				"$patterns" \
				"${REMOTE_STANDALONE_MTIME[$key]}"
		done
    } > "$MTIME_CACHE_FILE"
fi

# --- Unmount ---
umount "$MOUNT_POINT"
log "Sync complete, unmounted $MOUNT_POINT"
EOF
		chmod +x "$SYNC_SCRIPT"
	fi

	# --- Game-start hook ---
	if [[ ! -f "$FLAG_FILE" ]]; then
		mkdir -p "$(dirname "$GAMESTART_HOOK")"
		cat > "$GAMESTART_HOOK" <<-EOF
#!/usr/bin/env bash

GAME_FILE="/home/ark/.config/savesync.game"

# Clear the previous game's state immediately.
rm -f "$GAME_FILE"

# Do not delay EmulationStation/game launch.
(
    sleep 1

    rom=""

    # Read each process argument separately.
    # This preserves spaces inside ROM filenames.
    for proc in /proc/[0-9]*; do
        [ -r "$proc/cmdline" ] || continue

        while IFS= read -r -d '' arg; do
            case "$arg" in
                /roms/*|/roms2/*)
                    rom="$arg"
                    break
                    ;;
            esac
        done < "$proc/cmdline"

        [ -n "$rom" ] && break
    done

    [ -n "$rom" ] || exit 0

    # System is the first directory below /roms or /roms2.
    case "$rom" in
        /roms2/*)
            rel="${rom#/roms2/}"
            ;;
        /roms/*)
            rel="${rom#/roms/}"
            ;;
        *)
            exit 0
            ;;
    esac

    system="${rel%%/*}"
    [ -n "$system" ] || exit 0

    # Write atomically so SaveSync never sees a partial file.
    tmp="${GAME_FILE}.tmp"

    {
        printf 'SYSTEM=%s\n' "$system"
        printf 'ROM=%s\n' "$rom"
    } > "$tmp"

    mv -f "$tmp" "$GAME_FILE"
) >/dev/null 2>&1 &

exit 0
EOF
		chmod +x "$GAMESTART_HOOK"
	fi

	# --- Game-end hook ---
	if [[ ! -f "$FLAG_FILE" ]]; then
		mkdir -p "$(dirname "$GAMEEND_HOOK")"
		cat > "$GAMEEND_HOOK" <<-EOF
#!/usr/bin/env bash

GAME_FILE="/home/ark/.config/savesync.game"

[ -f "$GAME_FILE" ] || exit 0

SYSTEM=""

while IFS='=' read -r key value; do
    case "$key" in
        SYSTEM) SYSTEM="$value" ;;
    esac
done < "$GAME_FILE"

[ -n "$SYSTEM" ] || exit 0

/usr/local/bin/savesync.sh --game-end "$SYSTEM"
EOF
		chmod +x "$GAMEEND_HOOK"
	fi

	# --- Boot service ---
	if [[ ! -f "$FLAG_FILE" ]]; then
		cat > "$SERVICE_FILE" <<-EOF
[Unit]
Description=SaveSync Boot Sync Service
Wants=NetworkManager-wait-online.service
After=NetworkManager-wait-online.service
ExecStartPre=/bin/sleep 5

[Service]
Type=oneshot
ExecStart=/usr/local/bin/savesync.sh --scan
ExecStart=/usr/local/bin/savesync.sh --bg
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
	fi
	systemctl daemon-reload
	systemctl enable savesync.service

	touch "$FLAG_FILE"

	dialog --backtitle "$T_BACKTITLE" --msgbox "\n$T_SS_INSTALL" 6 40 2>&1 > "$CURR_TTY"
}

# =======================================================
# Uninstall SaveSync
# =======================================================
Uninstall_SaveSync() {
	dialog --backtitle "$T_BACKTITLE" --infobox "\n    $T_WAIT" 5 40 2>&1 > "$CURR_TTY"

	# --- Boot service ---
	if [[ -f "$SERVICE_FILE" ]]; then
		systemctl disable savesync.service 2>/dev/null
		rm -f "$SERVICE_FILE"
		systemctl daemon-reload
	fi
	
	# --- WebDAV secrets cleanup ---
	if [[ -f /etc/davfs2/secrets ]]; then
		sed -i '\#^/mnt/savesync #d' /etc/davfs2/secrets
	fi
	
	# --- savesync.sh ---

	rm -f "$SYNC_SCRIPT"

	# --- Game-start hook ---
	rm -f "$GAMESTART_HOOK"
	
	# --- Game-end hook ---
	rm -f "$GAMEEND_HOOK"

	# --- Flag ---
	rm -f "$FLAG_FILE"
	
	# --- FastSync Flag ---
	rm -f "$FS_FLAG"	

	dialog --backtitle "$T_BACKTITLE" --msgbox "\n$T_SS_UNINSTALL" 6 40 2>&1 > "$CURR_TTY"
}

# =======================================================
# Manual Sync
# =======================================================
Manual_Sync() {
    local LOG_START=0
    local ERROR_MSG=""
	local RESULT
	
	dialog --backtitle "$T_BACKTITLE" --infobox "\n    $T_WAIT" 5 40 2>&1 > "$CURR_TTY"

    if [[ -f "$LOG_FILE" ]]; then
        LOG_START=$(wc -c < "$LOG_FILE")
    fi

    if "$SYNC_SCRIPT" --bg; then
        RESULT="SUCCESS"
    else
        RESULT="FAILED"
    fi

    if [[ -f "$LOG_FILE" ]]; then
        ERROR_MSG=$(tail -c +"$((LOG_START + 1))" "$LOG_FILE" |
            grep 'ERROR:' |
            tail -n 1)
    fi
	
    if [[ "$RESULT" == "SUCCESS" ]]; then
        dialog \
            --backtitle "$T_BACKTITLE" \
            --title "$T_SSYNC" \
            --msgbox "\n    $T_SUCCESS" \
            7 40 \
            2>&1 > "$CURR_TTY"
    else
		ERROR_MSG=$(printf '%s\n' "$ERROR_MSG" | fold -s -w 34)
        if [[ -n "$ERROR_MSG" ]]; then
            dialog \
                --backtitle "$T_BACKTITLE" \
                --title "$T_SSYNC" \
                --msgbox "\n$T_FAILED\n\n$ERROR_MSG" \
                10 40 \
                2>&1 > "$CURR_TTY"
        else
            dialog \
                --backtitle "$T_BACKTITLE" \
                --title "$T_SSYNC" \
                --msgbox "\n$T_FAILED\n\n$T_NO_DETAILS" \
                10 40 \
                2>&1 > "$CURR_TTY"
        fi
    fi
}

# =======================================================
# Clear Log
# =======================================================
Clear_Log() {
    if [[ ! -f "$LOG_FILE" ]]; then
        dialog \
            --backtitle "$T_BACKTITLE" \
            --title "$T_SSYNC" \
            --msgbox "\n$T_NO_LOG" \
            7 40 \
            2>&1 > "$CURR_TTY"
        return
    fi

    : > "$LOG_FILE"

    dialog \
        --backtitle "$T_BACKTITLE" \
        --title "$T_SSYNC" \
        --msgbox "\n$T_LOG_CLEARED" \
        7 40 \
        2>&1 > "$CURR_TTY"
}

# =======================================================
# View Log
# =======================================================
View_Log() {
    if [[ ! -f "$LOG_FILE" ]]; then
        dialog \
            --backtitle "$T_BACKTITLE" \
            --title "$T_SSYNC" \
            --msgbox "\n$T_NO_LOG" \
            7 40 \
            2>&1 > "$CURR_TTY"
        return
    fi

    local VIEW_LOG="/tmp/savesync_view.$$"

    fold -s -w 36 "$LOG_FILE" > "$VIEW_LOG"

    dialog \
        --backtitle "$T_BACKTITLE" \
        --title "$T_SSYNC" \
        --textbox "$VIEW_LOG" \
        16 40 \
        2>&1 > "$CURR_TTY"

    rm -f "$VIEW_LOG"
}

# =======================================================
# Credentials Menu dialog
# =======================================================
Credentials_Menu() {
	while true; do
		# --- keep gptokeyb alive ---
		if [[ -z $(pgrep -f gptokeyb) ]]; then
			Start_GPTKeyb
		fi
		
		local network_id=""
		local username=""
		local networkpath=""
		
		if [[ -f "$CRD_FILE" ]]; then
			network_id=$(sed -n 's/^HOST=//p' "$CRD_FILE")
			username=$(sed -n 's/^USERNAME=//p' "$CRD_FILE")
			networkpath=$(sed -n 's/^NETWORKPATH=//p' "$CRD_FILE")
		fi
		
		local CHOICE
		CHOICE=$(dialog \
			--clear \
			--colors \
			--no-collapse \
			--cancel-label "$T_EXIT" \
			--backtitle "$T_BACKTITLE" \
			--title "$T_SSYNC" \
			--menu "Host=$network_id\nUsername=$username\nPath=$networkpath" \
			14 45 6 \
			"1" "$T_IP" \
			"2" "$T_NAME" \
			"3" "$T_PASS" \
			"4" "$T_PATH" \
            2>&1 > "$CURR_TTY")
			
			[[ $? -ne 0 ]] && return

		case "$CHOICE" in
			1) CRD_Prompt HOST "Host" ;;
			2) CRD_Prompt USERNAME "Username" ;;
			3) CRD_Prompt PASSWORD "Password" cancel_ok ;;
			4) CRD_Prompt NETWORKPATH "Network Path" ;;
		esac
	done
}

# =======================================================
# Protocol Menu dialog
# =======================================================
Protocol_Menu() {
	while true; do
		local current
		current="$(CRD_Get PROTOCOL)"
		[[ -n "$current" ]] || current="smb"

		local CHOICE
		CHOICE=$(dialog \
			--clear \
			--colors \
			--no-collapse \
			--cancel-label "$T_EXIT" \
			--backtitle "$T_BACKTITLE" \
			--title "$T_PROTOCOL" \
			--menu "Current: $current" \
			14 45 6 \
			"1" "SMB (Windows / Samba share)" \
			"2" "NFS (Linux / NAS export)" \
			"3" "SSHFS (SSH / SFTP server)" \
			"4" "WebDAV (Nextcloud / ownCloud / DAV)" \
			2>&1 > "$CURR_TTY")

		[[ $? -ne 0 ]] && Check_Dependencies && return

		case "$CHOICE" in
			1) CRD_Set PROTOCOL "smb" ;;
			2) CRD_Set PROTOCOL "nfs" ;;
			3) CRD_Set PROTOCOL "sshfs" ;;
			4) CRD_Set PROTOCOL "webdav" ;;
		esac
	done
}

# =======================================================
# Log Menu dialog
# =======================================================
Log_Menu() {
	while true; do
		# --- keep gptokeyb alive ---
		if [[ -z $(pgrep -f gptokeyb) ]]; then
			Start_GPTKeyb
		fi

		local CHOICE
		CHOICE=$(dialog \
			--clear \
			--colors \
			--no-collapse \
			--cancel-label "$T_EXIT" \
			--backtitle "$T_BACKTITLE" \
			--title "$T_LOG_TITLE" \
			--menu "" \
			14 45 6 \
			"1" "$T_VIEW_LOG" \

			"2" "$T_CLEAR_LOG" \
            2>&1 > "$CURR_TTY")
			
			[[ $? -ne 0 ]] && return

			case "$CHOICE" in
				1) View_Log ;;
				2) Clear_Log ;;
			esac
	done
}

# =======================================================
# Location Menu dialog
# =======================================================
Location_Menu() {
	while true; do
		# --- keep gptokeyb alive ---
		if [[ -z $(pgrep -f gptokeyb) ]]; then
			Start_GPTKeyb
		fi

		local state
		local location
		location=$(grep '^savefiles_in_content_dir' "$RA64_CFG" | grep -o 'true\|false')
		if [[ "$location" == "true" ]]; then
			location="$T_CONTENT_FOLDER"
			save="$T_SAVE"
			state="1"
		else
			location="$T_SAVE_FOLDER"
			save="$T_FOLDER"
			state="0"
		fi
		
		local CHOICE
		CHOICE=$(dialog \
			--clear \
			--colors \
			--no-collapse \
			--cancel-label "$T_EXIT" \
			--backtitle "$T_BACKTITLE" \
			--title "$T_SAVE_LOCATION" \
			--menu "$T_LOCATION \Z2$location\Zn\n$T_STATUS" \
			14 45 6 \
			"1" "$save" \
			"2" "$T_MIGRATE" \
            2>&1 > "$CURR_TTY")
			
			[[ $? -ne 0 ]] && return

			case "$CHOICE" in
				1) dialog --yesno "$T_SURE" 6 30 || return 0
					if [[ "$state" == "1" ]]; then
						Saves_Folder
					else
						Content_Folders
					fi ;;
				2) Migrate_Saves ;;
			esac
	done
}

# =======================================================
# Main Menu dialog
# =======================================================
Main_Menu() {
	while true; do
		# --- keep gptokeyb alive ---
		if [[ -z $(pgrep -f gptokeyb) ]]; then
			Start_GPTKeyb
		fi
		
		local installed
		local fastsync
		if [[ -f "$FLAG_FILE" ]]; then
			installed="$T_UNINSTALL"
		else
			installed="$T_INSTALL"
		fi

		if [[ -f "$FS_FLAG" ]]; then
			fastsync="$T_FS_ON"
		else
			fastsync="$T_FS_OFF"
		fi
		
		local CHOICE
		CHOICE=$(dialog \
			--clear \
			--colors \
			--no-collapse \
			--cancel-label "$T_EXIT" \
			--backtitle "$T_BACKTITLE" \
			--title "$T_SSYNC" \
			--menu "" \
			14 45 6 \
			"1" "$installed" \
			"2" "$T_MANUAL" \
			"3" "$T_CACHE" \
			"4" "$T_CRED" \
			"5" "$T_PROTOCOL" \
			"6" "$fastsync" \
			"7" "$T_LOG_TITLE" \
			"8" "$T_SAVE_LOCATION" \
            2>&1 > "$CURR_TTY")
			
			[[ $? -ne 0 ]] && Exit_Menu

			case "$CHOICE" in
				1) if [[ "$installed" == "$T_INSTALL" ]]; then
						Install_SaveSync
					else
						Uninstall_SaveSync
					fi ;;
				2) Manual_Sync ;;
				3) "$SYNC_SCRIPT" --scan ;;
				4) Credentials_Menu ;;
				5) Protocol_Menu ;;
				6) if [[ -f "$FS_FLAG" ]]; then
						rm -f "$FS_FLAG"
					else
						touch "$FS_FLAG"
					fi ;;
				7) Log_Menu ;;
				8) Location_Menu
			esac
	done
}

# =======================================================
# Gamepad Setup
# =======================================================
export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
chmod 666 /dev/uinput
cp /opt/inttools/keys.gptk "$TMP_KEYS"
if grep -q '^b = backspace' "$TMP_KEYS"; then
    sed -i 's/^b = .*/b = esc/' "$TMP_KEYS"
    sed -i 's/^a = .*/a = enter/' "$TMP_KEYS"
fi
Start_GPTKeyb

# =======================================================
# Main Execution
# =======================================================
printf "\033[H\033[2J" > "$CURR_TTY"
dialog --clear
trap 'Exit_Menu' EXIT

Main_Menu
