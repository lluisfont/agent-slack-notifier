Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$installRoot = Join-Path $HOME '.ai-agent-slack-notifier'
$marker = '.ai-agent-slack-notifier'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $temporaryPath = "$Path.tmp-$PID"
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 20), $utf8NoBom)
    Move-Item -Force -Path $temporaryPath -Destination $Path
}

function Test-NotifierMatcherGroup {
    param($Group)

    if ($null -eq $Group) {
        return $false
    }

    $hooksProperty = $Group.PSObject.Properties['hooks']
    if ($null -eq $hooksProperty) {
        return $false
    }

    foreach ($handler in @($hooksProperty.Value)) {
        if ($null -eq $handler) {
            continue
        }

        foreach ($propertyName in @('command', 'commandWindows')) {
            $property = $handler.PSObject.Properties[$propertyName]
            if ($null -ne $property -and "$($property.Value)" -like "*$marker*") {
                return $true
            }
        }
    }

    return $false
}

function Remove-HookGroups {
    param(
        [Parameter(Mandatory = $true)]$HooksObject,
        [Parameter(Mandatory = $true)][string]$EventName
    )

    $property = $HooksObject.PSObject.Properties[$EventName]
    if ($null -eq $property) {
        return
    }

    $property.Value = @($property.Value | Where-Object { -not (Test-NotifierMatcherGroup -Group $_) })
}

$claudeSettingsPath = Join-Path $HOME '.claude/settings.json'
if (Test-Path $claudeSettingsPath) {
    try {
        $settings = Get-Content -Raw -Path $claudeSettingsPath | ConvertFrom-Json
        if ($null -ne $settings.PSObject.Properties['hooks']) {
            Remove-HookGroups -HooksObject $settings.hooks -EventName 'Notification'
            Write-JsonFile -Path $claudeSettingsPath -Value $settings
        }
    }
    catch {
        throw "Could not safely update '$claudeSettingsPath'. No notifier files were removed. $($_.Exception.Message)"
    }
}

$codexHooksPath = Join-Path $HOME '.codex/hooks.json'
if (Test-Path $codexHooksPath) {
    try {
        $hooksDocument = Get-Content -Raw -Path $codexHooksPath | ConvertFrom-Json
        if ($null -ne $hooksDocument.PSObject.Properties['hooks']) {
            Remove-HookGroups -HooksObject $hooksDocument.hooks -EventName 'PermissionRequest'
            Write-JsonFile -Path $codexHooksPath -Value $hooksDocument
        }
    }
    catch {
        throw "Could not safely update '$codexHooksPath'. No notifier files were removed. $($_.Exception.Message)"
    }
}

if (Test-Path $installRoot) {
    Remove-Item -Recurse -Force -Path $installRoot
}

Write-Host 'AI Agent Slack Notifier uninstalled. Existing agent configuration was preserved.' -ForegroundColor Green
Write-Host 'The Codex hooks feature flag was left enabled because other hooks may depend on it.' -ForegroundColor Yellow
