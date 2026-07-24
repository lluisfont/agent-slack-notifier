$ErrorActionPreference = 'Stop'
$installRoot = Join-Path $HOME '.ai-agent-slack-notifier'

$claudeSettings = Join-Path $HOME '.claude/settings.json'
if (Test-Path $claudeSettings) {
    $settings = Get-Content -Raw $claudeSettings | ConvertFrom-Json
    if ($settings.hooks.Notification) {
        $settings.hooks.Notification = @(
            $settings.hooks.Notification | Where-Object {
                ($_.hooks.command -join ' ') -notmatch 'ai-agent-slack-notifier'
            }
        )
        $settings | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 $claudeSettings
    }
}

$codexHooks = Join-Path $HOME '.codex/hooks.json'
if (Test-Path $codexHooks) {
    $hooks = Get-Content -Raw $codexHooks | ConvertFrom-Json
    if ($hooks.hooks.PermissionRequest) {
        $hooks.hooks.PermissionRequest = @(
            $hooks.hooks.PermissionRequest | Where-Object {
                ($_.hooks.command -join ' ') -notmatch 'ai-agent-slack-notifier'
            }
        )
        $hooks | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 $codexHooks
    }
}

if (Test-Path $installRoot) { Remove-Item -Recurse -Force $installRoot }
Write-Host 'AI Agent Slack Notifier uninstalled.' -ForegroundColor Green
