# pack-claude-config.ps1
# Windows 版:把 Claude Code 的"个人配置"导出成一个 zip(自动脱敏)。
# 与 macOS / Linux 版的 pack-claude-config.sh 等价。
#
# 用法(PowerShell):
#   powershell -ExecutionPolicy Bypass -File pack-claude-config.ps1 [-OutDir <输出目录>]
#   默认输出到 %USERPROFILE%
#
# 打包策略(覆盖 Claude Code 全部个人配置):见同名 .sh 的注释。

param(
    [string]$OutDir = "$HOME"
)

$ErrorActionPreference = "Stop"
$Name = $env:COMPUTERNAME
if (-not $Name) { $Name = "windows" }
$Out = Join-Path $OutDir "claude-config-$Name.zip"
$ClaudeHome = Join-Path $env:USERPROFILE ".claude"

if (-not (Test-Path $ClaudeHome)) {
    Write-Error "找不到 $ClaudeHome"
    exit 1
}

$Tmp = Join-Path $env:TEMP ("cc-pack-" + [guid]::NewGuid().ToString("N"))
$Dst = Join-Path $Tmp ".claude"
New-Item -ItemType Directory -Path $Dst -Force | Out-Null

# 1) 个人配置文件 / 目录
foreach ($item in @("CLAUDE.md", "keybindings.json", "commands", "agents", "output-styles", "hooks")) {
    $p = Join-Path $ClaudeHome $item
    if (Test-Path $p) { Copy-Item -Path $p -Destination $Dst -Recurse -Force }
}

# 2) skills:只打"自定义"(无 LICENSE 的)
$skillsSrc = Join-Path $ClaudeHome "skills"
if (Test-Path $skillsSrc) {
    $skillsDst = Join-Path $Dst "skills"
    New-Item -ItemType Directory -Path $skillsDst -Force | Out-Null
    Get-ChildItem $skillsSrc -Directory | ForEach-Object {
        $hasLic = (Test-Path (Join-Path $_.FullName "LICENSE.txt")) -or (Test-Path (Join-Path $_.FullName "LICENSE"))
        if ($hasLic) {
            Write-Host "  - 跳过 skill(官方/插件,带 LICENSE): $($_.Name)"
        } else {
            Copy-Item -Path $_.FullName -Destination $skillsDst -Recurse -Force
            Write-Host "  - 打包 skill(自定义): $($_.Name)"
        }
    }
}

# 3) plugins:打包清单文件
$pluginsSrc = Join-Path $ClaudeHome "plugins"
$ipJson = Join-Path $pluginsSrc "installed_plugins.json"
$kmJson = Join-Path $pluginsSrc "known_marketplaces.json"
if ((Test-Path $ipJson) -or (Test-Path $kmJson)) {
    $pluginsDst = Join-Path $Dst "plugins"
    New-Item -ItemType Directory -Path $pluginsDst -Force | Out-Null
    if (Test-Path $ipJson) { Copy-Item $ipJson -Destination $pluginsDst -Force }
    if (Test-Path $kmJson) { Copy-Item $kmJson -Destination $pluginsDst -Force }
}

# 4) settings.json 脱敏
$settingsSrc = Join-Path $ClaudeHome "settings.json"
$settings = $null
if (Test-Path $settingsSrc) {
    $settings = Get-Content $settingsSrc -Raw | ConvertFrom-Json

    function Invoke-Redact($o) {
        if ($o -is [System.Management.Automation.PSCustomObject]) {
            foreach ($name in @($o.PSObject.Properties.Name)) {
                if ($name -match '(?i)(token|key|secret|password|auth|credential)' -and $o.$name) {
                    $o.$name = "***REDACTED***"
                } else {
                    $o.$name = Invoke-Redact $o.$name
                }
            }
        } elseif ($o -is [System.Collections.IList]) {
            for ($i = 0; $i -lt $o.Count; $i++) { $o[$i] = Invoke-Redact $o[$i] }
        }
        return $o
    }

    $settings = Invoke-Redact $settings
    ($settings | ConvertTo-Json -Depth 100) | Set-Content -Path (Join-Path $Dst "settings.json") -Encoding UTF8
}

# 5) MCP servers:从 ~/.claude.json 提取,env 值全脱敏(保留 key 名)
$claudeJson = Join-Path $env:USERPROFILE ".claude.json"
$mcpAll = $null
if (Test-Path $claudeJson) {
    $cjd = Get-Content $claudeJson -Raw | ConvertFrom-Json
    $mcpAll = $cjd.mcpServers
}

