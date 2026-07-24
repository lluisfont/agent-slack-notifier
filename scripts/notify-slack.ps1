param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('codex', 'claude', 'test')]
    [string]$Agent,

    [string]$Event = '',
    [string]$InputJson = '',
    [string]$ConfigPath = "$HOME/.ai-agent-slack-notifier/config.local.json"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-NotifierLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    try {
        $logDirectory = Split-Path -Parent $ConfigPath
        New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
        $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        Add-Content -Path (Join-Path $logDirectory 'notifier.log') -Value $line -Encoding UTF8
    }
    catch {
        # Logging must never break the agent hook.
    }
}

function Read-StdinAll {
    if ([Console]::IsInputRedirected) {
        return [Console]::In.ReadToEnd()
    }
    return ''
}

function Get-PropertyValue {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string[]]$Names,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    foreach ($name in $Names) {
        $property = $Object.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value -and -not [string]::IsNullOrWhiteSpace("$($property.Value)")) {
            return $property.Value
        }
    }

    return $Default
}

function ConvertFrom-ProtectedString {
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

function Limit-Text {
    param(
        $Value,
        [int]$MaximumLength = 1200
    )

    $text = "$Value"
    $text = $text -replace "`0", ''
    if ($text.Length -le $MaximumLength) {
        return $text
    }

    return $text.Substring(0, [Math]::Max(0, $MaximumLength - 1)) + '…'
}

function Escape-SlackText {
    param($Value)

    $text = Limit-Text -Value $Value
    return $text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

function Get-GitBranch {
    param([Parameter(Mandatory = $true)][string]$WorkingDirectory)

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return ''
    }

    try {
        $branch = & git -C $WorkingDirectory branch --show-current 2>$null
        if ($LASTEXITCODE -eq 0 -and $branch) {
            return "$branch".Trim()
        }
    }
    catch {
        Write-NotifierLog -Level 'WARN' -Message "Git branch detection failed: $($_.Exception.Message)"
    }

    return ''
}

function Find-ProjectConfig {
    param([Parameter(Mandatory = $true)][string]$WorkingDirectory)

    try {
        $current = [System.IO.DirectoryInfo]::new([System.IO.Path]::GetFullPath($WorkingDirectory))
    }
    catch {
        return $null
    }

    while ($null -ne $current) {
        $candidate = Join-Path $current.FullName '.ai-agent-project.json'
        if (Test-Path $candidate) {
            return $candidate
        }
        $current = $current.Parent
    }

    return $null
}

function Get-ProjectName {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)]$Config
    )

    $projectConfigPath = Find-ProjectConfig -WorkingDirectory $WorkingDirectory
    if ($projectConfigPath) {
        try {
            $projectConfig = Get-Content -Raw -Path $projectConfigPath | ConvertFrom-Json
            $projectName = Get-PropertyValue -Object $projectConfig -Names @('project', 'projectName', 'name') -Default ''
            if ($projectName) {
                return Limit-Text -Value $projectName -MaximumLength 200
            }
        }
        catch {
            Write-NotifierLog -Level 'WARN' -Message "Invalid project config '$projectConfigPath': $($_.Exception.Message)"
        }
    }

    if ($null -ne $Config.PSObject.Properties['projectOverrides'] -and $Config.projectOverrides) {
        $normalizedWorkingDirectory = [System.IO.Path]::GetFullPath($WorkingDirectory).TrimEnd('\')
        foreach ($property in $Config.projectOverrides.PSObject.Properties) {
            try {
                $overridePath = [System.IO.Path]::GetFullPath("$($property.Name)").TrimEnd('\')
                if ($normalizedWorkingDirectory.StartsWith($overridePath, [StringComparison]::OrdinalIgnoreCase)) {
                    return Limit-Text -Value $property.Value -MaximumLength 200
                }
            }
            catch {
                continue
            }
        }
    }

    if (Get-Command git -ErrorAction SilentlyContinue) {
        try {
            $gitRoot = & git -C $WorkingDirectory rev-parse --show-toplevel 2>$null
            if ($LASTEXITCODE -eq 0 -and $gitRoot) {
                return Split-Path -Leaf "$gitRoot".Trim()
            }
        }
        catch {
            Write-NotifierLog -Level 'WARN' -Message "Git root detection failed: $($_.Exception.Message)"
        }
    }

    return Split-Path -Leaf $WorkingDirectory
}

function Test-DuplicateNotification {
    param(
        [Parameter(Mandatory = $true)][string]$Fingerprint,
        [Parameter(Mandatory = $true)][int]$WindowSeconds
    )

    if ($WindowSeconds -le 0) {
        return $false
    }

    $statePath = Join-Path (Split-Path -Parent $ConfigPath) 'last-notification.json'
    $now = [DateTimeOffset]::UtcNow

    if (Test-Path $statePath) {
        try {
            $state = Get-Content -Raw -Path $statePath | ConvertFrom-Json
            $previousTime = [DateTimeOffset]::Parse("$($state.timestamp)")
            if ("$($state.fingerprint)" -eq $Fingerprint -and ($now - $previousTime).TotalSeconds -lt $WindowSeconds) {
                return $true
            }
        }
        catch {
            Write-NotifierLog -Level 'WARN' -Message "Duplicate state could not be read: $($_.Exception.Message)"
        }
    }

    $state = [ordered]@{
        fingerprint = $Fingerprint
        timestamp = $now.ToString('o')
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText($statePath, $state, (New-Object System.Text.UTF8Encoding($false)))
    return $false
}

function Send-SlackPayload {
    param(
        [Parameter(Mandatory = $true)][string]$WebhookUrl,
        [Parameter(Mandatory = $true)][string]$Payload,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $attempts = 2
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        try {
            Invoke-RestMethod `
                -Method Post `
                -Uri $WebhookUrl `
                -ContentType 'application/json; charset=utf-8' `
                -Body ([Text.Encoding]::UTF8.GetBytes($Payload)) `
                -TimeoutSec $TimeoutSeconds | Out-Null
            return
        }
        catch {
            if ($attempt -eq $attempts) {
                throw
            }
            Start-Sleep -Milliseconds 750
        }
    }
}

try {
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }

    $config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
    $webhookUrl = ''

    $protectedProperty = $config.PSObject.Properties['slackWebhookProtected']
    if ($null -ne $protectedProperty -and -not [string]::IsNullOrWhiteSpace("$($protectedProperty.Value)")) {
        $webhookUrl = ConvertFrom-ProtectedString -Value "$($protectedProperty.Value)"
    }
    else {
        $legacyProperty = $config.PSObject.Properties['slackWebhookUrl']
        if ($null -ne $legacyProperty) {
            $webhookUrl = "$($legacyProperty.Value)"
        }
    }

    if ($webhookUrl -notmatch '^https://hooks\.slack\.com/services/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$') {
        throw 'The Slack Incoming Webhook URL is missing or invalid.'
    }

    $raw = $InputJson
    if (-not $raw) {
        $raw = Read-StdinAll
    }

    $data = $null
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        try {
            $data = $raw | ConvertFrom-Json
        }
        catch {
            Write-NotifierLog -Level 'WARN' -Message "Hook payload was not valid JSON: $($_.Exception.Message)"
        }
    }

    if ($Agent -eq 'test') {
        $workingDirectory = (Get-Location).Path
        $eventName = if ($Event) { $Event } else { 'ManualTest' }
        $reason = 'Connection test completed successfully.'
    }
    else {
        $workingDirectory = "$((Get-PropertyValue -Object $data -Names @('cwd', 'working_directory', 'workingDirectory') -Default (Get-Location).Path))"
        if (-not (Test-Path $workingDirectory -PathType Container)) {
            $workingDirectory = (Get-Location).Path
        }

        $eventName = if ($Event) {
            $Event
        }
        else {
            "$((Get-PropertyValue -Object $data -Names @('hook_event_name', 'event', 'type') -Default 'AttentionRequired'))"
        }

        if ($Agent -eq 'claude') {
            $reason = Get-PropertyValue -Object $data -Names @('message', 'notification', 'reason') -Default ''
            if (-not $reason) {
                $notificationType = Get-PropertyValue -Object $data -Names @('notification_type') -Default ''
                $toolName = Get-PropertyValue -Object $data -Names @('tool_name') -Default ''
                if ($toolName) {
                    $reason = "Claude Code requests permission to use: $toolName"
                }
                elseif ($notificationType) {
                    $reason = "Claude Code requires attention: $notificationType"
                }
                else {
                    $reason = 'Claude Code is waiting for input or authorization.'
                }
            }
        }
        else {
            $reason = Get-PropertyValue -Object $data -Names @('reason', 'message', 'prompt') -Default ''
            if (-not $reason) {
                $toolName = Get-PropertyValue -Object $data -Names @('tool_name', 'tool') -Default ''
                $reason = if ($toolName) {
                    "Codex requests permission to use: $toolName"
                }
                else {
                    'Codex CLI is waiting for authorization.'
                }
            }
        }
    }

    $project = Get-ProjectName -WorkingDirectory $workingDirectory -Config $config
    $branch = Get-GitBranch -WorkingDirectory $workingDirectory
    $machine = if ($config.machineName) { "$($config.machineName)" } else { $env:COMPUTERNAME }
    $agentLabel = switch ($Agent) {
        'claude' { 'Claude Code' }
        'codex' { 'Codex CLI' }
        default { 'Installer' }
    }
    $icon = switch ("$($config.machineIcon)") {
        'house' { ':house:' }
        'office' { ':office:' }
        'laptop' { ':computer:' }
        'robot' { ':robot_face:' }
        default { ':desktop_computer:' }
    }

    $eventName = Escape-SlackText -Value $eventName
    $reason = Escape-SlackText -Value $reason
    $project = Escape-SlackText -Value $project
    $machine = Escape-SlackText -Value $machine
    $branch = Escape-SlackText -Value $branch
    $safeDirectory = Escape-SlackText -Value $workingDirectory

    $fingerprintSource = "$Agent|$machine|$project|$eventName|$reason|$safeDirectory"
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $fingerprint = [BitConverter]::ToString($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($fingerprintSource))).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }

    $duplicateWindow = 30
    if ($null -ne $config.PSObject.Properties['duplicateWindowSeconds']) {
        $duplicateWindow = [Math]::Max(0, [int]$config.duplicateWindowSeconds)
    }

    if (Test-DuplicateNotification -Fingerprint $fingerprint -WindowSeconds $duplicateWindow) {
        Write-NotifierLog -Message "Suppressed duplicate notification for $agentLabel on $project."
        exit 0
    }

    $fields = @(
        @{ type = 'mrkdwn'; text = "*Computer:*`n$icon $machine" },
        @{ type = 'mrkdwn'; text = "*Project:*`n$project" },
        @{ type = 'mrkdwn'; text = "*Agent:*`n$agentLabel" },
        @{ type = 'mrkdwn'; text = "*Event:*`n$eventName" }
    )
    if ($branch) {
        $fields += @{ type = 'mrkdwn'; text = "*Branch:*`n$branch" }
    }

    $payload = @{
        text = "$agentLabel needs attention on $machine ($project)"
        blocks = @(
            @{ type = 'header'; text = @{ type = 'plain_text'; text = "Attention required: $agentLabel"; emoji = $true } },
            @{ type = 'section'; fields = $fields },
            @{ type = 'section'; text = @{ type = 'mrkdwn'; text = "*Reason:*`n$reason" } },
            @{ type = 'context'; elements = @(@{ type = 'mrkdwn'; text = "Directory: ``$safeDirectory`` | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" }) }
        )
    } | ConvertTo-Json -Depth 8

    $requestTimeout = 10
    if ($null -ne $config.PSObject.Properties['requestTimeoutSeconds']) {
        $requestTimeout = [Math]::Max(1, [int]$config.requestTimeoutSeconds)
    }

    Send-SlackPayload -WebhookUrl $webhookUrl -Payload $payload -TimeoutSeconds $requestTimeout
    Write-NotifierLog -Message "Notification sent for $agentLabel on $project."
    exit 0
}
catch {
    Write-NotifierLog -Level 'ERROR' -Message $_.Exception.Message
    Write-Error $_.Exception.Message
    exit 1
}
