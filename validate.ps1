Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

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

function Test-JsonSyntax {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        Get-Content -Raw -Path $Path | ConvertFrom-Json | Out-Null
    }
    catch {
        throw "Invalid JSON in '$Path': $($_.Exception.Message)"
    }
}

$powerShellFiles = Get-ChildItem -Path $repoRoot -Recurse -File -Filter '*.ps1'
foreach ($file in $powerShellFiles) {
    Test-PowerShellSyntax -Path $file.FullName
    Write-Host "PASS PowerShell: $($file.FullName.Substring($repoRoot.Length + 1))"
}

foreach ($relativePath in @('config.example.json', 'examples/.ai-agent-project.json')) {
    $path = Join-Path $repoRoot $relativePath
    Test-JsonSyntax -Path $path
    Write-Host "PASS JSON: $relativePath"
}

$readmePath = Join-Path $repoRoot 'README.md'
$requiredReadmeTerms = @('Codex CLI', 'Claude Code', 'Incoming Webhook', 'Windows')
$readme = Get-Content -Raw -Path $readmePath
foreach ($term in $requiredReadmeTerms) {
    if ($readme -notlike "*$term*") {
        throw "README validation failed: missing '$term'."
    }
}

Write-Host 'Repository validation passed.' -ForegroundColor Green
