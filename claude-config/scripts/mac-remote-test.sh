#!/usr/bin/env bash
# Run an Xcode test action on a remote Mac instead of on this one.
#
# macOS XCUITest has no headless mode: it activates the real app in the real
# WindowServer session and delivers synthesized keystrokes to whatever is
# frontmost. Running it locally makes the machine unusable for the length of the
# run and corrupts results in both directions — your typing lands in the app
# under test, the test's keystrokes land in your window. So the run is shipped
# to a dedicated Mac.
#
# Usage (from anywhere inside the project):
#   mac-remote-test.sh <-only-testing target>   # e.g. MyUITests/SomeTests
#   mac-remote-test.sh --all                    # every test in the scheme
#   mac-remote-test.sh --build-only             # compile + sign, no GUI
#
# This script knows nothing about any particular project or machine. It reads:
#
#   <project root>/.cc-remote-test.conf   what to build      (committed with the project)
#   ~/.claude/remote-test.conf            which Mac to use   (per machine, not in any repo)
#
# both plain shell fragments, and both optional if the corresponding CC_MAC_*
# environment variables are set instead. Precedence, highest first:
#
#   environment  >  project conf  >  machine conf  >  built-in default
#
# The project root is found by walking up from $PWD looking for the project
# conf, so the script works from any subdirectory.
#
# THE ONE NON-OBVIOUS REQUIREMENT: the tmux server on the remote Mac must have
# been started from its GUI login session. A server started over ssh cannot use
# the signing private key (codesign fails with errSecInternalComponent, because
# the login keychain is locked and there is no way to prompt) and cannot be
# granted the automation TCC prompt ("Timed out while enabling automation
# mode"). Injecting into a GUI-owned server with `ssh … tmux send-keys` is fine;
# only the server's origin matters.

set -uo pipefail

# ------------------------------------------------------------- config --------
PROJECT_CONF_NAME=".cc-remote-test.conf"
MACHINE_CONF="${CC_MAC_MACHINE_CONF:-$HOME/.claude/remote-test.conf}"

# Walk up from $PWD for the project conf. Its directory is the project root.
find_project_root() {
  local d="$PWD"
  while [ "$d" != "/" ]; do
    [ -f "$d/$PROJECT_CONF_NAME" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  return 1
}

# Defaults live here so a conf only has to state what differs.
SCHEME=""
XCODE_PROJECT=""          # e.g. Foo.xcodeproj — or leave empty and set XCODE_WORKSPACE
XCODE_WORKSPACE=""
CONFIGURATION="Debug"
DESTINATION="platform=macOS"
SESSION=""                # defaults to claude-running-<project dir name>
SEED_HINT=""              # project-specific advice printed when every test skips
RSYNC_EXCLUDES=('.git/' '.DS_Store' 'DerivedData/' 'build/' '*.xcresult' 'node_modules/')

# shellcheck source=/dev/null
[ -f "$MACHINE_CONF" ] && . "$MACHINE_CONF"

if LOCAL_DIR="$(find_project_root)"; then
  # shellcheck source=/dev/null
  . "$LOCAL_DIR/$PROJECT_CONF_NAME"
else
  LOCAL_DIR="${CC_MAC_LOCAL_DIR:-}"
  if [ -z "$LOCAL_DIR" ]; then
    echo "No $PROJECT_CONF_NAME found in $PWD or any parent." >&2
    echo "Create one at the project root, e.g.:" >&2
    echo "    SCHEME=MyMacApp" >&2
    echo "    XCODE_PROJECT=MyApp.xcodeproj" >&2
    echo "Or set CC_MAC_LOCAL_DIR and CC_MAC_SCHEME." >&2
    exit 2
  fi
fi

# Environment wins over both conf files.
REMOTE="${CC_MAC_REMOTE:-${REMOTE:-}}"
REMOTE_BASE="${CC_MAC_REMOTE_BASE:-${REMOTE_BASE:-Coding}}"
if [ -z "$REMOTE" ]; then
  echo "No remote Mac configured. Create $MACHINE_CONF:" >&2
  echo "    REMOTE=<ssh host alias from ~/.ssh/config>" >&2
  echo "    REMOTE_BASE=Coding        # relative to that host's home" >&2
  echo "Or set CC_MAC_REMOTE." >&2
  exit 2
fi
SCHEME="${CC_MAC_SCHEME:-$SCHEME}"
CONFIGURATION="${CC_MAC_CONFIGURATION:-$CONFIGURATION}"
DESTINATION="${CC_MAC_DESTINATION:-$DESTINATION}"
TMUX_BIN="${CC_MAC_TMUX_BIN:-${TMUX_BIN:-/opt/homebrew/bin/tmux}}"
SHOTS_DIR="${CC_MAC_SHOTS:-${SHOTS_DIR:-$HOME/Temp/cc-shots}}"

PROJECT_NAME="$(basename "$LOCAL_DIR")"
SESSION="${CC_MAC_TMUX:-${SESSION:-claude-running-$PROJECT_NAME}}"

# Remote paths stay relative to the remote home, so no remote username is ever
# written down and the same conf works whoever the account belongs to.
REMOTE_DIR="${CC_MAC_REMOTE_DIR:-$REMOTE_BASE/$PROJECT_NAME}"
DERIVED="${CC_MAC_DERIVED:-DerivedData/$PROJECT_NAME}"

if [ -z "$SCHEME" ]; then
  echo "SCHEME is not set (project conf: $LOCAL_DIR/$PROJECT_CONF_NAME)" >&2
  exit 2
fi
if [ -n "$XCODE_WORKSPACE" ]; then
  PROJECT_ARG=(-workspace "$XCODE_WORKSPACE")
elif [ -n "$XCODE_PROJECT" ]; then
  PROJECT_ARG=(-project "$XCODE_PROJECT")
else
  PROJECT_ARG=()          # let xcodebuild discover it
fi

RUNID="$(date +%Y%m%d-%H%M%S)"
RLOG="/tmp/ccmac-$RUNID.log"
RRC="/tmp/ccmac-$RUNID.rc"
RSCRIPT="/tmp/ccmac-$RUNID.sh"
RESULT="/tmp/ccmac-$RUNID.xcresult"

BUILD_ONLY=0
ONLY_TESTING=""
case "${1:-}" in
  --build-only) BUILD_ONLY=1 ;;
  --all)        ONLY_TESTING="" ;;
  "")  echo "usage: $(basename "$0") <-only-testing target> | --all | --build-only" >&2; exit 2 ;;
  -*)  echo "unknown option: $1" >&2; exit 2 ;;
  *)   ONLY_TESTING="$1" ;;
