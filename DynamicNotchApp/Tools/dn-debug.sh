#!/bin/bash
# dn-debug.sh — send DEBUG commands to a DynamicNotch development instance (DebugCommandRegistry,
# Sources/Support/DebugHooks-Registry.swift). DEBUG builds only; release builds ignore all of this.
#
#   dn-debug.sh -c <channel> <command> [<command>…]   post each command (distributed notification
#                                                      "com.example.dynamicnotch.debug.<channel>")
#   dn-debug.sh -c <channel> -f <file> <command>…     append the commands to a command file instead
#                                                      (the instance was launched with
#                                                      -DNDebugCommandFile <file>; use this when
#                                                      distributed notifications do not arrive)
#   dn-debug.sh -c <channel> [-f <file>] help [<filter>]   print the registered commands
#   dn-debug.sh -c <channel> [-f <file>] ping          check delivery (waits up to 5 s for "pong")
#   dn-debug.sh -c <channel> launch <App.app> [<command>…]
#                                                      start a development instance in the background:
#                                                      DN_DEBUG_CHANNEL=<channel>, DN_DEBUG_OFFSCREEN=1
#                                                      (override with DN_DEBUG_OFFSCREEN=0), a command
#                                                      file (printed; also reachable with -f), and the
#                                                      commands as -DNDebugCommand launch arguments.
#                                                      Refuses the user's bundle id
#                                                      (com.example.dynamicnotch.DynamicNotch): build the
#                                                      dev instance with PRODUCT_BUNDLE_IDENTIFIER=….dev.
#   dn-debug.sh [-p <process>] log                     stream the instance's debug log lines
#
# The channel defaults to $DN_DEBUG_CHANNEL. Without one the commands would reach the user's own
# instance (the unnamed channel), so the script refuses unless --user-instance is given.
# Commands are "<verb>[:<arg>]"; snapshot commands take "<dir>?appearance=dark|light|both&glass=off|on|both".
# In a launch-argument / command-file sequence, `wait:<seconds>` pauses and `quit` ends the instance.
set -euo pipefail

base="com.example.dynamicnotch.debug"
user_bundle_id="com.example.dynamicnotch.DynamicNotch"
channel="${DN_DEBUG_CHANNEL:-}"
command_file=""
process="DynamicNotch"
user_instance=0

usage() { sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    -c|--channel) channel="$2"; shift 2 ;;
    -f|--file) command_file="$2"; shift 2 ;;
    -p|--process) process="$2"; shift 2 ;;
    --user-instance) user_instance=1; shift ;;
    -h|--help) usage 0 ;;
    --) shift; break ;;
    -*) echo "dn-debug: unknown option $1" >&2; usage 2 ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || usage 2

name="$base"
if [ -n "$channel" ]; then
  name="$base.$channel"
elif [ "$user_instance" != 1 ] && [ "$1" != "log" ]; then
  echo "dn-debug: no channel (-c <channel> or DN_DEBUG_CHANNEL). The unnamed channel reaches the user's" >&2
  echo "          own instance; pass --user-instance if that is really meant." >&2
  exit 2
fi

post() { # post <command>
  if [ -n "$command_file" ]; then
    printf '%s\n' "$1" >> "$command_file"
  else
    /usr/bin/osascript -l JavaScript - "$name" "$1" >/dev/null <<'JXA'
ObjC.import('Foundation');
function run(argv) {
  $.NSDistributedNotificationCenter.defaultCenter
    .postNotificationNameObjectUserInfoDeliverImmediately(argv[0], argv[1], $(), true);
}
JXA
  fi
}

wait_for() { # wait_for <file> <seconds>
  local i=0 n=$(( $2 * 10 ))
  while [ ! -s "$1" ] && [ $i -lt $n ]; do /bin/sleep 0.1; i=$((i + 1)); done
  [ -s "$1" ]
}

case "$1" in
  help)
    out="$(/usr/bin/mktemp -t dn-debug-help)"; rm -f "$out"
    filter="${2:-}"
    # help:<file> writes the full list; filter locally
    post "help:$out"
    if wait_for "$out" 5; then
      if [ -n "$filter" ]; then grep -i -- "$filter" "$out" || true; else cat "$out"; fi
      rm -f "$out"
    else
      echo "dn-debug: no answer on $name within 5 s (instance running? DEBUG build? try -f <command file>)" >&2
      exit 1
    fi
    ;;
  ping)
    out="$(/usr/bin/mktemp -t dn-debug-ping)"; rm -f "$out"
    post "ping:$out"
    if wait_for "$out" 5; then cat "$out"; rm -f "$out"; else
      echo "dn-debug: no pong on $name within 5 s" >&2; exit 1
    fi
    ;;
  launch)
    shift
    app="${1:?launch needs the path of the .app}"; shift
    [ -n "$channel" ] || { echo "dn-debug: launch needs a channel" >&2; exit 2; }
    plist="$app/Contents/Info.plist"
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
    exe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
    if [ "$bundle_id" = "$user_bundle_id" ]; then
      echo "dn-debug: $app has the user's bundle id ($bundle_id); build the dev instance with" >&2
      echo "          PRODUCT_BUNDLE_IDENTIFIER=$user_bundle_id.dev (separate settings, tray, SwiftData)." >&2
      exit 2
    fi
    file="${command_file:-$(/usr/bin/mktemp -t "dn-debug-$channel")}"
    : > "$file"
    args=(-DNDebugCommandFile "$file")
    for c in "$@"; do args+=(-DNDebugCommand "$c"); done
    logfile="${file}.log"
    DN_DEBUG_CHANNEL="$channel" DN_DEBUG_OFFSCREEN="${DN_DEBUG_OFFSCREEN:-1}" \
      /usr/bin/nohup "$app/Contents/MacOS/$exe" "${args[@]}" >"$logfile" 2>&1 &
    echo "pid $! channel $channel bundle $bundle_id"
    echo "command file $file   (dn-debug.sh -c $channel -f $file <command>)"
    echo "stdout/stderr $logfile"
    ;;
  log)
    exec /usr/bin/log stream --style compact --predicate "process == \"$process\" AND eventMessage CONTAINS \"[\""
    ;;
  *)
    for c in "$@"; do post "$c"; done
    ;;
esac
