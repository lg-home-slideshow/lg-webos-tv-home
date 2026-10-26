#!/bin/sh
# tv-home.sh - TV Home on the TV: its server, and TV Home in LG's Home's place.
#
#   sh tv-home.sh start | stop | status    the server only (LG's Home untouched)
#   sh tv-home.sh take [qml|web]           TV Home becomes the TV's Home: the
#                                          native QML version (app-qml) or the
#                                          web version (app); remembered in ./kind
#   sh tv-home.sh give                     LG's Home back
#   sh tv-home.sh reload                   TV Home's own files changed: open it afresh
#   sh tv-home.sh boot                     what the boot hook runs: start, take, watch
#
# How the take works (as Glasshouse does on webOS 10): our app folder, a web
# app under LG's Home's id com.webos.app.home with appCategory "home", is
# bind-mounted over LG's Home's folder; the app manager (sam) is made to reread
# it (blockSystemApp + releaseBlockSystemApp); LG's Home (Flutter) is stopped.
# The TV then opens ours for the Home button, Back out of an app and waking up.
#
# Nothing on the system is written: the mount is in memory and goes with a
# restart. A watchdog gives LG's Home back if TV Home stops answering.

# LG's own tools first (a plain ssh session puts the Homebrew Channel's first).
PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH
export PATH

BASE=/home/root/tv-home
LOG=$BASE/server.log
WLOG=$BASE/tv-home.log
PORT=8650
HOME_ID=com.webos.app.home
LG_DIR=/usr/palm/applications/$HOME_ID
KIND=$(cat "$BASE/kind" 2>/dev/null)
case "$KIND" in qml|web) ;; *) KIND=qml ;; esac
app_dir() { if [ "$1" = qml ]; then echo "$BASE/app-qml"; else echo "$BASE/app"; fi; }
APP=$(app_dir "$KIND")
SAM=luna://com.webos.applicationManager
STATE=/tmp/tv-home
BLOCK_SCHEMA=/etc/palm/schemas/sam/applicationManager.blockSystemApp.schema

log() { echo "[tv-home $(date '+%F %T')] $*" | tee -a "$WLOG"; }
luna() { luna-send -n 1 -w 5000 "$SAM/$1" "$2" </dev/null 2>&1; }

# ---- the server -------------------------------------------------------------------
pids() {
    for p in /proc/[0-9]*; do
        case "$( { tr '\0' ' ' < "$p/cmdline"; } 2>/dev/null )" in
            *"$BASE/server.js"*) echo "${p#/proc/}" ;;
        esac
    done
}
server_up() { wget -q -T 3 -O /dev/null "http://127.0.0.1:$PORT/api/heartbeat" 2>/dev/null; }

stop() {
    for pid in $(pids); do kill "$pid" 2>/dev/null && echo "stopped server (pid $pid)"; done
    return 0
}

start() {
    stop >/dev/null
    if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 262144 ]; then
        tail -n 500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    fi
    cd "$BASE" || exit 1
    # Its own session, away from this shell, so it outlives an ssh session.
    if command -v setsid >/dev/null 2>&1; then
        setsid /usr/bin/node "$BASE/server.js" --port "$PORT" >>"$LOG" 2>&1 </dev/null &
    else
        nohup /usr/bin/node "$BASE/server.js" --port "$PORT" >>"$LOG" 2>&1 </dev/null &
    fi
    i=0
    while [ $i -lt 20 ] && ! server_up; do sleep 1; i=$((i + 1)); done
    cd /
    status
}

status() {
    p=$(pids)
    if [ -z "$p" ]; then echo "server: not running (see $LOG)"; else echo "server: running (pid $p), http://127.0.0.1:$PORT/"; fi
    if taken; then echo "home: TV Home, $KIND version (sam: $(sam_type))"; else echo "home: LG's (sam: $(sam_type))"; fi
    w=$(watch_pids); echo "watchdog: ${w:-not running}"
    [ -n "$p" ]
}

# ---- TV Home in LG's Home's place -----------------------------------------------------
taken() { awk -v m="$LG_DIR" '$2 == m { f = 1 } END { exit !f }' /proc/mounts; }
sam_type() { luna getAppInfo "{\"id\":\"$HOME_ID\"}" | sed -n 's/.*"type": *"\([a-z]*\)".*/\1/p' | head -1; }
home_in_front() { luna getForegroundAppInfo '{}' | grep -q "\"appId\": *\"$HOME_ID\""; }

