#!/usr/bin/env bash
# Runs a command that tests the app on this Mac while no other script does.
#
#   scripts/storekit-lock.sh xcodebuild test ...
#
# StoreKit Testing keeps one transaction store per bundle ID on the Mac, and
# every process with an SKTestSession can change it: a UI test runner's
# clearTransactions() wiped a purchase the app tests of another worktree had
# just made, within a second (MM-110, docs/testing.md). The lock inside the
# app tests (StoreKitTestLock) cannot see a UI test runner: the runner is not
# the sandboxed app, so it has another temporary directory, and the shell cannot
# read the app's container either. A file in /tmp is one place every script of
# every worktree can reach, so the scripts take this lock around each macOS
# test run; iOS Simulator runs keep their own store and do not take it.
set -euo pipefail

lock=/tmp/asia.xdev.mindmapai.storekit-tests.lock
# Long enough for a whole macOS UI test run to finish first; a hung run fails
# this one instead of stalling it forever.
timeout=${STOREKIT_LOCK_TIMEOUT:-3600}

if [[ $# -eq 0 ]]; then
  echo "usage: $0 command [arguments]" >&2
  exit 64
fi

# lockf waits silently; say why the run has not started yet.
if ! lockf -k -s -t 0 "$lock" true 2>/dev/null; then
  echo "Waiting for another test run of the app on this Mac (StoreKit lock, up to ${timeout}s)" >&2
fi
# -k keeps the file, so every waiter locks the same inode.
exec lockf -k -t "$timeout" "$lock" "$@"
