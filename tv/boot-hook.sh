#!/bin/sh
# TV Home at boot: the Homebrew Channel runs this from
# /var/lib/webosbrew/init.d/70-tv-home (without arguments). In the background,
# so the TV's start is not held up while it waits for the app manager.
# To stop TV Home starting at boot: rm /var/lib/webosbrew/init.d/70-tv-home
[ -f /home/root/tv-home/tv-home.sh ] && sh /home/root/tv-home/tv-home.sh boot &
exit 0