$mcpExport = [ordered]@{}
if ($mcpAll) {
    foreach ($prop in $mcpAll.PSObject.Properties) {
        $cfg = $prop.Value
        $new = [ordered]@{}
        foreach ($c in $cfg.PSObject.Properties) {
            if (($c.Name -eq "env" -or $c.Name -eq "headers") -and $c.Value) {
                $red = [ordered]@{}
                foreach ($e in $c.Value.PSObject.Properties) { $red[$e.Name] = "***REDACTED***" }
                $new[$c.Name] = $red
            } else {
                $new[$c.Name] = $c.Value
            }
        }
        $mcpExport[$prop.Name] = $new
    }
}
($mcpExport | ConvertTo-Json -Depth 100) | Set-Content -Path (Join-Path $Dst "mcp-servers.json") -Encoding UTF8

# 6) 生成可读 inventory(插件 + MCP)
function Get-JsonFile($p) {
    if (Test-Path $p) { return Get-Content $p -Raw | ConvertFrom-Json } else { return $null }
}
$installed    = Get-JsonFile $ipJson
$marketplaces = Get-JsonFile $kmJson

$lines = @()
$lines += "# Claude Code 配置清单 - $Name"
$lines += ""
$lines += "_由 pack-claude-config 生成_"
$lines += ""

$lines += "## 已安装插件 (installed_plugins.json)"
if ($installed -and $installed.plugins) {
    $installed.plugins.PSObject.Properties | ForEach-Object {
        $spec = $_.Name
        $_.Value | ForEach-Object {
            $ver = $_.version; if (-not $ver) { $ver = "?" }
            $scope = $_.scope; if (-not $scope) { $scope = "?" }
            $ts = "$($_.installedAt)"; if ($ts.Length -ge 10) { $ts = $ts.Substring(0, 10) }
            $lines += "- $spec v$ver - scope=$scope, installed $ts"
        }
    }
} else { $lines += "_(无)_" }
$lines += ""

$lines += "## 启用的插件 (settings.json -> enabledPlugins)"
if ($settings -and $settings.enabledPlugins) {
    $settings.enabledPlugins.PSObject.Properties | ForEach-Object {
        $lines += "- $($_.Name) = $($_.Value)"
    }
} else { $lines += "_(无)_" }
$lines += ""

$lines += "## 已知插件市场 (known_marketplaces.json)"
if ($marketplaces) {
    $marketplaces.PSObject.Properties | ForEach-Object {
        $mktName = $_.Name; $src = $_.Value.source
        $kind = "?"; $loc = "?"
        if ($src) { $kind = $src.source; $loc = $src.repo; if (-not $loc) { $loc = $src.path } }
        $lines += "- $mktName - ${kind}: $loc"
    }
} else { $lines += "_(无)_" }
$lines += ""

$lines += "## MCP servers (~/.claude.json -> mcpServers)"
if ($mcpAll) {
    foreach ($prop in $mcpAll.PSObject.Properties) {
        $cfg = $prop.Value
        $transport = $cfg.type; if (-not $transport) { $transport = "stdio" }
        $cmd = $cfg.command; if (-not $cmd) { $cmd = $cfg.url }; if (-not $cmd) { $cmd = "?" }
        $parts = @()
        if ($cfg.env) {
            $keys = @(); foreach ($e in $cfg.env.PSObject.Properties) { $keys += $e.Name }
            if ($keys.Count -gt 0) { $parts += "env=[$($keys -join ', ')]" }
        }
        if ($cfg.headers) {
            $keys = @(); foreach ($e in $cfg.headers.PSObject.Properties) { $keys += $e.Name }
            if ($keys.Count -gt 0) { $parts += "headers=[$($keys -join ', ')]" }
        }
        $extra = ""; if ($parts.Count -gt 0) { $extra = ", $($parts -join ', ')" }
        $lines += "- $($prop.Name) - $transport, $cmd$extra"
    }
} else { $lines += "_(无)_" }
$lines += ""

($lines -join "`n") | Set-Content -Path (Join-Path $Dst "plugins-inventory.md") -Encoding UTF8

# 7) 打包
Compress-Archive -Path (Join-Path $Tmp "*") -DestinationPath $Out -Force
Remove-Item -Recurse -Force $Tmp

Write-Host "✓ 导出完成: $Out"
Write-Host "  把这个文件传到整合用的那台机器上"
