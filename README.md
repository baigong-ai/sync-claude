# sync-claude

> Claude Code 跨设备配置同步方案 —— 在 MacBook、Mac mini、Windows 之间同步你的配置和使用习惯。**只同步个人沉淀,不同步敏感数据和安装产物。**

## 为什么需要这个

Claude Code 的所有配置都存在本地 `~/.claude/`,**没有内置的跨设备同步功能**。如果你在多台机器上用 Claude Code,会很快遇到两个问题:

1. **重复配置** —— 每台机器都要重新写一遍 `CLAUDE.md`、自定义命令、`settings.json`。
2. **逐渐分叉** —— 用一段时间后,各台机器上的配置长得不一样了,你记不清哪份才是"对的"。

直接同步整个 `~/.claude/` 目录**不可行**:里面混着登录 token、几 GB 的对话历史、各种缓存和会话状态。一旦上传就等于泄露凭证 + 传输海量无用数据。

`sync-claude` 解决的是:把真正属于你的**"个人配置"**从这些噪声里抽出来,做成一个由 git 管理的**单一基线**,让所有机器共享同一份。

> 🆕 **不想敲命令行?** 直接双击仓库根目录的 [`sync-claude.html`](sync-claude.html) —— 一个图形化配置合并向导(单文件、零 Web Server、离线可用):勾选本机要同步的数据 → 导入另一台机器的备份 → 图形化比对差异 → 一键生成脱敏基线 zip + `install.sh`。下方命令行方式(`pack-claude-config.sh` + 手动 diff)依然保留,适合无 GUI / SSH / CI 场景。

## 核心原则

1. **只同步个人沉淀,不同步安装产物。** `skills/`、`plugins/` 这些重装就有,不进仓库;只有你亲手写的配置才进。
2. **敏感字段永不入库。** `ANTHROPIC_AUTH_TOKEN`、API key 这类东西只留在各机器本地。
3. **个人沉淀取并集,冲突择优。** 整合多台机器时,把每台独有的部分并进来;同名内容冲突时挑更好的那份。
4. **dotfiles + git + 符号链接。** 仓库存"真身",`~/.claude/` 下挂符号链接指向仓库。改配置 = 改仓库文件,`git push` 即同步。

## 哪些该同步、哪些不能碰

`~/.claude/` 是个杂物间。下表告诉你什么该带走、什么必须留下:

| 路径 | 类别 | 是否同步 | 说明 |
|---|---|---|---|
| `CLAUDE.md` | 个人指令 | ✅ 同步 | 全局工作约定,纯文本 |
| `settings.json` | 用户设置 | ⚠️ 先脱敏 | **去掉 token 后**再入库 |
| `keybindings.json` | 快捷键 | ✅ 同步 | 有就同步 |
| `commands/` | 自定义命令 | ✅ 同步 | `.md` 文件 |
| `agents/` | 自定义 subagent | ✅ 同步 | 可选 |
| `output-styles/` | 输出风格 | ✅ 同步 | 可选 |
| `skills/` | 自定义 skill | ⚠️ 仅自定义 | pack 自动只打**无 LICENSE** 的自定义 skill;官方内置(带 LICENSE)和插件 skill 都不打 |
| `hooks/` | hook 脚本 | ⚠️ 谨慎 | shell/python 脚本要跨平台适配 |
| `plugins/installed_plugins.json` `known_marketplaces.json` | 插件清单 | ✅ 同步 | pack 生成 `plugins-inventory.md`(插件 + MCP 概况) |
| `~/.claude.json` → `mcpServers` | MCP servers | ✅ 同步 | pack 提取 `mcpServers` → `mcp-servers.json`,`env`/`headers` 值全脱敏;install 时 `claude mcp add-json -s user` 导入 |
| `projects/` | 对话历史 | ❌ 不同步 | 又大又含敏感内容 |
| `history.jsonl` | 命令历史 | ❌ 不同步 | |
| `sessions/` `session-env/` | 会话 | ❌ 不同步 | 设备相关 |
| `shell-snapshots/` | shell 快照 | ❌ 不同步 | |
| `backups/` | 备份 | ❌ 不同步 | 含 `.claude.json` 历史,可能含密钥 |
| `config.json` `*-cache.json` | 凭证 / 缓存 | ❌ 不同步 | |
| `usage-data/` `tasks/` `transcripts/` | 统计 / 任务 | ❌ 不同步 | |
| `~/.claude.json`(在 `~` 下) | 登录态 + 统计 | ❌ 不同步 | 含敏感信息 |

