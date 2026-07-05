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
# 打包策略(覆盖 Claude Code 全部个人配置):
#   - CLAUDE.md / keybindings / commands / agents / output-styles / hooks:全量
#   - skills:只打"自定义"(目录下没有 LICENSE/LICENSE.txt 的);官方/插件 skill 跳过
#   - plugins:installed_plugins.json + known_marketplaces.json + 可读 inventory
#   - MCP servers:从 ~/.claude.json 提取 mcpServers,env 值全脱敏(保留 key 名)
#   - settings.json:token/key/secret 类字段 → ***REDACTED***
#   不打包:projects/、sessions/、history.jsonl、~/.claude.json 的其余字段
#  (对话历史/登录态/统计,既敏感又设备相关)

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

# 3) plugins:打包清单文件
if [ -d plugins ] && { [ -f plugins/installed_plugins.json ] || [ -f plugins/known_marketplaces.json ]; }; then
  mkdir -p "$TMP/.claude/plugins"
  [ -f plugins/installed_plugins.json ]  && cp plugins/installed_plugins.json  "$TMP/.claude/plugins/"
  [ -f plugins/known_marketplaces.json ] && cp plugins/known_marketplaces.json "$TMP/.claude/plugins/"
fi

# 4) settings.json 脱敏 + MCP 导出 + 生成 inventory(一次 python 调用搞定)
PYBIN="${CC_PYTHON:-$HOME/.venvs/cc-data/bin/python}"
command -v "$PYBIN" >/dev/null 2>&1 || PYBIN=python3
"$PYBIN" - "$CLAUDE_HOME" "$TMP/.claude" "$HOST" <<'PY'
import json, os, pathlib, re, sys
claude_home = pathlib.Path(sys.argv[1])
dst         = pathlib.Path(sys.argv[2])
host        = sys.argv[3]
user_home   = pathlib.Path(os.path.expanduser("~"))

def load(p):
    try:
        return json.loads(p.read_text())
    except Exception:
        return None

# --- 脱敏 settings.json ---
settings = load(claude_home / "settings.json")
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
else:
    SENS = re.compile(r'(?i)(token|key|secret|password|auth|credential)')

# --- MCP servers:从 ~/.claude.json 提取,env 值全脱敏(保留 key 名)---
claude_json = user_home / ".claude.json"
mcp_all = {}
if claude_json.exists():
    cjd = load(claude_json) or {}
    mcp_all = cjd.get("mcpServers") or {}

mcp_export = {}
for name, cfg in mcp_all.items():
    cfg2 = {k: v for k, v in (cfg or {}).items() if k not in ("env", "headers")}
    if (cfg or {}).get("env"):
        # MCP env 极大概率含凭证 → 值全脱敏,只保留 key 名(让用户知道要填哪些)
        cfg2["env"] = {k: "***REDACTED***" for k in cfg["env"]}
    if (cfg or {}).get("headers"):
        # http server 的 headers 常含 Authorization → 同样全脱敏值
        cfg2["headers"] = {k: "***REDACTED***" for k in cfg["headers"]}
    mcp_export[name] = cfg2
(dst / "mcp-servers.json").write_text(json.dumps(mcp_export, indent=2, ensure_ascii=False))

# --- 生成可读 inventory(插件 + MCP,便于多机对比)---
installed    = load(claude_home / "plugins" / "installed_plugins.json")
marketplaces = load(claude_home / "plugins" / "known_marketplaces.json")
ep = (settings or {}).get("enabledPlugins") or {}

L = [f"# Claude Code 配置清单 — {host}", "", "_由 pack-claude-config 生成_", ""]

L.append("## 已安装插件 (`installed_plugins.json`)")
if installed and installed.get("plugins"):
    for spec, instances in installed["plugins"].items():
        for inst in instances:
            ver = inst.get("version", "?"); scope = inst.get("scope", "?")
            ts = str(inst.get("installedAt", "?"))[:10]
            L.append(f"- `{spec}` v{ver} — scope={scope}, installed {ts}")
else:
    L.append("_(无)_")
L.append("")

L.append("## 启用的插件 (`settings.json` → `enabledPlugins`)")
for k, v in ep.items():
    L.append(f"- `{k}` = {v}")
if not ep:
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

L.append("## MCP servers (`~/.claude.json` → `mcpServers`)")
if mcp_all:
    for name, cfg in mcp_all.items():
        transport = (cfg or {}).get("type", "stdio")
        cmd = (cfg or {}).get("command") or (cfg or {}).get("url") or "?"
        envkeys = list(((cfg or {}).get("env") or {}).keys())
        hdrkeys = list(((cfg or {}).get("headers") or {}).keys())
        parts = []
        if envkeys: parts.append(f"env=[{', '.join(envkeys)}]")
        if hdrkeys: parts.append(f"headers=[{', '.join(hdrkeys)}]")
        extra = (", " + ", ".join(parts)) if parts else ""
        L.append(f"- `{name}` — {transport}, {cmd}{extra}")
else:
    L.append("_(无)_")
L.append("")

(dst / "plugins-inventory.md").write_text("\n".join(L))
n_inst = len((installed or {}).get("plugins", {}) or {})
print(f"  • 清单: {n_inst} 插件 / {len(ep)} 启用 / {len(marketplaces or {})} 市场 / {len(mcp_all)} MCP")
PY

# 5) 打包
tar -czf "$OUT" -C "$TMP" .claude
echo "✓ 导出完成: $OUT  ($(du -h "$OUT" | cut -f1))"
echo "  → 把这个文件传到整合用的那台机器上"
