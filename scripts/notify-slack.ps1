param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('codex','claude','test')]
    [string]$Agent,
    [string]$Event = '',
    [string]$InputJson = '',
    [string]$ConfigPath = "$HOME/.ai-agent-slack-notifier/config.local.json"
)

$ErrorActionPreference = 'Stop'

function Read-StdinAll {
    if ([Console]::IsInputRedirected) { return [Console]::In.ReadToEnd() }
    return ''
}

function Get-PropertyValue($Object, [string[]]$Names, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    foreach ($name in $Names) {
        $property = $Object.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value -and "$($property.Value)" -ne '') {
            return $property.Value
        }
    }
    return $Default
}

function Get-GitBranch([string]$WorkingDirectory) {
    try {
        $branch = git -C $WorkingDirectory branch --show-current 2>$null
        if ($LASTEXITCODE -eq 0 -and $branch) { return "$branch".Trim() }
    } catch {}
    return ''
}

function Get-ProjectName([string]$WorkingDirectory, $Config) {
    if ($Config.projectOverrides) {
        foreach ($property in $Config.projectOverrides.PSObject.Properties) {
            if ($WorkingDirectory -like "$($property.Name)*") { return "$($property.Value)" }
        }
    }
    try {
        $gitRoot = git -C $WorkingDirectory rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitRoot) { return Split-Path -Leaf "$gitRoot".Trim() }
    } catch {}
    return Split-Path -Leaf $WorkingDirectory
}

if (-not (Test-Path $ConfigPath)) { throw "Configuration file not found: $ConfigPath" }

$config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
if (-not $config.slackWebhookUrl -or $config.slackWebhookUrl -notlike 'https://hooks.slack.com/services/*') {
    throw 'The Slack webhook URL is missing or invalid.'
}

$raw = $InputJson
if (-not $raw) { $raw = Read-StdinAll }
$data = $null
if ($raw) {
    try { $data = $raw | ConvertFrom-Json } catch { $data = $null }
}

if ($Agent -eq 'test') {
    $cwd = (Get-Location).Path
    $eventName = if ($Event) { $Event } else { 'ManualTest' }
    $reason = 'Connection test completed successfully.'
} else {
    $cwd = Get-PropertyValue $data @('cwd','working_directory','workingDirectory') (Get-Location).Path
    $eventName = if ($Event) { $Event } else { Get-PropertyValue $data @('hook_event_name','event','type') 'AttentionRequired' }

    if ($Agent -eq 'claude') {
        $reason = Get-PropertyValue $data @('message','notification','reason') ''
        if (-not $reason) {
            $toolName = Get-PropertyValue $data @('tool_name') ''
            $reason = if ($toolName) { "Claude Code requests permission to use: $toolName" } else { 'Claude Code is waiting for input or authorization.' }
        }
    } else {
        $reason = Get-PropertyValue $data @('reason','message','prompt') ''
        if (-not $reason) {
            $toolName = Get-PropertyValue $data @('tool_name','tool') ''
            $reason = if ($toolName) { "Codex requests permission to use: $toolName" } else { 'Codex is waiting for authorization.' }
        }
    }
}

$project = Get-ProjectName -WorkingDirectory $cwd -Config $config
$branch = Get-GitBranch -WorkingDirectory $cwd
$machine = if ($config.machineName) { "$($config.machineName)" } else { $env:COMPUTERNAME }
$agentLabel = switch ($Agent) { 'claude' { 'Claude Code' } 'codex' { 'Codex' } default { 'Installer' } }
$icon = switch ("$($config.machineIcon)") { 'house' { ':house:' } 'office' { ':office:' } 'laptop' { ':computer:' } 'robot' { ':robot_face:' } default { ':desktop_computer:' } }

$fields = @(
    @{ type = 'mrkdwn'; text = "*Computer:*`n$icon $machine" },
    @{ type = 'mrkdwn'; text = "*Project:*`n$project" },
    @{ type = 'mrkdwn'; text = "*Agent:*`n$agentLabel" },
    @{ type = 'mrkdwn'; text = "*Event:*`n$eventName" }
)
if ($branch) { $fields += @{ type = 'mrkdwn'; text = "*Branch:*`n$branch" } }

$payload = @{
    text = "$agentLabel needs attention on $machine ($project)"
    blocks = @(
        @{ type = 'header'; text = @{ type = 'plain_text'; text = "Attention required: $agentLabel"; emoji = $true } },
        @{ type = 'section'; fields = $fields },
        @{ type = 'section'; text = @{ type = 'mrkdwn'; text = "*Reason:*`n$reason" } },
        @{ type = 'context'; elements = @(@{ type = 'mrkdwn'; text = "Directory: ``$cwd`` | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" }) }
    )
} | ConvertTo-Json -Depth 8

Invoke-RestMethod -Method Post -Uri $config.slackWebhookUrl -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) | Out-Null
