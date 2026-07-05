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

# MCP servers:从 dotfiles 的 mcp-servers.json 导入到本机 user scope
$mcpJson = Join-Path $Src "mcp-servers.json"
if (Test-Path $mcpJson) {
    Write-Host ""
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Host "=== 导入 MCP servers(user scope)==="
        $mcp = Get-Content $mcpJson -Raw | ConvertFrom-Json
        $added = 0; $skipped = 0; $failed = 0
        foreach ($prop in $mcp.PSObject.Properties) {
            $name = $prop.Name; $cfg = $prop.Value
            & claude mcp get $name 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Host "  - 跳过(已存在): $name"; $skipped++; continue }
            $cfgJson = $cfg | ConvertTo-Json -Depth 100 -Compress
            & claude mcp add-json $name $cfgJson -s user 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $todo = @()
                if ($cfg.env) {
                    $ek = @(); foreach ($e in $cfg.env.PSObject.Properties) { $ek += $e.Name }
                    if ($ek.Count) { $todo += "env=[$($ek -join ',')]" }
                }
                if ($cfg.headers) {
                    $hk = @(); foreach ($h in $cfg.headers.PSObject.Properties) { $hk += $h.Name }
                    if ($hk.Count) { $todo += "headers=[$($hk -join ',')]" }
                }
                $hint = ""; if ($todo.Count) { $hint = "  ! 待填: $($todo -join ', ')" }
                Write-Host "  + 新增: $name$hint"
                $added++
            } else { Write-Host "  x 失败: $name"; $failed++ }
        }
        Write-Host "  汇总: 新增 $added, 跳过 $skipped, 失败 $failed"
        Write-Host "  提示:env/headers 是 ***REDACTED*** 占位,需手动填回真实凭证"
    } else {
        Write-Host "发现 $mcpJson 但本机没有 claude 命令,跳过 MCP 导入(装好 claude 后重跑即可)"
    }
}

Write-Host ""
Write-Host "完成。"
