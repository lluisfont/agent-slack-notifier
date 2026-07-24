param(
    [ValidateSet('Both', 'Codex', 'Claude')]
    [string]$Agents = 'Both',

    [string]$MachineName = $env:COMPUTERNAME,

    [ValidateSet('house', 'office', 'laptop', 'robot', 'desktop')]
    [string]$MachineIcon = 'desktop',

    [string]$SlackWebhookUrl = '',

    [switch]$NonInteractive,
    [switch]$SkipTest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installRoot = Join-Path $HOME '.ai-agent-slack-notifier'
$configPath = Join-Path $installRoot 'config.local.json'
$scriptPath = Join-Path $installRoot 'notify-slack.ps1'
$marker = '.ai-agent-slack-notifier'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $directory = Split-Path -Parent $Path
    if ($directory) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $temporaryPath = "$Path.tmp-$PID"
    [System.IO.File]::WriteAllText($temporaryPath, $Content, $utf8NoBom)
    Move-Item -Force -Path $temporaryPath -Destination $Path
}

function Backup-File {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path $Path) {
        $backupPath = "$Path.backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -Path $Path -Destination $backupPath -Force
        return $backupPath
    }

    return $null
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][scriptblock]$DefaultFactory
    )

    if (-not (Test-Path $Path)) {
        return & $DefaultFactory
    }

    try {
        $raw = Get-Content -Raw -Path $Path
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return & $DefaultFactory
        }
        return $raw | ConvertFrom-Json
    }
    catch {
        throw "Invalid JSON in '$Path'. The file was not modified. $($_.Exception.Message)"
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 20
    Write-Utf8File -Path $Path -Content $json
}

function Set-ObjectProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
    else {
        $property.Value = $Value
    }
}

function Protect-StringForCurrentUser {
    param([Parameter(Mandatory = $true)][string]$Value)

    $secureValue = ConvertTo-SecureString -String $Value -AsPlainText -Force
    return ConvertFrom-SecureString -SecureString $secureValue
}

function Unprotect-StringForCurrentUser {
    param([Parameter(Mandatory = $true)][string]$Value)

    $secureValue = ConvertTo-SecureString -String $Value
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
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

function Remove-NotifierMatcherGroups {
    param($Groups)

    return @($Groups | Where-Object { -not (Test-NotifierMatcherGroup -Group $_) })
}

function Enable-CodexHooksFeature {
    $codexDirectory = Join-Path $HOME '.codex'
    $configTomlPath = Join-Path $codexDirectory 'config.toml'
    New-Item -ItemType Directory -Force -Path $codexDirectory | Out-Null

    if (-not (Test-Path $configTomlPath)) {
        Write-Utf8File -Path $configTomlPath -Content "[features]`r`nhooks = true`r`n"
        return
    }

    Backup-File -Path $configTomlPath | Out-Null
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [System.IO.File]::ReadAllLines($configTomlPath)) {
        $lines.Add($line)
    }

    $featuresStart = -1
    $featuresEnd = $lines.Count

    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*\[features\]\s*(?:#.*)?$') {
            $featuresStart = $index
            break
        }
    }

    if ($featuresStart -ge 0) {
        for ($index = $featuresStart + 1; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match '^\s*\[[^\]]+\]\s*(?:#.*)?$') {
                $featuresEnd = $index
                break
            }
        }

        $hooksLine = -1
        for ($index = $featuresStart + 1; $index -lt $featuresEnd; $index++) {
            if ($lines[$index] -match '^\s*hooks\s*=') {
                $hooksLine = $index
                break
            }
        }

        if ($hooksLine -ge 0) {
            $lines[$hooksLine] = 'hooks = true'
        }
        else {
            $lines.Insert($featuresStart + 1, 'hooks = true')
        }
    }
    else {
        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
            $lines.Add('')
        }
        $lines.Add('[features]')
        $lines.Add('hooks = true')
    }

    Write-Utf8File -Path $configTomlPath -Content (($lines -join "`r`n") + "`r`n")
}

function Install-ClaudeHooks {
    $claudeDirectory = Join-Path $HOME '.claude'
    $settingsPath = Join-Path $claudeDirectory 'settings.json'
    New-Item -ItemType Directory -Force -Path $claudeDirectory | Out-Null

    $settings = Read-JsonFile -Path $settingsPath -DefaultFactory { [pscustomobject]@{} }
    if (Test-Path $settingsPath) {
        Backup-File -Path $settingsPath | Out-Null
    }

    if ($null -eq $settings.PSObject.Properties['hooks']) {
        $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
    }

    $notificationGroups = @()
    $notificationProperty = $settings.hooks.PSObject.Properties['Notification']
    if ($null -ne $notificationProperty) {
        $notificationGroups = Remove-NotifierMatcherGroups -Groups @($notificationProperty.Value)
    }

    $command = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Agent claude' -f $scriptPath
    foreach ($notificationType in @('permission_prompt', 'idle_prompt', 'elicitation_dialog')) {
        $notificationGroups += [pscustomobject]@{
            matcher = $notificationType
            hooks = @(
                [pscustomobject]@{
                    type = 'command'
                    command = $command
                    timeout = 15
                }
            )
        }
    }

    Set-ObjectProperty -Object $settings.hooks -Name 'Notification' -Value @($notificationGroups)
    Write-JsonFile -Path $settingsPath -Value $settings
}

