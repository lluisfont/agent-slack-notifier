# AI Agent Slack Notifier

Lightweight Slack notifications for **Codex** and **Claude Code** when human attention is required.

Designed for developers running multiple AI coding agents across several computers and projects. The notifier avoids noisy progress logs and only sends actionable alerts such as permission requests, blocked executions, or requests for user input.

## What it notifies

- Claude Code requests permission.
- Claude Code is waiting for user input.
- A background Claude Code agent needs attention.
- Codex displays a permission request.
- Manual installation and connection tests.

It does not send every command or continuous progress updates.

## Message contents

Each Slack alert can include:

- computer name;
- detected project;
- agent name;
- event type;
- Git branch;
- reason;
- working directory;
- timestamp.

## Requirements

- Windows 10 or Windows 11.
- PowerShell 5.1 or later.
- Codex CLI and/or Claude Code already installed.
- A Slack Incoming Webhook.
- Git is optional, but enables project and branch detection.

## Quick installation

Clone the repository and open PowerShell in the project directory:

```powershell
git clone https://github.com/lluisfont/agent-slack-notifier.git
cd agent-slack-notifier
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
```

The installer asks for the Slack webhook URL and sends a test notification.

### Non-interactive example

```powershell
.\install.ps1 `
  -Agents Both `
  -MachineName "PC-HOME" `
  -MachineIcon house `
  -SlackWebhookUrl "https://hooks.slack.com/services/..."
```

Supported icons: `house`, `office`, `laptop`, `robot`, and `desktop`.

## Installation on several computers

Use the same repository and Slack webhook on every machine. Change only the machine name and icon:

```powershell
.\install.ps1 -MachineName "PC-HOME" -MachineIcon house
.\install.ps1 -MachineName "PC-OFFICE" -MachineIcon office
.\install.ps1 -MachineName "LAPTOP-MSI" -MachineIcon laptop
.\install.ps1 -MachineName "MINIPC-AI" -MachineIcon robot
```

All alerts can be sent to a single Slack channel such as `#ai-agents-alerts`.

## Required Codex step

Codex requires new hooks to be reviewed before execution:

1. Restart Codex after installation.
2. Run `/hooks`.
3. Locate the `PermissionRequest` hook.
4. Mark it as **trusted**.

Codex will ignore the hook until it is trusted.

## Installed files

```text
~/.ai-agent-slack-notifier/
├── config.local.json
└── notify-slack.ps1

~/.claude/settings.json
~/.codex/hooks.json
```

The installer creates timestamped backups before modifying existing agent configuration files.

## Manual test

```powershell
.\test.ps1
```

## Uninstallation

```powershell
.\uninstall.ps1
```

The uninstaller removes only notifier-related hook entries and the local notifier directory.

## Security

The Slack webhook URL is stored locally in:

```text
~/.ai-agent-slack-notifier/config.local.json
```

Do not commit this file, paste the webhook into issues, or include it in public screenshots.

## Documentation

- [Slack webhook setup](docs/SLACK_SETUP.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## Project structure

```text
agent-slack-notifier/
├── README.md
├── config.example.json
├── install.ps1
├── test.ps1
├── uninstall.ps1
├── docs/
│   ├── SLACK_SETUP.md
│   └── TROUBLESHOOTING.md
├── examples/
│   └── .ai-agent-project.json
└── scripts/
    └── notify-slack.ps1
```

## Official references

- Claude Code hooks: `https://code.claude.com/docs/en/hooks-guide`
- Codex hooks: `https://learn.chatgpt.com/docs/hooks`
- Codex configuration reference: `https://learn.chatgpt.com/docs/config-file/config-reference`

## License

MIT License.