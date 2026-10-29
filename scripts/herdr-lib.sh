# Shared by the herdr-* scripts. Spaces opened on a git repository get a
# throwaway worktree under $WORKTREE_ROOT, created on open and removed on
# close; nothing outside $WORKTREE_ROOT is ever removed.

herdr="${HERDR_BIN_PATH:-herdr}"
WORKTREE_ROOT="$HOME/.herdr/worktrees"

is_managed() {
  [[ "$1" == "$WORKTREE_ROOT"/* ]]
}

# The main checkout a worktree belongs to.
repo_of() {
  dirname "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)"
}

# The left hand (terminal) pane of a space's active tab, as "<id>\t<cwd>".
# Like Koba, its live directory decides the space's branch, ticket and PR.
terminal_pane() {
  local tab
  tab=$("$herdr" workspace get "$1" | jq -r '.result.workspace.active_tab_id')
  "$herdr" pane list --workspace "$1" \
    | jq -r --arg tab "$tab" '[.result.panes[] | select(.tab_id == $tab)][0] | [.pane_id, .cwd] | @tsv'
}

# Moves a worktree into the trash (instant, unlike deleting node_modules) and
# drops git's record of it. Branches are untouched.
discard_worktree() {
  local dir="$1" repo
  repo=$(repo_of "$dir")
  mkdir -p "$WORKTREE_ROOT/.trash"
  mv "$dir" "$WORKTREE_ROOT/.trash/$(openssl rand -hex 4)"
  git -C "$repo" worktree prune
}

# Deletes trashed worktrees in the background. A deletion cut short (herdr
# kills a popup's processes when it closes) is finished by the next call.
empty_trash() {
  (rm -rf "$WORKTREE_ROOT/.trash/"*) > /dev/null 2>&1 &
  disown
}

# Prints why a worktree can't be thrown away, or nothing when it can.
# Commits only reachable from a detached HEAD count: removing the worktree
# would strand them.
unsafe_reason() {
  local dir="$1" changes stranded
  changes=$(git -C "$dir" status --porcelain)
  stranded=$(git -C "$dir" log --oneline HEAD --not --branches --remotes --tags)
  if [[ -n "$changes" ]]; then
    printf 'uncommitted changes:\n%s\n' "$changes"
  fi
  if [[ -n "$stranded" ]]; then
    printf 'commits not on any branch:\n%s\n' "$stranded"
  fi
}

# Runs a command behind a progress line, ticked off when it finishes.
step() {
  local message="$1"
  shift
  printf '  … %s' "$message"
  if "$@" > /dev/null 2>&1; then
    printf '\r\033[K  ✓ %s\n' "$message"
  else
    printf '\r\033[K  ✗ %s\n' "$message"
    return 1
  fi
}

# Keeps a failing popup open long enough to read why.
if [[ -t 0 ]]; then
  trap 'printf "\n  something went wrong, any key to close"; read_key > /dev/null' ERR
fi

# Ticket key at the start of a branch's last path component, as in Koba:
# "ari-123-fix" and "alice/ARI-123" both give ARI-123.
ticket_from_branch() {
  sed -nE 's#^([A-Za-z]{2,10})-([0-9]{1,6})([-_].*)?$#\1-\2#p' <<< "${1##*/}" \
    | tr '[:lower:]' '[:upper:]'
}

# Waits for one key and prints "esc", or the key itself.
read_key() {
  local key
  IFS= read -rsn1 key
  [[ "$key" == $'\e' ]] && key=esc
  printf '%s' "$key"
}
