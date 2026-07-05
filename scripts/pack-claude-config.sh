#!/usr/bin/env bash
# pack-claude-config.sh
# 在源机器上跑,把 Claude Code 的"个人配置"导出成一个 tarball(自动脱敏)。
# 用途:整合多台机器时,把各台配置收集到一起做 diff / 合并。
#
# 用法:
#   bash pack-claude-config.sh [输出目录]    # 默认输出到 $HOME
#
# 环境变量:
#   CC_PYTHON   Python 解释器路径,默认 ~/.venvs/cc-data/bin/python,回退 python3
#   CLAUDE_HOME Claude Code 配置目录,默认 ~/.claude
#
# 打包策略:
#   - CLAUDE.md / keybindings / commands / agents / output-styles / hooks:全量
#   - skills:只打"自定义"(启发式 = 目录下没有 LICENSE/LICENSE.txt 的);
#             官方/插件 skill 都带 LICENSE,新机装 Claude Code 自带,不打
#   - plugins:打包 installed_plugins.json + known_marketplaces.json,并生成
#             可读的 plugins-inventory.md,便于多机对比"哪台装了啥"
#   - settings.json:脱敏(token/key/secret 类字段 → ***REDACTED***)

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

# 2) skills:只打"自定义"(无 LICENSE 的);官方/插件 skill 跳过
if [ -d skills ]; then
  mkdir -p "$TMP/.claude/skills"
  for s in skills/*/; do
    [ -d "$s" ] || continue
    name=$(basename "$s")
    if [ -f "$s/LICENSE.txt" ] || [ -f "$s/LICENSE" ]; then
      echo "  • 跳过 skill(官方/插件,带 LICENSE): $name"
    else
      cp -R "$s" "$TMP/.claude/skills/$name"
      echo "  • 打包 skill(自定义): $name"
    fi
  done
fi

# 3) plugins:打包清单文件(known_marketplaces 让目标机能找到同样的市场)
if [ -d plugins ] && { [ -f plugins/installed_plugins.json ] || [ -f plugins/known_marketplaces.json ]; }; then
  mkdir -p "$TMP/.claude/plugins"
  [ -f plugins/installed_plugins.json ]  && cp plugins/installed_plugins.json  "$TMP/.claude/plugins/"
  [ -f plugins/known_marketplaces.json ] && cp plugins/known_marketplaces.json "$TMP/.claude/plugins/"
fi

# 4) settings.json 脱敏 + 生成 plugins-inventory.md(一次 python 调用搞定)
PYBIN="${CC_PYTHON:-$HOME/.venvs/cc-data/bin/python}"
command -v "$PYBIN" >/dev/null 2>&1 || PYBIN=python3
"$PYBIN" - "$CLAUDE_HOME" "$TMP/.claude" "$HOST" <<'PY'
import json, pathlib, re, sys
home = pathlib.Path(sys.argv[1])
dst  = pathlib.Path(sys.argv[2])
host = sys.argv[3]

def load(p):
    try:
        return json.loads(p.read_text())
    except Exception:
        return None

# --- 脱敏 settings.json ---
settings = load(home / "settings.json")
if settings is not None:
    SENS = re.compile(r'(?i)(token|key|secret|password|auth|credential)')
    def redact(o):
        if isinstance(o, dict):
            return {k: ('***REDACTED***' if (SENS.search(k) and isinstance(v, (str, dict, list)) and v) else redact(v))
                    for k, v in o.items()}
        if isinstance(o, list):
            return [redact(x) for x in o]
        return o
    (dst / "settings.json").write_text(json.dumps(redact(settings), indent=2, ensure_ascii=False))

# --- 生成 plugins-inventory.md(人类可读,便于多机对比)---
installed    = load(home / "plugins" / "installed_plugins.json")
marketplaces = load(home / "plugins" / "known_marketplaces.json")
ep = (settings or {}).get("enabledPlugins") or {}

L = [f"# Plugins Inventory — {host}", "", "_由 pack-claude-config 生成_", ""]

L.append("## 已安装插件 (`installed_plugins.json`)")
if installed and installed.get("plugins"):
    for spec, instances in installed["plugins"].items():
        for inst in instances:
            ver = inst.get("version", "?")
            scope = inst.get("scope", "?")
            ts = str(inst.get("installedAt", "?"))[:10]
            L.append(f"- `{spec}` v{ver} — scope={scope}, installed {ts}")
else:
    L.append("_(无)_")
L.append("")

L.append("## 启用的插件 (`settings.json` → `enabledPlugins`)")
if ep:
    for k, v in ep.items():
        L.append(f"- `{k}` = {v}")
else:
    L.append("_(无)_")
L.append("")

L.append("## 已知插件市场 (`known_marketplaces.json`)")
if marketplaces:
    for name, info in marketplaces.items():
        src = info.get("source", {}) or {}
        kind = src.get("source", "?")
        loc = src.get("repo") or src.get("path") or "?"
        L.append(f"- `{name}` — {kind}: {loc}")
else:
    L.append("_(无)_")
L.append("")

(dst / "plugins-inventory.md").write_text("\n".join(L))
n_inst = len((installed or {}).get("plugins", {}) or {})
print(f"  • 生成插件清单: {n_inst} 已装 / {len(ep)} 启用 / {len(marketplaces or {})} 市场")
PY

# 5) 打包
tar -czf "$OUT" -C "$TMP" .claude
echo "✓ 导出完成: $OUT  ($(du -h "$OUT" | cut -f1))"
echo "  → 把这个文件传到整合用的那台机器上"