> 一句话:**个人沉淀取并集,敏感字段不入库,安装产物靠重装。**

## 项目内容

```
sync-claude/
├── README.md                  # 你正在看的这份
├── LICENSE                    # MIT
├── sync-claude.html                  # 🆕 图形化配置合并向导(双击即用,零 Web Server)
├── scripts/
│   ├── pack-claude-config.sh  # 导出本机配置(脱敏),macOS / Linux
│   ├── pack-claude-config.ps1 # 导出本机配置(脱敏),Windows
│   ├── install.sh             # macOS / Linux:把 dotfiles 挂到 ~/.claude/
│   └── install.ps1            # Windows 版
└── examples/
    ├── settings.example.json  # 脱敏后的 settings 模板
    ├── dotfiles-layout.md     # 推荐的 dotfiles 仓库布局
    └── dotfiles.gitignore     # dotfiles 仓库用的 .gitignore 模板
```

## 实施路线(分阶段推进)

如果你在多个平台上用 Claude Code,建议按平台**分阶段**接入,每阶段跑通再进下一阶段,避免一次铺太大难排查问题:

- **阶段一:macOS(当前进行中)** —— 先把 MacBook、Mac mini 两台 Mac 的配置整合成一个基线,跑通"导出 → 合并 → dotfiles → 符号链接 → 双机同步"全流程。
- **阶段二:加入 Linux** —— 在阶段一基线上接入 Linux;重点处理平台差异(Python 解释器路径、包管理器),把硬编码抽象成环境变量。
- **阶段三:加入 Windows** —— 最后接入 Windows;处理符号链接(需开发者模式)、PowerShell 脚本适配、路径分隔符等。