esac

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o ForwardX11=no -o ForwardX11Trusted=no)
ssh_q() { ssh "${SSH_OPTS[@]}" "$REMOTE" "$@"; }
export RSYNC_RSH="ssh ${SSH_OPTS[*]}"

RSYNC_ARGS=()
for x in "${RSYNC_EXCLUDES[@]}"; do RSYNC_ARGS+=(--exclude "$x"); done

# ---------------------------------------------------------------- 1. sync ----
# --delete makes the remote a strict mirror: nothing is edited there, so there
# is never a question of which copy is authoritative. .git is excluded on
# purpose — the remote is a build slave, not a second working copy.
say "sync $PROJECT_NAME -> $REMOTE:$REMOTE_DIR"
rsync -az --delete "${RSYNC_ARGS[@]}" \
  "$LOCAL_DIR/" "$REMOTE:$REMOTE_DIR/" || { echo "rsync failed" >&2; exit 1; }

pending=$(rsync -an --delete "${RSYNC_ARGS[@]}" \
  "$LOCAL_DIR/" "$REMOTE:$REMOTE_DIR/" 2>/dev/null \
  | grep -vcE '^(sending|created|building|$)')
echo "in sync (pending transfers: $pending)"

# ------------------------------------------------------- 2. remote runner ----
# Written as a file rather than inlined into send-keys: quoting a command
# through ssh -> tmux -> the remote shell mangles $? and friends, and that
# failure is silent. A script file has one layer of quoting.
if [ "$BUILD_ONLY" = 1 ]; then
  ACTION="build-for-testing"
  ONLY_ARG=""
else
  ACTION="test-without-building"
  [ -n "$ONLY_TESTING" ] && ONLY_ARG="-only-testing:$ONLY_TESTING" || ONLY_ARG=""
fi

ssh_q "cat > $RSCRIPT" <<REMOTE_SCRIPT
#!/bin/bash
cd "\$HOME/$REMOTE_DIR" || exit 1
NSUnbufferedIO=YES env -u CC -u CXX xcodebuild $ACTION \\
  ${PROJECT_ARG[*]} \\
  -scheme "$SCHEME" \\
  -configuration "$CONFIGURATION" \\
  -destination "$DESTINATION" \\
  -derivedDataPath "\$HOME/$DERIVED" \\
  -resultBundlePath "$RESULT" \\
  -allowProvisioningUpdates $ONLY_ARG