# sam drops and rereads the app's appinfo.json on a block and a release.
# (sh has no local variables: names here must not clash with take's)
reread() {
    rr_want=$1
    extra=""
    grep -q forceBlockSystemApp "$BLOCK_SCHEMA" 2>/dev/null && extra=',"forceBlockSystemApp":false'
    out=$(luna blockSystemApp "{\"id\":\"$HOME_ID\"$extra}")
    echo "$out" | grep -q '"returnValue": *true' || log "block refused: $(echo "$out" | tr -d '\n' | cut -c1-160)"
    n=0
    until luna releaseBlockSystemApp "{\"id\":\"$HOME_ID\"}" | grep -q '"returnValue": *true'; do
        n=$((n + 1)); [ $n -ge 3 ] && { log "WARNING: release failed"; break; }; sleep 1
    done
    i=0
    while [ $i -lt 10 ]; do
        [ "$(sam_type)" = "$rr_want" ] && return 0
        sleep 1; i=$((i + 1))
    done
    log "sam reports type '$(sam_type)', not '$rr_want'"
    return 1
}

# LG's Home: "flutter-client -i com.webos.app.home"; its memory snapshots
# (CRIU checkpoints) would bring it back as it was, so they go too.
stop_lg_home() {
    for d in /tmp/checkpoint /mnt/lg/cmn_data/checkpoint; do rm -rf "$d/$HOME_ID" "$d/hash_check_$HOME_ID"; done
    for p in /proc/[0-9]*; do
        case " $( { tr '\0' ' ' < "$p/cmdline"; } 2>/dev/null ) " in
            *" -i $HOME_ID "*) kill "${p#/proc/}" 2>/dev/null && log "stopped LG's Home (pid ${p#/proc/})" ;;
        esac
    done
}

stage() {
    mkdir -p "$APP"
    # LG's icon for ours, taken while LG's folder is still visible
    if ! taken && [ ! -f "$APP/icon.png" ]; then cp "$LG_DIR/icon.png" "$APP/icon.png" 2>/dev/null; fi
}

# take [qml|web]: switching between the two goes through LG's Home, so sam
# never has to go straight from one of our types to the other.
take() {
    tk_kind=${1:-$KIND}
    case "$tk_kind" in qml|web) ;; *) echo "take: qml or web"; return 2 ;; esac
    if taken && [ "$tk_kind" != "$KIND" ]; then give; fi
    KIND=$tk_kind; APP=$(app_dir "$KIND"); echo "$KIND" > "$BASE/kind"
    server_up || start >/dev/null
    server_up || { log "take: the server does not answer, LG's Home stays"; return 1; }
    stage
    front=0; home_in_front && front=1
    if ! taken; then
        mount --bind "$APP" "$LG_DIR" || { log "take: mount failed"; return 1; }
    fi
    # (at boot the mount can come before sam reads the apps: then it already has ours)
    if [ "$(sam_type)" != "$KIND" ] && ! reread "$KIND"; then
        log "take: sam did not take TV Home ($KIND), giving LG's Home back"
        give
        return 1
    fi
    log "take: sam has TV Home ($(cut -d' ' -f1 /proc/uptime) s)"
    stop_lg_home
    log "take: TV Home ($KIND) is the Home"
    if [ $front = 1 ]; then sleep 2; luna launch "{\"id\":\"$HOME_ID\"}" >/dev/null; fi
    return 0
}

give() {
    front=0; home_in_front && front=1
    n=0
    while taken && [ $n -lt 3 ]; do umount "$LG_DIR" 2>/dev/null || umount -l "$LG_DIR"; n=$((n + 1)); done
    taken && { log "give: LG's folder is still covered"; return 1; }
    reread flutter || log "give: sam has not taken LG's Home back yet"
    # ours closed (the web page in the web app manager, or the QML runner),
    # then LG's Home starts fresh
    luna-send -n 1 -w 5000 luna://com.palm.webappmanager/killApp "{\"appId\":\"$HOME_ID\"}" </dev/null >/dev/null 2>&1
    for p in /proc/[0-9]*; do
        case "$( { tr '\0' ' ' < "$p/cmdline"; } 2>/dev/null )" in
            *qml-runner*"$HOME_ID"*) kill "${p#/proc/}" 2>/dev/null && log "stopped TV Home's QML runner (pid ${p#/proc/})" ;;
        esac
    done
    for d in /tmp/checkpoint /mnt/lg/cmn_data/checkpoint; do rm -rf "$d/$HOME_ID" "$d/hash_check_$HOME_ID"; done
    log "give: LG's Home is back"
    if [ $front = 1 ]; then sleep 2; luna launch "{\"id\":\"$HOME_ID\"}" >/dev/null; fi
    return 0
}

# ---- watchdog: LG's Home back if TV Home stops answering --------------------------------
watch_pids() {
    for p in /proc/[0-9]*; do
        case "$( { tr '\0' ' ' < "$p/cmdline"; } 2>/dev/null )" in
            *"tv-home.sh watchloop"*) echo "${p#/proc/}" ;;
        esac
    done
}

