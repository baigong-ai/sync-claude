# pack-claude-config.ps1
# Windows 版:把 Claude Code 的"个人配置"导出成一个 zip(自动脱敏)。
# 用途:整合多台机器时,把各台配置收集到一起做 diff / 合并。
# 与 macOS / Linux 版的 pack-claude-config.sh 等价。
#
# 用法(PowerShell):
#   powershell -ExecutionPolicy Bypass -File pack-claude-config.ps1 [-OutDir <输出目录>]
#   默认输出到 %USERPROFILE%

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

# 1) 个人配置文件 / 目录(有则打包)
foreach ($item in @("CLAUDE.md", "keybindings.json", "commands", "agents", "output-styles", "hooks")) {
    $p = Join-Path $ClaudeHome $item
    if (Test-Path $p) { Copy-Item -Path $p -Destination $Dst -Recurse -Force }
}

# skills:全量打包(合并时人工区分"自定义" vs "插件自带")
$skillsPath = Join-Path $ClaudeHome "skills"
if (Test-Path $skillsPath) { Copy-Item -Path $skillsPath -Destination $Dst -Recurse -Force }

# 插件清单(让目标机器能装上同样的插件)
$pluginsJson = Join-Path $ClaudeHome "plugins\installed_plugins.json"
if (Test-Path $pluginsJson) {
    $pluginsDst = Join-Path $Dst "plugins"
    New-Item -ItemType Directory -Path $pluginsDst -Force | Out-Null
    Copy-Item -Path $pluginsJson -Destination $pluginsDst -Force
}

# 2) settings.json:脱敏后写入(token/key/secret 类字段替换为 ***REDACTED***)
$settingsSrc = Join-Path $ClaudeHome "settings.json"
if (Test-Path $settingsSrc) {
    $d = Get-Content $settingsSrc -Raw | ConvertFrom-Json

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

    $d = Invoke-Redact $d
    ($d | ConvertTo-Json -Depth 100) | Set-Content -Path (Join-Path $Dst "settings.json") -Encoding UTF8
}

# 3) 打包
Compress-Archive -Path (Join-Path $Tmp "*") -DestinationPath $Out -Force
Remove-Item -Recurse -Force $Tmp

Write-Host "✓ 导出完成: $Out"
Write-Host "  把这个文件传到整合用的那台机器上"
