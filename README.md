# AI Agent Slack Notifier

Receive a Slack alert when **Codex CLI** or **Claude Code** stops and needs human attention.

AI Agent Slack Notifier is a lightweight, self-hosted notification layer for developers running several AI coding sessions across multiple Windows computers and repositories. It does not stream logs or send continuous progress updates. It only reports interruptions that require a person to return to the agent.

Typical alerts include:

- permission or approval required;
- user input required;
- an elicitation dialog is waiting;
- the agent has become idle while waiting for interaction.

## Why this project exists

Running one AI coding agent is easy to supervise. Running several agents on four computers is not.

Without notifications, you have to repeatedly check every terminal to discover that an agent has been waiting for approval for twenty minutes. This project gives all machines a shared Slack notification channel while preserving enough context to know exactly where attention is needed.

```text
Codex CLI / Claude Code
          |
          | native lifecycle hook
          v
AI Agent Slack Notifier
          |
          | Slack Incoming Webhook
          v
#ai-agents-alerts
```

## Example notification

```text
Attention required: Claude Code

Computer: PC-OFFICE
Project: Innovision Studio
Agent: Claude Code
Event: permission_prompt
Branch: feature/contact-export
Reason: Claude Code is waiting for permission or user input.
Directory: C:\Projects\innovision-studio
```

## Main features

- One Slack channel for multiple computers and projects.
- Native hook integration with Codex CLI and Claude Code.
- Automatic computer, project, directory, Git branch, event and reason detection.
- Optional `.ai-agent-project.json` file for friendly project names.
- Duplicate-alert suppression.
- Slack retry and request timeout handling.
- Local error log for diagnostics.
- Idempotent installer that preserves unrelated hooks and settings.
- Timestamped backups before agent configuration files are changed.
- Slack webhook protected with Windows DPAPI for the current user.
- Validation scripts and a Windows GitHub Actions workflow.
- No server, database, SaaS backend or background daemon.

## Supported scope

| Agent | Supported surface | Hook used | Status |
|---|---|---|---|
| Claude Code | CLI on Windows | `Notification` | Supported |
| Codex | Codex CLI on Windows | `PermissionRequest` | Supported |
| Codex Desktop | Windows desktop application | Not guaranteed | Unsupported |
| Codex IDE extensions | VS Code and other IDE surfaces | Not guaranteed | Unsupported |

Claude Code notifications are installed for `permission_prompt`, `idle_prompt`, and `elicitation_dialog` notification types.

Codex CLI requires a manual trust step after installation. A successful Slack test does not prove that Codex has trusted and executed the hook.

## Requirements

- Windows 10 or Windows 11.
- Windows PowerShell 5.1 or later.
- Git for cloning the repository and detecting branches.
- Codex CLI, Claude Code, or both already installed.
- A Slack workspace where you can install or configure an app.
- A Slack Incoming Webhook connected to the destination channel.

## Quick start

### 1. Create the Slack webhook

Create or select a Slack app, enable **Incoming Webhooks**, and add a webhook to a channel such as `#ai-agents-alerts`.

Detailed instructions: [docs/SLACK_SETUP.md](docs/SLACK_SETUP.md)

### 2. Clone and validate the repository

```powershell
git clone https://github.com/lluisfont/agent-slack-notifier.git
cd agent-slack-notifier
Set-ExecutionPolicy -Scope Process Bypass
.\validate.ps1
```

### 3. Install the notifier

```powershell
.\install.ps1
```

The installer asks for the Slack webhook, installs the shared notifier, configures the selected agents, protects the webhook and sends a connection test.

### 4. Activate the Codex CLI hook

When Codex support is installed:

1. restart Codex CLI;
2. run `/hooks`;
3. locate the `PermissionRequest` hook;
4. review it and mark it as trusted.

### 5. Run the complete test suite

```powershell
.\test.ps1 -Mode All
```

For the complete installation procedure, agent-specific checks and multi-computer deployment, read [docs/INSTALLATION.md](docs/INSTALLATION.md).

## Installing on four computers

Use the same Slack webhook on every computer and assign a different machine name and icon to each installation.

```powershell
.\install.ps1 -MachineName "PC-HOME" -MachineIcon house
.\install.ps1 -MachineName "PC-OFFICE" -MachineIcon office
.\install.ps1 -MachineName "LAPTOP-MSI" -MachineIcon laptop
.\install.ps1 -MachineName "MINIPC-AI" -MachineIcon robot
```

Supported icons:

- `house`
- `office`
- `laptop`
- `robot`
- `desktop`

## Installation options

```powershell
.\install.ps1 `
  -Agents Both `
  -MachineName "PC-OFFICE" `
  -MachineIcon office `
  -SlackWebhookUrl "https://hooks.slack.com/services/..." `
  -NonInteractive
