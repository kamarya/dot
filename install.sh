#!/usr/bin/env bash
#
# Dotfiles sync/install helpers.
#
# Usage:
#   ./install.sh update_configs   # copy repo config files into $HOME
#   ./install.sh install_mark     # install vim-mark plugin (+ its dependency)
#   ./install.sh install_skills   # clone agent skill repos into ~/.agents/skills
#   ./install.sh install_git_completion  # fetch git's bash completion script for zsh's _git
#   ./install.sh all              # all of the above (default)

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
  "zshrc:.zshrc"
  "agents/AGENTS.md:.agents/AGENTS.md"
  "agents/CPPSTD.md:.agents/CPPSTD.md"
)

# destination-under-$HOME paths that are no longer used and should be
# removed (backed up first) so they don't shadow their replacement above,
# e.g. ~/.vimrc shadowing the fallback ~/.vim/vimrc that vim loads instead.
REMOVE_LIST=(
  ".vimrc"
)

# agent skill repos to clone (shallow, depth 1) into ~/.agents/skills
SKILLS_DIR="$HOME/.agents/skills"
SKILL_REPOS=(
  "https://github.com/danyuchn/asd-ste100-skill"
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

install_skills() {
  local repo_url repo_name dest_dir

  mkdir -p "$SKILLS_DIR"

  for repo_url in "${SKILL_REPOS[@]}"; do
    repo_name="$(basename "$repo_url" .git)"
    dest_dir="$SKILLS_DIR/$repo_name"

    if [[ -d "$dest_dir/.git" ]]; then
      git -C "$dest_dir" pull --ff-only
    else
      git clone --depth 1 "$repo_url" "$dest_dir"
    fi

    echo "skill installed: $dest_dir"
  done
}

install_git_completion() {
  local dest_dir="$HOME/.zsh"
  local dest_file="$dest_dir/git-completion.bash"
  local url="https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash"

  mkdir -p "$dest_dir"
  curl -fsSL "$url" -o "$dest_file"
  echo "git bash-completion script installed: $dest_file"
  echo "(used by zsh's _git via the 'script' zstyle in zshrc)"
}

main() {
  case "${1:-all}" in
    update_configs)         update_configs ;;
    install_mark)           install_vim_mark ;;
    install_skills)         install_skills ;;
    install_git_completion) install_git_completion ;;
    all)
      update_configs
      install_vim_mark
      install_skills
      install_git_completion
      ;;
    *)
      echo "usage: $0 {update_configs|install_mark|install_skills|install_git_completion|all}" >&2
      exit 1
      ;;
  esac
}

main "$@"
