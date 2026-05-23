# c0ffeeOverdose's dotfiles

Personal Linux desktop dotfiles.

This setup is based on [`end-4/dots-hyprland`](https://github.com/end-4/dots-hyprland). Install the upstream dots first, then apply this repository as an overlay for my version.

This repository tracks only the config files I want to version and share. It is not a full home-directory backup and should not be applied blindly without reviewing the changes.

## Contents

- `quickshell/` - desktop shell, sidebar, widgets, services, scripts, and AI chat integration.
- `illogical-impulse/` - shared shell configuration used by the Quickshell setup.
- `hypr/` - Hyprland configuration and related scripts.
- `fish/` - Fish shell configuration.
- `kitty/` and `foot/` - terminal configuration.
- `wlogout/` - logout menu configuration.
- `scripts/` - helper scripts for applying this overlay.
- `starship.toml` - shell prompt configuration.

## Main Changes From Upstream

- Added an official Antigravity CLI backend for the Quickshell AI sidebar.
- Added AGY models using the model labels accepted by Antigravity settings.
- Added stateful sidebar AGY sessions with `agy --conversation` instead of resending the full transcript each turn.
- Isolated sidebar AGY history under Quickshell state so it does not pollute normal Antigravity TUI history.
- Added Chat and Agent sidebar modes with `/mode`, `/chat`, and `/agent`.
- Added an editable AGY sidebar contract at `quickshell/ii/services/ai/prompts/agy-sidebar-contract.md`.
- Added local Antigravity skill sync into the isolated sidebar AGY home without copying AGY history.
- Added grammar-coach behavior to the sidebar prompt.
- Removed the sidebar tool indicator and kept the mode indicator.
- Added QML undefined-safety fixes in AI message rendering.
- Changed touch gesture config to set `disable_inhibit = true` for configured gestures.
- Changed the default on-screen keyboard layout to English.
- Simplified the sidebar AI system prompt and cleared the default excluded search sites.

## Extra Dependencies

Install the dependencies required by `end-4/dots-hyprland` first. This overlay also expects or benefits from the following tools, depending on which features you use:

- Required for the overlay script: `bash`, `git`, and standard GNU/coreutils tools such as `cp`, `cmp`, `mkdir`, and `date`.
- Quickshell desktop: `quickshell`, `hyprland`, `hyprctl`, Material Symbols or compatible icon fonts, and the upstream end-4 dependencies.
- Shell and terminal setup: `fish`, `starship`, `kitty`, and/or `foot`.
- Sidebar AI helpers: `jq`, `ripgrep`, `secret-tool` from `libsecret`, and `file`.
- Optional AGY backend: official Antigravity CLI installed as `~/.local/bin/agy` or available in `PATH`.
- Optional local AI features: `ollama`.
- Optional screenshot/search/clipboard scripts: `curl`, `grim`, `slurp`, `wl-clipboard`, and `cliphist`.

## Apply After Installing Upstream

1. Install [`end-4/dots-hyprland`](https://github.com/end-4/dots-hyprland) normally.
2. Clone this repo somewhere outside `~/.config`:

```bash
git clone https://github.com/c0ffeeOverdose/dotfiles.git
cd dotfiles
```

3. Preview the overlay:

```bash
./scripts/apply-dotfile.sh --dry-run --target "$HOME/.config"
```

4. Apply it:

```bash
./scripts/apply-dotfile.sh --target "$HOME/.config"
```

The script copies only files tracked by this repository. Existing target files that would be replaced are backed up under `~/.config/.dotfile-backups/<timestamp>/`.

## Update To My Latest Version

From wherever you cloned the repo, update and apply the overlay with:

```bash
cd /path/to/dotfiles
./scripts/apply-dotfile.sh --pull --target "$HOME/.config"
```

Use `--dry-run` first if you want to preview changes.

## Quickshell AI Notes

The Quickshell sidebar can use multiple AI backends, including the official Antigravity CLI through `agy`.

The Antigravity integration is designed to:

- Use the official `agy` binary instead of third-party proxy layers.
- Keep a stateful sidebar conversation with `agy --conversation`.
- Keep sidebar AGY history isolated from the normal Antigravity TUI history.
- Store the sidebar AGY prompt contract in `quickshell/ii/services/ai/prompts/agy-sidebar-contract.md`.
- Support Chat and Agent modes from the sidebar UI.
- Sync local Antigravity skills into the isolated sidebar AGY home without copying conversation history.

Chat mode is an instruction-level guard for AGY, not a hard sandbox. The Antigravity CLI does not expose a true no-tools mode, and `--sandbox` was not sufficient as a hard write boundary in local testing.
