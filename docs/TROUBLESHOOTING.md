# Troubleshooting

## The installation test fails

Run PowerShell from the repository directory and execute:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\test.ps1
```

Check that the local configuration file exists:

```text
~/.ai-agent-slack-notifier/config.local.json
```

Confirm that the webhook URL begins with:

```text
https://hooks.slack.com/services/
```

## Claude Code does not send notifications

1. Restart Claude Code after installation.
2. Run `/hooks` inside Claude Code.
3. Confirm that a `Notification` hook is present.
4. Inspect `~/.claude/settings.json`.
5. Run `./test.ps1` to verify Slack connectivity independently of Claude Code.

## Codex does not send notifications

1. Restart Codex after installation.
2. Run `/hooks`.
3. Locate the `PermissionRequest` hook.
4. Mark it as **trusted**.
5. Inspect `~/.codex/hooks.json`.

Codex will not execute a new hook until it has been explicitly trusted.

## Slack returns an error

- Check that the webhook has not been revoked.
- Confirm that the computer can make outbound HTTPS requests.
- Generate a new webhook if the current one was exposed or disabled.
- Verify that the Slack app still has access to the selected channel.

## Messages are duplicated

Run the installer again:

```powershell
.\install.ps1
```

The installer removes existing entries created by this notifier before adding the current hook configuration.

## The wrong project is displayed

The notifier uses the Git repository root folder as the default project name. You can override project names in:

```text
~/.ai-agent-slack-notifier/config.local.json
```

Example:

```json
{
  "projectOverrides": {
    "C:\\Projects\\studio": "Innovision Studio"
  }
}
```

## The Git branch is missing

Install Git and ensure `git` is available in the system `PATH`. Branch detection is optional and does not prevent Slack notifications.

## Restore a previous agent configuration

The installer creates timestamped backups next to modified configuration files:

```text
settings.json.backup-YYYYMMDDHHMMSS
hooks.json.backup-YYYYMMDDHHMMSS
```

Stop the agent, replace the current file with the required backup, and restart the agent.
