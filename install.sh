#!/usr/bin/env bash
set -Eeuo pipefail

# -------- helpers --------
log()  { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"\n; }
die()  { printf "\033[1;31m[err]\033[0m %s\n" "$*"\n; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

is_arch() { [[ -f /etc/arch-release ]]; }

# -------- config --------
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${HOME}"
BACKUP_DIR="${HOME}/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

PACKAGES=(
  hypr
  waybar
  # add/remove as needed
)

PACMAN_PKGS=(
  wget
  keyd
  libappindicator-gtk3
)

AUR_PKGS=(
  stow
  slack-desktop
  telegram-desktop
  joplin-bin
  notion-app-electron
)

# -------- actions --------
backup_conflicts() {
  log "Backing up conflicting dotfiles (if any) to: $BACKUP_DIR"
  mkdir -p "$BACKUP_DIR"

  for pkg in "${PACKAGES[@]}"; do
    [[ -d "$pkg" ]] || { warn "Skipping missing package dir: $pkg"; continue; }

    # Dry-run to detect conflicts
    local out
    if ! out="$(stow -n -v -d "$REPO_ROOT" -t "$TARGET" "$pkg" 2>&1)"; then
      # Try to parse conflicts from stow output; if we can't, still keep the log.
      printf "%s\n" "$out" >"$BACKUP_DIR/stow-${pkg}.log"

      # Very conservative approach: just save the log and let user resolve.
      warn "Conflicts detected for '$pkg'. See: $BACKUP_DIR/stow-${pkg}.log"
      warn "Tip: move conflicting files out of the way, or adopt them into your stow package."
    fi
  done

  local out
  need sudo
  if ! out="sudo stow -d "$REPO_ROOT" -t /etc etc"; then
    printf "%s\n" "$out" >"$BACKUP_DIR/stow-etc.log"

    warn "Conflicts detected for 'etc'. See: $BACKUP_DIR/stow-etc.log"
    warn "Tip: move conflicting files out of the way, or adopt them into your stow package."
  fi
}

install_pacman() {
  is_arch || { warn "Not Arch Linux; skipping pacman install"; return 0; }
  need sudo
  log "Installing pacman packages (if missing)"
  sudo pacman -Syu --needed --noconfirm "${PACMAN_PKGS[@]}"
}

install_aur() {
  is_arch || { warn "Not Arch Linux; skipping aur install"; return 0; }
  if ((${#AUR_PKGS[@]} == 0)); then
    log "No AUR packages configured; skipping"
    return 0
  fi

  if command -v yay >/dev/null 2>&1; then
    log "Installing AUR packages with yay"
    yay -S --needed --noconfirm "${AUR_PKGS[@]}"
  else
    warn "yay not found; skipping AUR packages. Install yay or add your helper here."
  fi
}

stow_dotfiles() {
  need stow
  log "Stowing packages into: $TARGET"
  for pkg in "${PACKAGES[@]}"; do
    [[ -d "$pkg" ]] || { warn "Skipping missing package dir: $pkg"; continue; }
    stow -v -d "$REPO_ROOT" -t "$TARGET" "$pkg"
  done

  need sudo
  log "Stowing etc configs"
  sudo stow -d "$REPO_ROOT" -t /etc etc
}

enable_services() {
  is_arch || return 0
  need sudo

  # keyd for swapping Alt/Super (optional)
  if command -v keyd >/dev/null 2>&1; then
    log "Enabling keyd"
    sudo systemctl enable --now keyd || warn "Failed to enable keyd"
  fi

  log "Restarting Hyprland"
  hyprctl reload
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --all           Install packages + stow + services
  --packages      Install pacman/AUR packages
  --stow          Stow configured packages
  --services      Enable services (e.g., keyd)
  --backup        Detect possible stow conflicts and save logs
  -h, --help      Show this help

Notes:
- Edit PACKAGES / PACMAN_PKGS / AUR_PKGS near the top.
- Put stow packages in: <package-name>/...
EOF
}

main() {
  local do_all=0 do_packages=0 do_stow=0 do_services=0 do_backup=0

  while (($#)); do
    case "$1" in
      --all) do_all=1 ;;
      --packages) do_packages=1 ;;
      --stow) do_stow=1 ;;
      --services) do_services=1 ;;
      --backup) do_backup=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done

  ((do_all)) && do_packages=1 do_stow=1 do_services=1

  ((do_backup))   && backup_conflicts
  ((do_packages)) && install_pacman && install_aur
  ((do_stow))     && stow_dotfiles
  ((do_services)) && enable_services

  log "Done."
}

main "$@"

