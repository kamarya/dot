#!/usr/bin/env bash
#
# Dotfiles sync/install helpers.
#
# Usage:
#   ./install.sh update_configs   # copy repo config files into $HOME
#   ./install.sh install_mark     # install vim-mark plugin (+ its dependency)
#   ./install.sh install_skills   # clone agent skill repos into ~/.agents/skills
#   ./install.sh install_git_completion  # fetch git's bash completion script for zsh's _git
#   ./install.sh install_vscode_theme    # install the Kamary VS Code color theme
#   ./install.sh install_sclaude         # install the sandboxed claude launcher
#   ./install.sh set_default_shell       # chsh to zsh (interactive, not part of 'all')
#   ./install.sh all              # all of the above except set_default_shell

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

# standalone executables installed into $HOME/.local/bin, each as
# repo-relative-path:symlink-name (the symlink drops the .sh suffix)
BIN_DIR="$HOME/.local/bin"
BIN_MAP=(
  "sclaude.sh:sclaude"
)

# candidate "extensions" dirs for VS Code and its forks; the theme is
# installed into whichever of these already exist on this machine
VSCODE_EXTENSION_DIRS=(
  "$HOME/.vscode/extensions"
  "$HOME/.vscode-server/extensions"
  "$HOME/.vscode-insiders/extensions"
  "$HOME/.vscode-oss/extensions"
  "$HOME/.cursor/extensions"
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

install_vscode_theme() {
  local src_dir="$REPO_DIR/vscode/kamary-theme"
  local ext_dir dest_dir found=0

  if [[ ! -d "$src_dir" ]]; then
    echo "skip: $src_dir not found in repo" >&2
    return
  fi

  for ext_dir in "${VSCODE_EXTENSION_DIRS[@]}"; do
    if [[ -d "$ext_dir" ]]; then
      found=1
      dest_dir="$ext_dir/kamary-theme"
      backup_if_present "$dest_dir"
      mkdir -p "$dest_dir"
      cp -a "$src_dir/." "$dest_dir/"
      echo "vscode theme installed: $dest_dir (select \"Kamary\" via Preferences: Color Theme)"
    fi
  done

  if [[ "$found" -eq 0 ]]; then
    dest_dir="$HOME/.vscode/extensions/kamary-theme"
    mkdir -p "$dest_dir"
    cp -a "$src_dir/." "$dest_dir/"
    echo "vscode theme installed: $dest_dir (select \"Kamary\" via Preferences: Color Theme)"
  fi
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

install_sclaude() {
  local entry src link_name src_path dest_path link_path

  mkdir -p "$BIN_DIR"

  for entry in "${BIN_MAP[@]}"; do
    src="${entry%%:*}"
    link_name="${entry##*:}"
    src_path="$REPO_DIR/$src"
    dest_path="$BIN_DIR/$(basename "$src")"
    link_path="$BIN_DIR/$link_name"

    if [[ ! -f "$src_path" ]]; then
      echo "skip: $src_path not found in repo" >&2
      continue
    fi

    if cmp -s "$src_path" "$dest_path" 2>/dev/null; then
      echo "up to date: $dest_path"
    else
      backup_if_present "$dest_path"
      cp "$src_path" "$dest_path"
      echo "installed: $dest_path"
    fi
    chmod +x "$dest_path"

    # relative target so the link keeps working if $HOME moves
    if [[ -L "$link_path" && "$(readlink "$link_path")" == "$(basename "$src")" ]]; then
      echo "up to date: $link_path -> $(basename "$src")"
    else
      backup_if_present "$link_path"
      ln -sfn "$(basename "$src")" "$link_path"
      echo "linked: $link_path -> $(basename "$src")"
    fi
  done

  if ! command -v bwrap >/dev/null 2>&1; then
    echo "warning: bwrap not found; sclaude needs it (apt install bubblewrap)" >&2
  fi
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "warning: $BIN_DIR is not on your PATH" >&2 ;;
  esac

  if [[ -d "$BACKUP_DIR" ]]; then
    echo "backups of replaced files saved under: $BACKUP_DIR"
  fi
}

set_default_shell() {
  local zsh_path
  zsh_path="$(command -v zsh || true)"

  if [[ -z "$zsh_path" ]]; then
    echo "zsh not found in PATH; install it first (e.g. apt install zsh)" >&2
    return 1
  fi

  if [[ "${SHELL:-}" == "$zsh_path" ]]; then
    echo "default shell is already $zsh_path"
    return
  fi

  if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
    echo "warning: $zsh_path is not listed in /etc/shells; chsh may refuse it" >&2
    echo "  (add it with: echo '$zsh_path' | sudo tee -a /etc/shells)" >&2
  fi

  echo "changing default shell to $zsh_path (chsh may prompt for your password)"
  chsh -s "$zsh_path"
  echo "default shell changed to $zsh_path; log out and back in for it to take effect"
}

main() {
  case "${1:-all}" in
    update_configs)         update_configs ;;
    install_mark)           install_vim_mark ;;
    install_skills)         install_skills ;;
    install_git_completion) install_git_completion ;;
    install_vscode_theme)   install_vscode_theme ;;
    install_sclaude)        install_sclaude ;;
    set_default_shell)      set_default_shell ;;
    all)
      update_configs
      install_vim_mark
      install_skills
      install_git_completion
      install_vscode_theme
      install_sclaude
      ;;
    *)
      echo "usage: $0 {update_configs|install_mark|install_skills|install_git_completion|install_vscode_theme|install_sclaude|set_default_shell|all}" >&2
      exit 1
      ;;
  esac
}

main "$@"
