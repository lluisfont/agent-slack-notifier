$script = Join-Path $HOME '.ai-agent-slack-notifier/notify-slack.ps1'
if (-not (Test-Path $script)) { throw 'The notifier is not installed.' }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Agent test -Event ManualTest