screen_on() {
    s=$(luna-send -n 1 -w 5000 luna://com.webos.service.tvpower/power/getPowerState '{}' </dev/null 2>/dev/null)
    echo "$s" | grep -q '"state": *"Active"'
}

# UxAir (AirPlay receiver, if installed) runs in the background so devices can
# find it; it comes to the front by itself when one streams. Started with the
# app that is in front, which it hands the screen back to after ~2.5 s.
UXAIR=com.github.depius.uxair
uxair_running() { luna running '{}' | grep -q "\"id\": *\"$UXAIR\""; }
start_uxair() {
    [ -d "/media/developer/apps/usr/palm/applications/$UXAIR" ] || return 0
    uxair_running && return 0
    front=$(luna getForegroundAppInfo '{}' | sed -n 's/.*"appId": *"\([^"]*\)".*/\1/p')
    luna launch "{\"id\":\"$UXAIR\",\"params\":{\"background\":true,\"return_to\":\"${front:-$HOME_ID}\"}}" >/dev/null &&
        log "UxAir started in the background (back to ${front:-$HOME_ID})"
}

# Every 10 s while TV Home is the Home: the server must answer (restarted once
# if not), and while Home is on screen its page must have sent a heartbeat
# in the last 30 s. Twice in a row wrong: LG's Home back, and the watch ends.
watchloop() {
    bad=0; uxair_check=0
    while taken; do
        sleep 10
        # UxAir closed (or killed): back in the background, at most every 10
        # minutes and only while the Home screen shows (its window flashes up)
        uxair_check=$((uxair_check + 1))
        if [ $uxair_check -ge 60 ] && home_in_front && screen_on && ! uxair_running; then
            uxair_check=0; start_uxair
        fi
        if ! server_up; then
            log "watch: server not answering, restarting it"
            start >/dev/null
        fi
        problem=""
        server_up || problem="server down"
        if [ -z "$problem" ] && screen_on && home_in_front; then
            age=$(wget -q -T 3 -O - "http://127.0.0.1:$PORT/api/heartbeat" 2>/dev/null | sed -n 's/.*"age": *\([0-9]*\).*/\1/p')
            if [ -z "$age" ] || [ "$age" -gt 30000 ]; then problem="no heartbeat from the Home page (${age:-none} ms)"; fi
        fi
        if [ -n "$problem" ]; then bad=$((bad + 1)); else bad=0; fi
        if [ $bad -ge 2 ]; then
            log "watch: $problem - giving LG's Home back"
            give
            break
        fi
    done
}

watch_start() {
    for p in $(watch_pids); do kill "$p" 2>/dev/null; done
    if command -v setsid >/dev/null 2>&1; then
        setsid sh "$0" watchloop >/dev/null 2>>"$WLOG" </dev/null &   # log() writes to $WLOG itself
    else
        nohup sh "$0" watchloop >/dev/null 2>>"$WLOG" </dev/null &
    fi
}

case "$1" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    take) take "$2" && watch_start ;;
    reload)
        # TV Home's own files changed: close ours and open it again
        luna-send -n 1 -w 5000 luna://com.palm.webappmanager/killApp "{\"appId\":\"$HOME_ID\"}" </dev/null >/dev/null 2>&1
        for p in /proc/[0-9]*; do
            case "$( { tr '\0' ' ' < "$p/cmdline"; } 2>/dev/null )" in *qml-runner*"$HOME_ID"*) kill "${p#/proc/}" 2>/dev/null ;; esac
        done
        sleep 2; luna launch "{\"id\":\"$HOME_ID\"}" ;;
    give) for p in $(watch_pids); do kill "$p" 2>/dev/null; done; give ;;
    watchloop) watchloop ;;
    boot)
        # log() already writes to $WLOG; only errors go there besides
        exec >/dev/null 2>>"$WLOG" </dev/null
        log "boot: hook started ($(cut -d' ' -f1 /proc/uptime) s after power-on)"
        # First, before anything waits: our folder over LG's Home's, so the
        # next start of the Home is ours. LG's Home itself stays until take
        # replaces it on screen (stopped earlier, the TV would show the last
        # input until then).
        stage
        taken || mount --bind "$APP" "$LG_DIR" || log "boot: mount failed"
        start >/dev/null
        log "boot: server up ($(cut -d' ' -f1 /proc/uptime) s)"
        i=0; until luna getForegroundAppInfo '{}' | grep -q '"returnValue": *true' || [ $i -ge 60 ]; do sleep 2; i=$((i + 1)); done
        log "boot: app manager answers ($(cut -d' ' -f1 /proc/uptime) s)"
        take && watch_start
        # nothing on screen (LG's Home stopped before it was replaced): ours
        if luna getForegroundAppInfo '{}' | grep -q '"appId": *""'; then
            log "boot: nothing on screen, opening TV Home"; luna launch "{\"id\":\"$HOME_ID\"}" >/dev/null
        fi
        sleep 3; start_uxair
        log "boot: done ($(cut -d' ' -f1 /proc/uptime) s after power-on)" ;;
    *) echo "usage: sh $0 start | stop | status | take [qml|web] | give | reload | boot"; exit 2 ;;
esac
