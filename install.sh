#!/bin/sh
# install.sh - runs on the TV, from the files Install-TVHome.ps1 sent in the
# same SSH connection (so the root password is asked only once): checks the
# TV, installs TV Home into /home/root/tv-home, sets up the boot hook, adds an
# SSH key if one was sent, and makes TV Home the TV's Home screen.
#
# Prints CHECK_FAILED, INSTALL_OK, then APPLIED or NEED_TTY (the app manager
# gave no answer in this kind of SSH session) for the PC to act on.

# LG's own tools first: this plain ssh session has the Homebrew Channel's bin
# folder at the front of PATH, and the luna-send found there gets no answer
# from the app manager.
PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH
export PATH

NEW=$(cd "$(dirname "$0")" && pwd)
DEST=/home/root/tv-home
HOOK=/var/lib/webosbrew/init.d/70-tv-home
LG_HOME=/usr/palm/applications/com.webos.app.home
UPLOAD=/tmp/tvh-upload   # where Install-TVHome.ps1 unpacks the files

# Only the upload folder is ever deleted, never wherever else this was run from.
cleanup() { [ "$NEW" = "$UPLOAD" ] && rm -rf "$UPLOAD"; }
fail() { echo "CHECK_FAILED: $*"; cleanup; exit 3; }

ver=$(sed -n 's/.*"webos_release" *: *"\([^"]*\)".*/\1/p' /var/run/nyx/os_info.json 2>/dev/null)
echo "webOS ${ver:-unknown}"
case "$ver" in
    10.*) ;;
    *) [ -f "$NEW/force" ] || fail "made and tested for webOS 10.x; this TV runs ${ver:-an unknown version}" ;;
esac
[ -d /var/lib/webosbrew/init.d ] || fail "the Homebrew Channel's startup folder is missing (/var/lib/webosbrew/init.d)"
[ -x /usr/bin/node ] || fail "the TV has no Node.js (/usr/bin/node)"
[ -x /usr/bin/qml-runner ] || fail "the TV has no QML app runner (/usr/bin/qml-runner)"
[ -d "$LG_HOME" ] || fail "LG's Home app is missing ($LG_HOME)"
[ -f "$NEW/tv/tv-home.sh" ] || fail "the upload is incomplete"
# Another Home replacement (Glasshouse, for one) in LG's Home's place: only
# one can be the Home, and ours would take its mount for its own.
if awk -v m="$LG_HOME" '$2 == m { f = 1 } END { exit !f }' /proc/mounts; then
    cur=$(stat -c %d:%i "$LG_HOME" 2>/dev/null)
    ours=""
    for d in app app-qml; do
        [ -d "$DEST/$d" ] && [ "$(stat -c %d:%i "$DEST/$d" 2>/dev/null)" = "$cur" ] && ours=1
    done
    [ -n "$ours" ] || fail "another Home screen (Glasshouse Home?) has taken LG's Home's place; switch it off first (Glasshouse: Use LG Home), then run this again"
fi

mkdir -p "$DEST" || fail "cannot create $DEST"

# Program files: a new copy, then renamed into place, so a running script
# (the watchdog runs tv-home.sh) keeps reading its old copy undisturbed.
for f in tv-home.sh server.js iconfill.js boot-hook.sh; do
    cp "$NEW/tv/$f" "$DEST/$f.new" && mv -f "$DEST/$f.new" "$DEST/$f" || fail "cannot write $DEST/$f"
done
chmod 755 "$DEST/tv-home.sh" "$DEST/boot-hook.sh"
# App folders file by file: while TV Home is the Home, app-qml (or app) is
# mounted over LG's Home's folder and must stay the same folder.
for d in app app-qml ui; do
    mkdir -p "$DEST/$d" && cp -R "$NEW/tv/$d/." "$DEST/$d/" || fail "cannot write $DEST/$d"
done
cp "$NEW/config.json" "$DEST/config.json" || fail "cannot write $DEST/config.json"
# Photos only when new ones were sent; the dock (state.json) always stays.
if [ -d "$NEW/photos" ]; then
    rm -rf "$DEST/photos.new" && cp -R "$NEW/photos" "$DEST/photos.new" &&
        rm -rf "$DEST/photos" && mv "$DEST/photos.new" "$DEST/photos" || fail "cannot write $DEST/photos"
    echo "$(ls "$DEST/photos" | wc -l) photo(s) installed"
fi
mkdir -p "$DEST/photos"
[ -f "$DEST/kind" ] || echo qml > "$DEST/kind"
chown -R root:root "$DEST"
ln -sf "$DEST/boot-hook.sh" "$HOOK"

# An SSH key from the PC: from the next TV start the Homebrew Channel then
# turns password logins off and only this key gets in.
if [ -f "$NEW/authorized_key.pub" ]; then
    mkdir -p /home/root/.ssh && chmod 700 /home/root/.ssh
    key=$(cat "$NEW/authorized_key.pub")
    if ! grep -qF "$key" /home/root/.ssh/authorized_keys 2>/dev/null; then
        echo "$key" >> /home/root/.ssh/authorized_keys
        echo "SSH key added"
    fi
    chmod 600 /home/root/.ssh/authorized_keys
fi
# Out of the folder before it goes, and away from the upload stream: stdin
# is still the ssh channel the files came through (tar stops reading at the
# end of the archive), and with that luna-send got no answer.
cd /
cleanup
exec </dev/null
echo INSTALL_OK

# Make it the Home now, if the app manager answers in this session.
. /etc/profile >/dev/null 2>&1
PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH
answer=$(luna-send -n 1 -w 3000 luna://com.webos.applicationManager/getForegroundAppInfo '{}' 2>&1)
if ! echo "$answer" | grep -q '"returnValue": *true'; then
    echo "app manager answer: $answer" | cut -c1-300
    echo NEED_TTY
    exit 0
fi
kind=$(cat "$DEST/kind")
if awk -v m="$LG_HOME" '$2 == m { f = 1 } END { exit !f }' /proc/mounts; then
    # already the Home: the new server, the watchdog with the new script, the new page
    sh "$DEST/tv-home.sh" start >/dev/null
    sh "$DEST/tv-home.sh" take "$kind" >/dev/null
    sh "$DEST/tv-home.sh" reload >/dev/null
else
    sh "$DEST/tv-home.sh" take "$kind"
fi
sh "$DEST/tv-home.sh" status
sh "$DEST/tv-home.sh" status | grep -q '^home: TV Home' && echo APPLIED || echo NOT_APPLIED
