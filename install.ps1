param(
    [ValidateSet('Both','Codex','Claude')]
    [string]$Agents = 'Both',
    [string]$MachineName = $env:COMPUTERNAME,
    [ValidateSet('house','office','laptop','robot','desktop')]
    [string]$MachineIcon = 'desktop',
    [string]$SlackWebhookUrl = '',
    [switch]$NonInteractive,
    [switch]$SkipTest
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installRoot = Join-Path $HOME '.ai-agent-slack-notifier'
$configPath = Join-Path $installRoot 'config.local.json'
$scriptPath = Join-Path $installRoot 'notify-slack.ps1'

New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
Copy-Item (Join-Path $repoRoot 'scripts/notify-slack.ps1') $scriptPath -Force

if (-not $SlackWebhookUrl -and -not $NonInteractive) {
    $SlackWebhookUrl = Read-Host 'Paste the Slack Incoming Webhook URL'
}
if (-not $SlackWebhookUrl -and (Test-Path $configPath)) {
    $existing = Get-Content -Raw $configPath | ConvertFrom-Json
    $SlackWebhookUrl = $existing.slackWebhookUrl
}
if (-not $SlackWebhookUrl) { throw 'SlackWebhookUrl is required.' }
if ($SlackWebhookUrl -notlike 'https://hooks.slack.com/services/*') { throw 'The Slack webhook URL is invalid.' }

$config = [ordered]@{
    slackWebhookUrl = $SlackWebhookUrl
    machineName = $MachineName
    machineIcon = $MachineIcon
    notifyOnCompletion = $false
    projectOverrides = @{}
}
$config | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $configPath

function Merge-ClaudeHook {
    $claudeDir = Join-Path $HOME '.claude'
    $settingsPath = Join-Path $claudeDir 'settings.json'
    New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
    if (Test-Path $settingsPath) {
        Copy-Item $settingsPath "$settingsPath.backup-$(Get-Date -Format yyyyMMddHHmmss)"
        $settings = Get-Content -Raw $settingsPath | ConvertFrom-Json
    } else {
        $settings = [pscustomobject]@{}
    }

    if (-not $settings.PSObject.Properties['hooks']) {
        $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
    }

    $command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Agent claude -Event Notification"
    $entry = @([pscustomobject]@{
        matcher = 'permission_prompt|idle_prompt|agent_needs_input'
        hooks = @([pscustomobject]@{
            type = 'command'
            command = $command
            timeout = 10
        })
    })

    if ($settings.hooks.PSObject.Properties['Notification']) {
        $settings.hooks.Notification = @(
            $settings.hooks.Notification | Where-Object {
                ($_.hooks.command -join ' ') -notmatch 'ai-agent-slack-notifier'
            }
        ) + $entry
    } else {
        $settings.hooks | Add-Member -NotePropertyName Notification -NotePropertyValue $entry
    }

    $settings | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 $settingsPath
}

function Install-CodexHook {
    $codexDir = Join-Path $HOME '.codex'
    $hooksPath = Join-Path $codexDir 'hooks.json'
    New-Item -ItemType Directory -Force -Path $codexDir | Out-Null

    if (Test-Path $hooksPath) {
        Copy-Item $hooksPath "$hooksPath.backup-$(Get-Date -Format yyyyMMddHHmmss)"
        $existing = Get-Content -Raw $hooksPath | ConvertFrom-Json
    } else {
        $existing = [pscustomobject]@{
            description = 'User lifecycle hooks'
            hooks = [pscustomobject]@{}
        }
    }

    if (-not $existing.PSObject.Properties['hooks']) {
        $existing | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
    }

    $command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Agent codex -Event PermissionRequest"
    $entry = @([pscustomobject]@{
        matcher = '*'
        hooks = @([pscustomobject]@{
            type = 'command'
            command = $command
            commandWindows = $command
            timeout = 10
            statusMessage = 'Sending Slack notification'
        })
    })

    if ($existing.hooks.PSObject.Properties['PermissionRequest']) {
        $existing.hooks.PermissionRequest = @(
            $existing.hooks.PermissionRequest | Where-Object {
                ($_.hooks.command -join ' ') -notmatch 'ai-agent-slack-notifier'
            }
        ) + $entry
    } else {
        $existing.hooks | Add-Member -NotePropertyName PermissionRequest -NotePropertyValue $entry
    }

    $existing | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 $hooksPath
}

if ($Agents -in @('Both','Claude')) { Merge-ClaudeHook }
if ($Agents -in @('Both','Codex')) { Install-CodexHook }

Write-Host "Installation completed in $installRoot" -ForegroundColor Green
Write-Host 'Codex: open /hooks and trust the PermissionRequest hook after restarting.' -ForegroundColor Yellow

if (-not $SkipTest) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Agent test -Event InstallationTest
    Write-Host 'Test notification sent to Slack.' -ForegroundColor Green
}
