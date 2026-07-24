# AI Agent Slack Notifier

Lightweight Slack alerts for **Codex CLI** and **Claude Code** when an AI coding session requires human attention.

The project is designed for developers running several agents across multiple Windows computers and repositories. It sends actionable notifications instead of continuous progress logs.

## Supported scope

| Agent | Supported surface | Trigger |
|---|---|---|
| Claude Code | CLI on Windows | `Notification` events for permission prompts, idle prompts, and elicitation dialogs |
| Codex | Codex CLI on Windows | `PermissionRequest` user hook |

**Not guaranteed:** Codex Desktop and IDE extensions may not execute user hooks in the same way as Codex CLI. This repository does not claim support for those surfaces.

## Notification contents

Each alert can include:

- computer name and icon;
- project name;
- agent name;
- event type;
- Git branch;
- reason for the interruption;
- working directory;
- timestamp.

Duplicate alerts are suppressed for 30 seconds by default.

## Requirements

- Windows 10 or Windows 11;
- Windows PowerShell 5.1 or later;
- Codex CLI and/or Claude Code installed;
- a Slack Incoming Webhook;
- Git, optional but recommended for project and branch detection.

## Slack setup

Create a Slack app with an Incoming Webhook and connect it to the channel that will receive agent alerts. See [docs/SLACK_SETUP.md](docs/SLACK_SETUP.md).

Treat the webhook URL as a secret. The installer protects it with Windows DPAPI so it can only be decrypted by the same Windows user on the same machine.

## Installation

Clone the repository and open PowerShell in the project directory:

```powershell
git clone https://github.com/lluisfont/agent-slack-notifier.git
cd agent-slack-notifier
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
```

The installer:

1. asks for the Slack Incoming Webhook;
2. installs the shared notifier in `~/.ai-agent-slack-notifier`;
3. merges hooks without deleting unrelated agent configuration;
4. creates timestamped backups before changing existing files;
5. encrypts the webhook for the current Windows user;
6. sends a Slack connection test.

### Non-interactive installation

```powershell
.\install.ps1 `
  -Agents Both `
  -MachineName "PC-HOME" `
  -MachineIcon house `
  -SlackWebhookUrl "https://hooks.slack.com/services/..." `
  -NonInteractive
```

Supported icons: `house`, `office`, `laptop`, `robot`, and `desktop`.

### Four-computer example

Run the installer independently on each computer, using the same Slack webhook but a different machine name:

```powershell
.\install.ps1 -MachineName "PC-HOME" -MachineIcon house
.\install.ps1 -MachineName "PC-OFFICE" -MachineIcon office
.\install.ps1 -MachineName "LAPTOP-MSI" -MachineIcon laptop
.\install.ps1 -MachineName "MINIPC-AI" -MachineIcon robot
```

## Codex CLI activation

The installer enables the Codex `hooks` feature in `~/.codex/config.toml` and writes the user hook to `~/.codex/hooks.json`.

After installation:

1. restart Codex CLI;
2. run `/hooks`;
3. locate the `PermissionRequest` hook;
4. review and trust it.

A successful installer test only proves that Slack is reachable. It does **not** prove that Codex has trusted and executed the hook.

## Project naming

The notifier resolves a project name in this order:

1. nearest `.ai-agent-project.json` found in the current directory or a parent directory;
2. matching path in `projectOverrides`;
3. Git repository root name;
4. current directory name.

Add this file to a repository when its display name should differ from the folder name:

```json
{
  "project": "Innovision Studio",
  "client": "Innovision"
}
```

See [examples/.ai-agent-project.json](examples/.ai-agent-project.json).

## Installed files

```text
~/.ai-agent-slack-notifier/
├── config.local.json
├── last-notification.json
├── notifier.log
└── notify-slack.ps1

~/.claude/settings.json
~/.codex/config.toml
~/.codex/hooks.json
```

`config.local.json`, logs, local state, and backup files must not be committed.

## Validation and tests

Run repository checks without contacting Slack:

```powershell
.\validate.ps1
```

Run syntax, JSON, installed-configuration, and Slack tests:

```powershell
.\test.ps1 -Mode All
```

Run only the Slack test:

```powershell
.\test.ps1 -Mode Slack
```

The GitHub Actions workflow runs `validate.ps1` on `windows-latest` for every push and pull request.

## Reinstallation and updates

The installer is idempotent:

- notifier hook entries are replaced instead of duplicated;
- unrelated hooks are preserved;
- project overrides and runtime settings are preserved;
- timestamped backups are created before agent configuration changes.

To update:

```powershell
git pull
.\install.ps1
```

## Uninstallation

```powershell
.\uninstall.ps1
```

The uninstaller removes only hook entries belonging to this project and deletes `~/.ai-agent-slack-notifier`. It leaves the Codex hooks feature enabled because other hooks may depend on it.

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

Runtime errors are written to:

```text
~/.ai-agent-slack-notifier/notifier.log
```

## Security notes

- Never commit or publish a Slack webhook.
- Revoke the webhook in Slack if it is exposed.
- The protected webhook cannot be moved to another Windows account or computer and decrypted there.
- Hook payloads are limited and escaped before being sent to Slack.
- The notifier uses a request timeout and one retry.

## Official references

- Claude Code hooks: `https://code.claude.com/docs/en/hooks`
- Claude Code hooks guide: `https://code.claude.com/docs/en/hooks-guide`
- Codex hooks documentation: `https://developers.openai.com/codex/hooks`
- Codex configuration reference: `https://developers.openai.com/codex/config-reference`

## License

MIT License. See [LICENSE](LICENSE).