> 各阶段的具体步骤见下方[「使用流程」](#使用流程);推进进度由 git 提交历史跟踪。

## 使用流程

### 第一步:把现有机器的配置整合成一个基线

如果你已经有两台机器各自用了很久(配置不一样),先做**一次性整合**:

1. **在每台机器上导出配置**(自动脱敏):

   ```bash
   # macOS / Linux
   bash scripts/pack-claude-config.sh
   # → 生成 ~/claude-config-<hostname>.tgz
   ```

   ```powershell
   # Windows(PowerShell)
   powershell -ExecutionPolicy Bypass -File scripts\pack-claude-config.ps1
   # → 生成 claude-config-<电脑名>.zip
   ```

2. **把所有 tarball 汇到一台机器上**,解包、人工 diff:
   - `CLAUDE.md`:逐段比对,取并集,重复段落择优
   - `commands/`、`skills/`:文件并集,同名则比对内容取新
   - `settings.json`:模型映射等取一致值,token **不合并、不入库**

3. **把合并结果整理成 dotfiles 仓库**布局(见 [`examples/dotfiles-layout.md`](examples/dotfiles-layout.md))。

### 第二步:把基线挂到每台机器上

1. 在 GitHub 建一个 **private** 仓库,把整理好的 dotfiles push 上去。

   > ⚠️ 配置里有你的个人指令和工作习惯,**建议 private**。

2. 在每台机器上:

   ```bash
   git clone git@github.com:<你>/dotfiles.git ~/dotfiles
   bash ~/dotfiles/install.sh        # macOS / Linux
   # Windows:
   # powershell -ExecutionPolicy Bypass -File install.ps1
   ```

   脚本会:把仓库里的配置**以符号链接**挂到 `~/.claude/`;若已有同名本地文件,先备份为 `*.bak.<时间戳>`。

### 第三步:日常同步

- 改了配置 → 在 `~/dotfiles/` 里 `git commit && git push`
- 另一台机器 → `cd ~/dotfiles && git pull`
- 因为是符号链接,pull 完立即生效

## 敏感信息(token)怎么放

**不要**把 token 写进要入库的 `settings.json`。两种替代:

**方式 A(推荐,跨平台):写进 shell 环境变量**

```bash
# macOS:~/.zshrc
export ANTHROPIC_AUTH_TOKEN="你的token"
```

```powershell
# Windows:PowerShell $PROFILE
$env:ANTHROPIC_AUTH_TOKEN = "你的token"
```

**方式 B:放进 `~/.claude/settings.local.json`(已被 .gitignore 排除)**

```json
{ "env": { "ANTHROPIC_AUTH_TOKEN": "你的token" } }
```

## 平台差异

`CLAUDE.md` 和 `settings.json` 都**不支持 `darwin`/`win32` 条件分支**。如果你的配置里有平台相关的路径(比如 Python 解释器),把它**抽象成环境变量**,在各机器的 shell 里分别赋值:

```markdown
# CLAUDE.md 里这样写
- **Python 解释器**:使用 `$CC_PYTHON`
```

```bash
# macOS ~/.zshrc
export CC_PYTHON="$HOME/.venvs/cc-data/bin/python"
```

```powershell
# Windows $PROFILE
$env:CC_PYTHON = "$HOME\.venvs\cc-data\Scripts\python.exe"
```

`hooks` 同理:bash 脚本在 Windows 上需要 Git Bash,或改写为 `.ps1` / `.cmd`。

## 常见问题

**Q:为什么不直接用 iCloud / OneDrive 同步 `~/.claude/`?**
A:云盘会无差别同步,容易把 `projects/`(对话历史)、session、缓存都同步上去,既慢又有泄露风险;也无法版本控制和解决冲突。dotfiles + git 只同步你指定的内容,精确可控。

**Q:skills 文件夹里有些是官方/插件装的,要不要同步?**
A:不用,pack 脚本会自动只打**自定义** skill(启发式:目录下没有 `LICENSE` 的视为自定义)。官方内置 skill(`pdf`/`pptx`/`xlsx`/`canvas-design`…,都带 LICENSE)装 Claude Code 就有,不打;插件提供的 skill 跟着 `plugins/installed_plugins.json` 走。所以 tarball 里只会出现你手写的 skill(比如 `mmx-cli`)。

**Q:怎么在新机器上把插件装齐?我搞不清每台装了啥。**
A:每台机器 pack 出来的 `plugins-inventory.md` 列了「已装 / 启用 / 已知市场」。把各台的 inventory 一摆,差异一目了然。在新机器上:
1. 添加市场:`/plugin marketplace add anthropics/claude-plugins-official`(以及你用的其它市场)
2. 逐个安装:`/plugin install <plugin>@<marketplace>`

合并配置时,我会帮你对比各台 inventory,生成每台机器该跑的具体安装命令。

**Q:MCP server 怎么同步?env 和 Authorization 头里的 API key 怎么办?**
A:pack 会从 `~/.claude.json` 提取 `mcpServers`,生成 `mcp-servers.json`。其中 `env` 和 `headers` 的**值全部脱敏**为 `***REDACTED***`(只保留 key 名,让你知道要填哪些)。install 时自动用 `claude mcp add-json <name> <cfg> -s user` 导入结构(已存在的跳过,不覆盖),然后你把真实 API key 手动填回 —— 和 `settings.json` 的 token 同理:**结构同步,凭证各机本地填**。

**Q:Windows 符号链接创建失败?**
A:Windows 创建符号链接需要「开发者模式」(设置 → 隐私和安全 → 开发者选项)或管理员权限。开启后再跑 `install.ps1`。

**Q:两台机器的 token 是同一个还是各自的?**
A:随你。同一个账号就同一个 token,各机器分别填到自己的 `settings.local.json` 或环境变量里。无论哪种,token 都不进仓库。

## License

[MIT](LICENSE)
