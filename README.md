# Herdr.app

A macOS app for supervising parallel agents with [herdr](https://herdr.dev) 🪚

A single window running a herdr client on a [Ghostty](https://github.com/ghostty-org/ghostty)
surface, plus the scripts and config that shape my workflow:

1. No mouse usage, only an opinionated set of minimal keybindings and commands
1. Each space is a single stream of work, split into a terminal and an agent pane
1. Git repositories open as a fresh worktree per space
1. Spaces show their Linear ticket and GitHub PR in the sidebar

## Usage

```bash
make install-herdr   # build and install to ~/Applications/Herdr.app
make reload-herdr    # apply config/herdr.toml and relaunch with the latest build
```

`make install-herdr` symlinks `~/.config/herdr/config.toml` to `config/herdr.toml`, backing up any
existing file as `config.toml.bak`. Clone to `~/projects/github.com/revett/koba`, as the config
runs its scripts from there.

## License

Released under the [GPL v3](https://opensource.org/license/gpl-3-0) license.
