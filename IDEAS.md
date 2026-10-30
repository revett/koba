# Ideas

1. Sessions spawning sessions: `scripts/herdr-spawn` plus a `/fanout` skill that opens a worktree
   space per ticket with Claude or Codex started on a prompt
2. Fix notifications: switch `ui.toast.delivery` to `system`, since Herdr.app drops Ghostty's
   terminal notifications
3. Install Herdr's official agent skill (`herdr --skill`) into `~/.claude/skills` so Claude can
   drive Herdr
4. PR board popup in the palette ("GitHub → My PRs") showing each space's PR with checks and review
   state
5. Cursor cloud handoff: let `/fanout` send a ticket to a Cursor cloud agent instead of a local pane
6. Cmd+1..9 to jump to a space
7. Try the shep plugin to start a review agent automatically when tagged as a PR reviewer
8. Browser in a new tab: open a session's local HTML (e.g. from `/html`) as a tab in its space, with
   the native page shown whenever that tab is focused