function Install-CodexHooks {
    $codexDirectory = Join-Path $HOME '.codex'
    $hooksPath = Join-Path $codexDirectory 'hooks.json'
    New-Item -ItemType Directory -Force -Path $codexDirectory | Out-Null

    $hooksDocument = Read-JsonFile -Path $hooksPath -DefaultFactory {
        [pscustomobject]@{
            description = 'User lifecycle hooks'
            hooks = [pscustomobject]@{}
        }
    }

    if (Test-Path $hooksPath) {
        Backup-File -Path $hooksPath | Out-Null
    }

    if ($null -eq $hooksDocument.PSObject.Properties['hooks']) {
        $hooksDocument | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
    }

    $permissionGroups = @()
    $permissionProperty = $hooksDocument.hooks.PSObject.Properties['PermissionRequest']
    if ($null -ne $permissionProperty) {
        $permissionGroups = Remove-NotifierMatcherGroups -Groups @($permissionProperty.Value)
    }

    $command = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Agent codex' -f $scriptPath
    $permissionGroups += [pscustomobject]@{
        hooks = @(
            [pscustomobject]@{
                type = 'command'
                command = $command
                commandWindows = $command
                timeout = 15
                statusMessage = 'Sending Slack notification'
            }
        )
    }

    Set-ObjectProperty -Object $hooksDocument.hooks -Name 'PermissionRequest' -Value @($permissionGroups)
    Write-JsonFile -Path $hooksPath -Value $hooksDocument
    Enable-CodexHooksFeature
}

if ($env:OS -ne 'Windows_NT') {
    throw 'This installer currently supports Windows only.'
}

New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
Copy-Item -Path (Join-Path $repoRoot 'scripts/notify-slack.ps1') -Destination $scriptPath -Force

$existingConfig = Read-JsonFile -Path $configPath -DefaultFactory { [pscustomobject]@{} }
if (-not $SlackWebhookUrl -and -not $NonInteractive) {
    $SlackWebhookUrl = Read-Host 'Paste the Slack Incoming Webhook URL'
}

if (-not $SlackWebhookUrl) {
    $protectedProperty = $existingConfig.PSObject.Properties['slackWebhookProtected']
    if ($null -ne $protectedProperty -and -not [string]::IsNullOrWhiteSpace("$($protectedProperty.Value)")) {
        try {
            $SlackWebhookUrl = Unprotect-StringForCurrentUser -Value "$($protectedProperty.Value)"
        }
        catch {
            throw 'The existing protected Slack webhook could not be decrypted for this Windows user. Run the installer again and provide the webhook URL.'
        }
    }
    else {
        $legacyProperty = $existingConfig.PSObject.Properties['slackWebhookUrl']
        if ($null -ne $legacyProperty) {
            $SlackWebhookUrl = "$($legacyProperty.Value)"
        }
    }
}

if (-not $SlackWebhookUrl) {
    throw 'SlackWebhookUrl is required.'
}

if ($SlackWebhookUrl -notmatch '^https://hooks\.slack\.com/services/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$') {
    throw 'The Slack Incoming Webhook URL format is invalid.'
}

$projectOverrides = [pscustomobject]@{}
$projectOverridesProperty = $existingConfig.PSObject.Properties['projectOverrides']
if ($null -ne $projectOverridesProperty -and $null -ne $projectOverridesProperty.Value) {
    $projectOverrides = $projectOverridesProperty.Value
}

$duplicateWindowSeconds = 30
$duplicateProperty = $existingConfig.PSObject.Properties['duplicateWindowSeconds']
if ($null -ne $duplicateProperty -and [int]$duplicateProperty.Value -ge 0) {
    $duplicateWindowSeconds = [int]$duplicateProperty.Value
}

$requestTimeoutSeconds = 10
$timeoutProperty = $existingConfig.PSObject.Properties['requestTimeoutSeconds']
if ($null -ne $timeoutProperty -and [int]$timeoutProperty.Value -gt 0) {
    $requestTimeoutSeconds = [int]$timeoutProperty.Value
}

$config = [ordered]@{
    schemaVersion = 2
    slackWebhookProtected = Protect-StringForCurrentUser -Value $SlackWebhookUrl
    machineName = $MachineName
    machineIcon = $MachineIcon
    duplicateWindowSeconds = $duplicateWindowSeconds
    requestTimeoutSeconds = $requestTimeoutSeconds
    projectOverrides = $projectOverrides
}

if (Test-Path $configPath) {
    Backup-File -Path $configPath | Out-Null
}
Write-JsonFile -Path $configPath -Value $config

if ($Agents -in @('Both', 'Claude')) {
    Install-ClaudeHooks
}

if ($Agents -in @('Both', 'Codex')) {
    Install-CodexHooks
}

Write-Host "Installation completed in $installRoot" -ForegroundColor Green
if ($Agents -in @('Both', 'Codex')) {
    Write-Host 'Codex CLI: restart Codex, run /hooks, and trust the PermissionRequest hook.' -ForegroundColor Yellow
    Write-Host 'Codex Desktop and IDE extensions are not guaranteed to execute user hooks; this repository supports Codex CLI.' -ForegroundColor Yellow
}

if (-not $SkipTest) {
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath -Agent test -Event InstallationTest
    if ($LASTEXITCODE -ne 0) {
        throw 'The Slack test notification failed. Review the notifier log and run .\test.ps1.'
    }
    Write-Host 'Test notification sent to Slack.' -ForegroundColor Green
}
