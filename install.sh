#!/usr/bin/env bash
#
# Dotfiles sync/install helpers.
#
# Usage:
#   ./install.sh update_configs   # copy repo config files into $HOME
#   ./install.sh install_mark     # install vim-mark plugin (+ its dependency)
#   ./install.sh all              # both of the above (default)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

# repo-relative-path:destination-under-$HOME
CONFIG_MAP=(
  "vim/vimrc:.vim/vimrc"
  "vim/colors/kamary.vim:.vim/colors/kamary.vim"
  "nvim/init.vim:.config/nvim/init.vim"
  "nvim/colors/kamary.vim:.config/nvim/colors/kamary.vim"
  "tmux.conf:.tmux.conf"
  "gitconfig:.gitconfig"
)

# destination-under-$HOME paths that are no longer used and should be
# removed (backed up first) so they don't shadow their replacement above,
# e.g. ~/.vimrc shadowing the fallback ~/.vim/vimrc that vim loads instead.
REMOVE_LIST=(
  ".vimrc"
)

backup_if_present() {
  local dest="$1"
  local rel="${dest#"$HOME"/}"
  if [[ -e "$dest" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$dest" "$BACKUP_DIR/$rel"
  fi
}

update_configs() {
  local entry src dest src_path dest_path

  for entry in "${CONFIG_MAP[@]}"; do
    src="${entry%%:*}"
    dest="${entry##*:}"
    src_path="$REPO_DIR/$src"
    dest_path="$HOME/$dest"

    if [[ ! -f "$src_path" ]]; then
      echo "skip: $src_path not found in repo" >&2
      continue
    fi

    if cmp -s "$src_path" "$dest_path" 2>/dev/null; then
      echo "up to date: $dest_path"
      continue
    fi

    mkdir -p "$(dirname "$dest_path")"
    backup_if_present "$dest_path"
    cp "$src_path" "$dest_path"
    echo "updated: $dest_path"
  done

  remove_stale_configs

  if [[ -d "$BACKUP_DIR" ]]; then
    echo "backups of replaced files saved under: $BACKUP_DIR"
  fi
}

remove_stale_configs() {
  local rel dest_path

  for rel in "${REMOVE_LIST[@]}"; do
    dest_path="$HOME/$rel"
    if [[ -e "$dest_path" || -L "$dest_path" ]]; then
      backup_if_present "$dest_path"
      rm -f "$dest_path"
      echo "removed: $dest_path (see backup)"
    fi
  done
}

install_vim_mark() {
  local pack_dir="$HOME/.vim/pack/plugins/start"
  local ingo_dir="$pack_dir/vim-ingo-library"
  local mark_dir="$pack_dir/vim-mark"

  mkdir -p "$pack_dir"

  if [[ -d "$ingo_dir/.git" ]]; then
    git -C "$ingo_dir" pull --ff-only
  else
    git clone https://github.com/inkarkat/vim-ingo-library "$ingo_dir"
  fi

  if [[ -d "$mark_dir/.git" ]]; then
    git -C "$mark_dir" pull --ff-only
  else
    git clone https://github.com/inkarkat/vim-mark "$mark_dir"
  fi

  vim -u NONE -c "helptags $ingo_dir/doc" -c q 2>/dev/null || true
  vim -u NONE -c "helptags $mark_dir/doc" -c q 2>/dev/null || true

  echo "vim-mark installed into $mark_dir"
  echo "restart vim, then use <Leader>m to mark a word, <Leader>n / <Leader>N to jump between marks"
}

main() {
  case "${1:-all}" in
    update_configs) update_configs ;;
    install_mark)   install_vim_mark ;;
    all)            update_configs; install_vim_mark ;;
    *)
      echo "usage: $0 {update_configs|install_mark|all}" >&2
      exit 1
      ;;
  esac
}

main "$@"
