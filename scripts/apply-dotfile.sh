#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: apply-dotfile.sh [options]

Overlay this dotfile repository onto an existing end-4/dots-hyprland install.

Options:
  --target PATH   Config directory to update. Default: $XDG_CONFIG_HOME or ~/.config
  --pull          Run git pull --ff-only in this dotfile repo before applying
  --dry-run       Print what would change without writing files
  --no-backup     Do not backup replaced files
  -h, --help      Show this help

Examples:
  scripts/apply-dotfile.sh --dry-run
  scripts/apply-dotfile.sh --target "$HOME/.config"
  scripts/apply-dotfile.sh --pull --target "$HOME/.config"
USAGE
}

target_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
dry_run=0
backup=1
pull=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --target)
            if [ "$#" -lt 2 ]; then
                printf 'Missing value for --target\n' >&2
                exit 2
            fi
            target_dir="$2"
            shift 2
            ;;
        --pull)
            pull=1
            shift
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        --no-backup)
            backup=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/.." && pwd -P)"

if ! git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'This script must be run from a git clone of the dotfile repository.\n' >&2
    exit 1
fi

repo_root="$(git -C "$repo_root" rev-parse --show-toplevel)"
if [ "$dry_run" -eq 1 ]; then
    if [ -d "$target_dir" ]; then
        target_dir="$(cd "$target_dir" && pwd -P)"
    else
        target_parent="$(dirname "$target_dir")"
        target_name="$(basename "$target_dir")"
        target_dir="$(cd "$target_parent" && pwd -P)/$target_name"
    fi
else
    target_dir="$(mkdir -p "$target_dir" && cd "$target_dir" && pwd -P)"
fi

if [ "$pull" -eq 1 ]; then
    git -C "$repo_root" pull --ff-only
fi

backup_root="$target_dir/.dotfile-backups/$(date +%Y%m%d-%H%M%S)"
changed=0

printf 'Source: %s\n' "$repo_root"
printf 'Target: %s\n' "$target_dir"
if [ "$dry_run" -eq 1 ]; then
    printf 'Mode: dry run\n'
elif [ "$backup" -eq 1 ]; then
    printf 'Backup: %s\n' "$backup_root"
else
    printf 'Backup: disabled\n'
fi

while IFS= read -r -d '' rel_path; do
    src_path="$repo_root/$rel_path"
    dest_path="$target_dir/$rel_path"

    if [ -d "$dest_path" ] && [ ! -L "$dest_path" ]; then
        printf 'Refusing to replace directory with file: %s\n' "$dest_path" >&2
        exit 1
    fi

    # Compare files: resolve home path for user compatibility
    cmp_status=1
    if [ -e "$dest_path" ]; then
        if [[ "$rel_path" == "illogical-impulse/config.json" || "$rel_path" == "hypr/hyprlock/colors.conf" ]]; then
            if cmp -s <(sed "s|/home/c0ffeeoverdose|$HOME|g" "$src_path") "$dest_path"; then
                cmp_status=0
            fi
        else
            if cmp -s "$src_path" "$dest_path"; then
                cmp_status=0
            fi
        fi
    fi

    if [ "$cmp_status" -eq 0 ]; then
        continue
    fi

    changed=1
    if [ "$dry_run" -eq 1 ]; then
        if [ -e "$dest_path" ]; then
            printf 'Would update %s\n' "$rel_path"
        else
            printf 'Would create %s\n' "$rel_path"
        fi
        continue
    fi

    if [ "$backup" -eq 1 ] && [ -e "$dest_path" ]; then
        mkdir -p "$backup_root/$(dirname "$rel_path")"
        cp -a "$dest_path" "$backup_root/$rel_path"
    fi

    mkdir -p "$(dirname "$dest_path")"
    if [[ "$rel_path" == "illogical-impulse/config.json" || "$rel_path" == "hypr/hyprlock/colors.conf" ]]; then
        sed "s|/home/c0ffeeoverdose|$HOME|g" "$src_path" > "$dest_path"
    else
        cp -a "$src_path" "$dest_path"
    fi
    printf 'Applied %s\n' "$rel_path"
done < <(git -C "$repo_root" ls-files -z)

if [ "$changed" -eq 0 ]; then
    printf 'Already up to date.\n'
elif [ "$dry_run" -eq 0 ] && [ "$backup" -eq 1 ]; then
    printf 'Previous files were backed up under %s when replacements were needed.\n' "$backup_root"
fi

printf 'Done. Restart Hyprland/Quickshell if the changed files affect the running session.\n'
