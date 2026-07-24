param(
    [ValidateSet('Slack', 'Configuration', 'All')]
    [string]$Mode = 'All',

    [string]$WorkingDirectory = (Get-Location).Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$notifierPath = Join-Path $HOME '.ai-agent-slack-notifier/notify-slack.ps1'
$configPath = Join-Path $HOME '.ai-agent-slack-notifier/config.local.json'

function Test-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Required file not found: $Path"
    }

    try {
        Get-Content -Raw -Path $Path | ConvertFrom-Json | Out-Null
    }
    catch {
        throw "Invalid JSON in '$Path': $($_.Exception.Message)"
    }
}

function Test-PowerShellSyntax {
    param([Parameter(Mandatory = $true)][string]$Path)

    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $messages = $errors | ForEach-Object { "$($_.Extent.StartLineNumber):$($_.Extent.StartColumnNumber) $($_.Message)" }
        throw "PowerShell syntax errors in '$Path':`n$($messages -join "`n")"
    }
}

if ($Mode -in @('Configuration', 'All')) {
    foreach ($scriptPath in @(
        (Join-Path $repoRoot 'install.ps1'),
        (Join-Path $repoRoot 'uninstall.ps1'),
        (Join-Path $repoRoot 'test.ps1'),
        (Join-Path $repoRoot 'validate.ps1'),
        (Join-Path $repoRoot 'scripts/notify-slack.ps1')
    )) {
        Test-PowerShellSyntax -Path $scriptPath
    }

    Test-JsonFile -Path (Join-Path $repoRoot 'config.example.json')
    Test-JsonFile -Path (Join-Path $repoRoot 'examples/.ai-agent-project.json')

    if (Test-Path $configPath) {
        Test-JsonFile -Path $configPath
    }

    Write-Host 'Configuration and syntax checks passed.' -ForegroundColor Green
}

if ($Mode -in @('Slack', 'All')) {
    if (-not (Test-Path $notifierPath)) {
        throw 'The notifier is not installed. Run .\install.ps1 first.'
    }

    $payload = [ordered]@{
        cwd = $WorkingDirectory
        hook_event_name = 'ManualTest'
        message = 'Manual Slack connection test.'
    } | ConvertTo-Json -Compress

    & powershell.exe `
        -NoProfile `
        -NonInteractive `
        -ExecutionPolicy Bypass `
        -File $notifierPath `
        -Agent test `
        -Event ManualTest `
        -InputJson $payload

    if ($LASTEXITCODE -ne 0) {
        throw 'The Slack notification test failed. Review ~/.ai-agent-slack-notifier/notifier.log.'
    }

    Write-Host 'Slack connection test passed.' -ForegroundColor Green
}
