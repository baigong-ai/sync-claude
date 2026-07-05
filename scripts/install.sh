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

# MCP servers:从 dotfiles 的 mcp-servers.json 导入到本机 user scope
# (env/headers 值是占位,导入后需手动填回真实凭证)
MCP_JSON="$SRC/mcp-servers.json"
if [ -f "$MCP_JSON" ]; then
  echo
  if command -v claude >/dev/null 2>&1; then
    echo "=== 导入 MCP servers(user scope)==="
    PYBIN="${CC_PYTHON:-$HOME/.venvs/cc-data/bin/python}"
    command -v "$PYBIN" >/dev/null 2>&1 || PYBIN=python3
    "$PYBIN" - "$MCP_JSON" << 'PY'
import json, subprocess, sys
mcp = json.load(open(sys.argv[1]))
added = skipped = failed = 0
for name, cfg in mcp.items():
    check = subprocess.run(["claude", "mcp", "get", name],
                           capture_output=True, text=True)
    if check.returncode == 0:
        print(f"  • 跳过(已存在): {name}")
        skipped += 1
        continue
    try:
        subprocess.run(["claude", "mcp", "add-json", name, json.dumps(cfg), "-s", "user"],
                       check=True, capture_output=True, text=True)
        envkeys = list((cfg.get("env") or {}).keys())
        hdrkeys = list((cfg.get("headers") or {}).keys())
        todo = ([f"env={envkeys}"] if envkeys else []) + ([f"headers={hdrkeys}"] if hdrkeys else [])
        hint = f"  ⚠ 待填: {', '.join(todo)}" if todo else ""
        print(f"  ✓ 新增: {name}{hint}")
        added += 1
    except subprocess.CalledProcessError as e:
        print(f"  ✗ 失败: {name} — {(e.stderr or '').strip() or e}")
        failed += 1
print(f"\n  汇总: 新增 {added}, 跳过 {skipped}, 失败 {failed}")
print("  提示:env/headers 是 ***REDACTED*** 占位,需手动填回真实凭证")
print("  可用 'claude mcp remove <name>' 删后重 add,或直接编辑 ~/.claude.json")
PY
  else
    echo "⚠ 发现 $MCP_JSON 但本机没有 claude 命令,跳过 MCP 导入(装好 claude 后重跑即可)"
  fi
fi

echo
echo "完成。提示:"
echo "  - 敏感字段(token)请放在 ~/.claude/settings.local.json 或 shell 环境变量,不要写进仓库的 settings.json"
echo "  - MCP env/headers 是占位,记得手填真实凭证"
echo "  - 验证: ls -la $CLAUDE_HOME"
