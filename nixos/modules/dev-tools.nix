{ config, lib, pkgs, ... }:
{
  # Phase 2: port bootstrap/roles/40-dev-tools.sh and 60-langs.sh
  # Covers: bootstrap.DEV_TOOLS.1, bootstrap.LANGS.1-8
  # environment.systemPackages: git, tmux, zsh, ripgrep, fzf, btop, neovim, zoxide, eza, mosh, yadm, pipx
  # language runtimes: fnm/node, uv, bun, rust, go
}
