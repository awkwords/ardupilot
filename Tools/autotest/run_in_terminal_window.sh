#!/usr/bin/env bash
# Tools/autotest/run_in_terminal_window.sh
#
# Purpose:
#   Launch a command in an appropriate terminal; if no GUI/terminal is available,
#   run it headless and log stdout/stderr to a file.
#
# Enhancements (PR):
#   - Allow overriding fallback log path via env:
#       * Preferred: RITW_LOGFILE or RITW_LOGDIR
#       * Back-compat aliases: SITL_LOGFILE or SITL_LOGDIR
#     Defaults to /tmp/<name>.log when unset.
#   - Use 'command -v' instead of 'which' for portability.
#   - Ensure parent directory exists for custom log path.
#   - Keep subshell in fallback branch (required by upstream comment).
#
# Behavior:
#   Unchanged unless the above env vars are set.

name="$1"
shift
echo "RiTW: Starting $name : $*"

# default minimize behavior for some terminals
if [ -z "$SITL_RITW_MINIMIZE" ]; then
    SITL_RITW_MINIMIZE=1
fi

if [ -n "$SITL_RITW_TERMINAL" ]; then
  # Caller provided a terminal launcher (e.g. "screen -D -m", "gnome-terminal -e")
  # Create a temp script so we can hand over argv cleanly across terminal variants
  : "${TMPDIR:=/tmp}"
  FILENAME="ritw-$(date '+%Y%m%d%H%M%S')"
  FILEPATH="$TMPDIR/$FILENAME"
  echo "#!/bin/sh" >"$FILEPATH"
  printf "%q " "$@" >>"$FILEPATH"
  chmod +x "$FILEPATH"
  $SITL_RITW_TERMINAL "$FILEPATH" &

elif [ -n "$TMUX" ]; then
  tmux new-window -dn "$name" "$TMUX_PREFIX $*"

elif [ -n "$DISPLAY" ] && command -v osascript >/dev/null 2>&1; then
  # macOS: open a new Terminal window/tab and run the command
  osascript -e 'tell application "Terminal" to do script "'"cd $(pwd) && clear && $* "'"'

elif [ -n "$DISPLAY" ] && command -v xterm >/dev/null 2>&1; then
  if [ "$SITL_RITW_MINIMIZE" -eq 1 ]; then
      ICONIC=-iconic
  fi
  xterm $ICONIC -xrm 'XTerm*selectToClipboard: true' -xrm 'XTerm*initialFont: 6' \
        -n "$name" -name "$name" -T "$name" -hold -e $* &

elif [ -n "$DISPLAY" ] && command -v konsole >/dev/null 2>&1; then
  konsole --hold -e $*

elif [ -n "$DISPLAY" ] && command -v gnome-terminal >/dev/null 2>&1; then
  gnome-terminal -e "$*"

elif [ -n "$STY" ]; then
  # GNU screen session
  screen -X screen -t "$name" bash -c "cd $PWD; $*"

elif [ -n "$ZELLIJ" ]; then
  # zellij session
  zellij run -n "$name" -- "$1" "${@:2}"

else
  # ------------------------------
  # Fallback: run headless + log
  # ------------------------------
  # Prefer generic RITW_*; accept SITL_* as aliases
  LOGFILE="${RITW_LOGFILE:-${SITL_LOGFILE:-}}"
  LOGDIR="${RITW_LOGDIR:-${SITL_LOGDIR:-}}"

  if [ -n "$LOGFILE" ]; then
      # Ensure parent dir exists if LOGFILE is specified
      mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true
      filename="$LOGFILE"
  elif [ -n "$LOGDIR" ]; then
      mkdir -p "$LOGDIR" 2>/dev/null || true
      filename="$LOGDIR/$name.log"
  else
      filename="/tmp/$name.log"
  fi

  echo "RiTW: Window access not found, logging to $filename"
  cmd="$1"
  shift
  # Keep subshell (see upstream note: preserves parent for _fdm_input_step)
  ( : ; "$cmd" "$@" &>"$filename" < /dev/null ) &
fi

exit 0