echo \$? > "$RRC"
REMOTE_SCRIPT

# ------------------------------------------------------------- 3. launch -----
say "launch in $SESSION on $REMOTE  (action: $ACTION)"
ssh_q "$TMUX_BIN has-session -t $SESSION 2>/dev/null" || {
  echo "tmux session '$SESSION' is missing on $REMOTE." >&2
  echo "It must be created FROM THE GUI SESSION (Screen Sharing -> Terminal.app):" >&2
  echo "    $TMUX_BIN new-session -d -s $SESSION" >&2
  echo "A session started over ssh cannot use the signing key and cannot be" >&2
  echo "granted the automation TCC prompt." >&2
  exit 1
}
# pipe-pane WITHOUT -o: the -o form toggles, so a second run would silently
# turn logging back off and every progress read would come back empty.
ssh_q "$TMUX_BIN pipe-pane -t $SESSION; $TMUX_BIN pipe-pane -t $SESSION 'cat >> $RLOG'"
ssh_q "$TMUX_BIN send-keys -t $SESSION 'bash $RSCRIPT' Enter"

# --------------------------------------------------------------- 4. wait -----
say "running (Ctrl-C here does not stop $REMOTE; see 'kill run' below)"
start=$(date +%s)
rc=""
while :; do
  rc=$(ssh_q "cat $RRC 2>/dev/null" || true)
  [ -n "$rc" ] && break
  elapsed=$(( $(date +%s) - start ))
  last=$(ssh_q "tr -d '\r' < $RLOG 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' \
        | grep -aoE '(Test Case|Compiling|Signing|CodeSign|Touching|Ld )[^\"]{0,70}' | tail -1" || true)
  printf '\r  %4ds  %s\033[K' "$elapsed" "${last:-…}"
  sleep 15
done
elapsed=$(( $(date +%s) - start ))
printf '\r  %4ds  finished (rc=%s)\033[K\n' "$elapsed" "$rc"

ssh_q "$TMUX_BIN pipe-pane -t $SESSION" || true

# ------------------------------------------------------------ 5. results -----
say "results"
if [ "$BUILD_ONLY" = 1 ]; then
  ssh_q "tr -d '\r' < $RLOG | sed 's/\x1b\[[0-9;]*m//g' | grep -aE 'error:|BUILD SUCCEEDED|BUILD FAILED' | sort -u | head -20"
  ssh_q "rm -f $RSCRIPT $RRC $RLOG"
  exit "${rc:-1}"
fi

mkdir -p "$SHOTS_DIR"
LOCAL_RESULT="$SHOTS_DIR/$PROJECT_NAME-$RUNID.xcresult"
rsync -az "$REMOTE:$RESULT/" "$LOCAL_RESULT/" 2>/dev/null && echo "xcresult -> $LOCAL_RESULT"

summary=$(xcrun xcresulttool get test-results summary --path "$LOCAL_RESULT" 2>/dev/null)
if [ -n "$summary" ]; then
  passed=$(printf '%s' "$summary"  | plutil -extract passedTests  raw -o - - 2>/dev/null)
  failed=$(printf '%s' "$summary"  | plutil -extract failedTests  raw -o - - 2>/dev/null)
  skipped=$(printf '%s' "$summary" | plutil -extract skippedTests raw -o - - 2>/dev/null)
  echo "passed=${passed:-?}  failed=${failed:-?}  skipped=${skipped:-?}"

  # A run where every test skipped still reports TEST SUCCEEDED. On a fresh
  # remote machine that is the normal outcome, and it looks exactly like a pass.
  if [ "${skipped:-0}" != "0" ] && [ "${passed:-0}" = "0" ]; then
    echo "FALSE GREEN: every test skipped — $REMOTE probably lacks the data these tests need." >&2
    [ -n "$SEED_HINT" ] && echo "$SEED_HINT" >&2
    rc=1
  fi
else
  ssh_q "tr -d '\r' < $RLOG | sed 's/\x1b\[[0-9;]*m//g' | grep -aE 'error:|failed|TEST SUCCEEDED|TEST FAILED' | sort -u | head -20"
fi

echo
echo "  attachments : xcrun xcresulttool export attachments --path $LOCAL_RESULT --output-path <dir>"
echo "  watch live  : ssh -t $REMOTE $TMUX_BIN attach -t $SESSION"
echo "  kill run    : ssh $REMOTE $TMUX_BIN send-keys -t $SESSION C-c"

ssh_q "rm -f $RSCRIPT $RRC $RLOG; rm -rf $RESULT" || true
exit "${rc:-1}"
