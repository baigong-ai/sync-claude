#!/usr/bin/env bash
# pack-claude-config.sh
# 在源机器上跑,把 Claude Code 的"个人配置"导出成一个 tarball(自动脱敏)。
# 用途:整合多台机器时,把各台配置收集到一起做 diff / 合并。
#
# 用法:
#   bash pack-claude-config.sh [输出目录]    # 默认输出到 $HOME
#
# 环境变量:
#   CC_PYTHON   Python 解释器路径(用于 settings.json 脱敏),默认 ~/.venvs/cc-data/bin/python
#   CLAUDE_HOME Claude Code 配置目录,默认 ~/.claude

set -euo pipefail

OUT_DIR="${1:-$HOME}"
HOST="$(hostname -s)"
OUT="$OUT_DIR/claude-config-$HOST.tgz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.claude"

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
[ -d "$CLAUDE_HOME" ] || { echo "✗ 找不到 $CLAUDE_HOME"; exit 1; }

cd "$CLAUDE_HOME"

# 1) 个人配置文件 / 目录(有则打包)
for item in CLAUDE.md keybindings.json commands agents output-styles hooks; do
  [ -e "$item" ] && cp -R "$item" "$TMP/.claude/$item"
done

# skills:全量打包(体积可控;合并时人工区分"自定义" vs "插件自带")
[ -d skills ] && cp -R skills "$TMP/.claude/skills"

# 插件清单(让目标机器能装上同样的插件)
if [ -f plugins/installed_plugins.json ]; then
  mkdir -p "$TMP/.claude/plugins"
  cp plugins/installed_plugins.json "$TMP/.claude/plugins/"
fi

# 2) settings.json:脱敏后写入(token/key/secret 类字段替换为 ***REDACTED***)
if [ -f settings.json ]; then
  PYBIN="${CC_PYTHON:-$HOME/.venvs/cc-data/bin/python}"
  command -v "$PYBIN" >/dev/null 2>&1 || PYBIN=python3
  "$PYBIN" - "$CLAUDE_HOME/settings.json" "$TMP/.claude/settings.json" <<'PY'
import json, re, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    d = json.load(f)
SENS = re.compile(r'(?i)(token|key|secret|password|auth|credential)')
def redact(o):
    if isinstance(o, dict):
        return {k: ('***REDACTED***' if (SENS.search(k) and isinstance(v, (str, dict, list)) and v) else redact(v))
                for k, v in o.items()}
    if isinstance(o, list):
        return [redact(x) for x in o]
    return o
with open(dst, 'w') as f:
    json.dump(redact(d), f, indent=2, ensure_ascii=False)
PY
fi

# 3) 打包
tar -czf "$OUT" -C "$TMP" .claude
echo "✓ 导出完成: $OUT  ($(du -h "$OUT" | cut -f1))"
echo "  → 把这个文件传到整合用的那台机器上"
