# 推荐的 dotfiles 仓库布局

把整合好的 Claude Code 配置,组织成下面这个结构,放进你自己的 dotfiles 仓库:

```
~/dotfiles/
├── claude/
│   ├── CLAUDE.md                    # 全局个人指令
│   ├── settings.json                # 脱敏(无 token):模型映射、插件开关、超时等
│   ├── keybindings.json             # 可选
│   ├── commands/                    # 自定义 slash commands(.md)
│   ├── skills/                      # 仅放"自定义" skill;插件自带的 skill 不放
│   ├── agents/                      # 可选,自定义 subagents
│   ├── output-styles/               # 可选
│   └── plugins/
│       └── installed_plugins.json   # 插件清单,目标机器据此 /plugin install
├── install.sh                       # macOS / Linux 安装(符号链接)
├── install.ps1                      # Windows 安装
└── .gitignore                       # 用 examples/dotfiles.gitignore 这份
```

> `install.sh` / `install.ps1` 直接用 `cc-sync/scripts/` 里的就行,它们默认读 `~/dotfiles/claude/`。

## 怎么用

1. 在 GitHub 建一个 **private** 仓库(配置里有你的个人指令和工作习惯,不建议 public)。
2. 在一台机器上把 `~/dotfiles/` 初始化、按上面的布局填入配置、push。
3. 在其它机器 `git clone`,跑 `install.sh`(或 `install.ps1`)。
4. 以后改了配置,直接在 `~/dotfiles/` 里 commit + push;其它机器 pull 即可生效。

## 敏感信息(token)怎么放

**不要**把 token 写进 `claude/settings.json`(它要进仓库)。两种替代:

**方式 A(推荐,跨平台):写进 shell 环境变量**

```bash
# macOS:~/.zshrc
export ANTHROPIC_AUTH_TOKEN="你的token"
```
```powershell
# Windows:PowerShell $PROFILE
$env:ANTHROPIC_AUTH_TOKEN = "你的token"
```

**方式 B:放进 `~/.claude/settings.local.json`(被 .gitignore 排除,只在本地存在)**

```json
{ "env": { "ANTHROPIC_AUTH_TOKEN": "你的token" } }
```
