#!/usr/bin/env bash
# Quits a running PopShot. SIGTERM lets it restore Apple's thumbnail setting on the way out;
# if it hasn't exited after 10 s (e.g. macOS is still scanning a brand-new build), force-quit it.
pgrep -x PopShot >/dev/null || exit 0
pkill -TERM -x PopShot || true
for _ in $(seq 1 50); do
  pgrep -x PopShot >/dev/null || exit 0
  sleep 0.2
done
pkill -KILL -x PopShot || true
exit 0