```

| Parameter | Values | Default | Purpose |
|---|---|---|---|
| `Agents` | `Both`, `Codex`, `Claude` | `Both` | Selects which agent integrations are installed. |
| `MachineName` | Any string | Windows computer name | Name displayed in Slack. |
| `MachineIcon` | `house`, `office`, `laptop`, `robot`, `desktop` | `desktop` | Emoji associated with the computer. |
| `SlackWebhookUrl` | Slack webhook URL | Interactive prompt | Webhook used to send notifications. |
| `NonInteractive` | Switch | Disabled | Prevents interactive prompts. |
| `SkipTest` | Switch | Disabled | Skips the installation Slack test. |

When `NonInteractive` is used for a first installation, `SlackWebhookUrl` must also be supplied.

## How project names are resolved

The notifier resolves the displayed project name in this order:

1. nearest `.ai-agent-project.json` file in the current directory or a parent directory;
2. matching path in `projectOverrides` inside the local configuration;
3. Git repository root folder;
4. current directory name.

Example repository file:

```json
{
  "project": "Innovision Studio",
  "client": "Innovision"
}
```

A template is available at [examples/.ai-agent-project.json](examples/.ai-agent-project.json).

## Files installed on each computer

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

The installer changes only the agent configurations selected through `-Agents`. Existing notifier entries are replaced rather than duplicated, and unrelated hooks are preserved.

## Configuration and runtime behavior

The local configuration contains:

- the protected Slack webhook;
- machine name and icon;
- duplicate-notification window;
- Slack request timeout;
- optional project path overrides.

The default duplicate window is 30 seconds. Runtime errors are written to:

```text
~/.ai-agent-slack-notifier/notifier.log
```

The webhook is protected with Windows DPAPI. It can only be decrypted by the same Windows user on the same computer. Copying `config.local.json` to another computer will not transfer a usable webhook.

## Validation and testing

Validate repository syntax without contacting Slack:

```powershell
.\validate.ps1
```

Validate syntax, JSON and installed configuration, then send a Slack test:

```powershell
.\test.ps1 -Mode All
```

Test only the installed configuration:

```powershell
.\test.ps1 -Mode Configuration
```

Test only Slack connectivity:

```powershell
.\test.ps1 -Mode Slack
```

A Slack test verifies that the local notifier can reach the webhook. It does not verify the complete agent-to-hook path. After installation, trigger one real permission request in each installed agent before deploying to all computers.

## Updating

The installer is idempotent, so updates use the same installation command:

```powershell
git pull
Set-ExecutionPolicy -Scope Process Bypass
.\validate.ps1
.\install.ps1
```

During reinstallation:

- notifier hook entries are replaced instead of duplicated;
- unrelated hooks remain unchanged;
- project overrides and runtime settings are retained;
- timestamped backups are created before configuration changes.

## Uninstalling

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\uninstall.ps1
```

The uninstaller removes only hook entries created by AI Agent Slack Notifier and deletes the local notifier directory. It intentionally leaves the Codex `hooks` feature enabled because other Codex hooks may depend on it.

## Security model

- Never commit or publish the Slack webhook.
- Revoke the webhook immediately if it is exposed.
- The webhook is encrypted for the current Windows user with DPAPI.
- Hook payloads are escaped and truncated before they are sent to Slack.
- The notifier does not upload source code, repository files or terminal logs.
- Only context supplied by the hook and detected project metadata are included.
- Slack delivery uses an explicit timeout and one retry.

## Troubleshooting

Start with:

```powershell
.\validate.ps1
.\test.ps1 -Mode All
Get-Content "$HOME\.ai-agent-slack-notifier\notifier.log" -Tail 50
```

Then consult [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Repository structure

```text
agent-slack-notifier/
├── .github/workflows/validate.yml
├── docs/
│   ├── INSTALLATION.md
│   ├── SLACK_SETUP.md
│   └── TROUBLESHOOTING.md
├── examples/
│   └── .ai-agent-project.json
├── scripts/
│   └── notify-slack.ps1
├── config.example.json
├── install.ps1
├── test.ps1
├── uninstall.ps1
├── validate.ps1
├── LICENSE
└── README.md
```

## Current limitations

- Windows-only installer and runtime.
- Codex support is limited to Codex CLI.
- Codex hooks must be reviewed and trusted manually.
- Slack Incoming Webhooks post to the channel selected when the webhook is created.
- The project does not provide remote control of the agents; it only sends alerts.

## Official references

- Claude Code hooks: `https://code.claude.com/docs/en/hooks`
- Claude Code hooks guide: `https://code.claude.com/docs/en/hooks-guide`
- Codex hooks: `https://developers.openai.com/codex/hooks`
- Codex configuration reference: `https://developers.openai.com/codex/config-reference`
- Slack Incoming Webhooks: `https://api.slack.com/messaging/webhooks`

## License

MIT License. See [LICENSE](LICENSE).
