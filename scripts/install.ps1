# install.ps1
# Windows 版:把 dotfiles 仓库里的 Claude Code 配置,以符号链接方式挂到 %USERPROFILE%\.claude\
#
# 用法(以管理员或开启"开发者模式"后在 PowerShell 跑):
#   powershell -ExecutionPolicy Bypass -File install.ps1 [-Dotfiles <路径>]
#
# 注意:Windows 创建符号链接需要"开发者模式"(设置 → 隐私和安全 → 开发者选项)
#       或管理员权限,否则 New-Item -ItemType SymbolicLink 会失败。

param(
    [string]$Dotfiles = "$HOME\dotfiles"
)

$ErrorActionPreference = "Stop"
$Src = Join-Path $Dotfiles "claude"
$ClaudeHome = Join-Path $env:USERPROFILE ".claude"

if (-not (Test-Path $Src)) {
    Write-Error "找不到 $Src`n请先把 dotfiles 仓库 clone 好,或用 -Dotfiles <路径> 传入。"
    exit 1
}

if (-not (Test-Path $ClaudeHome)) { New-Item -ItemType Directory -Path $ClaudeHome | Out-Null }

$items = @("CLAUDE.md","settings.json","keybindings.json","commands","agents","skills","output-styles","hooks")

foreach ($item in $items) {
    $target = Join-Path $Src $item
    $link   = Join-Path $ClaudeHome $item
    if (-not (Test-Path $target)) { continue }

    # 备份已存在的、且不是符号链接的文件
    if ((Test-Path $link) -and -not ((Get-Item $link).LinkType)) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backup = "$link.bak.$stamp"
        Move-Item $link $backup
        Write-Host "  已备份原有 $item -> $backup"
    }

    # 已有符号链接先删,再重建
    if ((Test-Path $link) -and ((Get-Item $link).LinkType)) { Remove-Item $link -Force }
    New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
    Write-Host "✓ $item -> $target"
}

Write-Host ""
Write-Host "完成。"
