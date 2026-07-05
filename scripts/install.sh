#!/usr/bin/env bash
# install.sh
# 把 dotfiles 仓库里的 Claude Code 配置,以符号链接方式挂到 ~/.claude/。
# 适合 macOS / Linux。Windows 用 install.ps1。
#
# 用法:
#   bash install.sh [dotfiles 仓库路径]    # 默认 ~/dotfiles
#
# 行为:
#   - 仓库里有的条目 → 在 ~/.claude/ 下建符号链接指向它
#   - 已存在且不是符号链接的同名文件 → 先备份为 *.bak.<时间戳> 再覆盖
#   - 已经是符号链接 → 直接 ln -snf 刷新指向

set -euo pipefail

DOTFILES="${1:-$HOME/dotfiles}"
SRC="$DOTFILES/claude"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"

if [ ! -d "$SRC" ]; then
  echo "✗ 找不到 $SRC"
  echo "  请先把 dotfiles 仓库 clone 好,或传入路径作为参数: bash install.sh /path/to/dotfiles"
  exit 1
fi

mkdir -p "$CLAUDE_HOME"

items=(CLAUDE.md settings.json keybindings.json commands agents skills output-styles hooks)

for item in "${items[@]}"; do
  target="$SRC/$item"
  link="$CLAUDE_HOME/$item"
  [ -e "$target" ] || continue

  # 备份已存在的、且不是符号链接的文件(防覆盖)
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    backup="$link.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$link" "$backup"
    echo "  已备份原有 $item → $backup"
  fi

  ln -snf "$target" "$link"
  echo "✓ $item → $target"
done

echo
echo "完成。提示:"
echo "  - 敏感字段(token)请放在 ~/.claude/settings.local.json 或 shell 环境变量,不要写进仓库的 settings.json"
echo "  - 验证: ls -la $CLAUDE_HOME"
