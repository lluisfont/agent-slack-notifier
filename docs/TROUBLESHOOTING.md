# Troubleshooting

## Start with the local log

Runtime errors are written to:

```text
~/.ai-agent-slack-notifier/notifier.log
```

The hook returns a non-zero exit code when Slack delivery or configuration loading fails, but the log is the most useful diagnostic source.

## Validate the repository

From the cloned repository:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\validate.ps1
```

This checks PowerShell syntax, JSON examples, and required README content without contacting Slack.

## Test Slack independently

```powershell
.\test.ps1 -Mode Slack
```

A successful Slack test proves only that:

- the installed configuration can be decrypted by the current Windows user;
- the webhook is reachable;
- Slack accepted the payload.

It does not prove that Codex or Claude Code loaded the hook.

## The installer cannot reuse the existing webhook

The webhook is protected with Windows DPAPI. It can only be decrypted by the same Windows user on the same computer.

Run the installer again and supply the webhook when:

- the configuration was copied from another computer;
- the installation is being executed under another Windows account;
- the Windows profile or DPAPI keys changed.

```powershell
.\install.ps1 -SlackWebhookUrl "https://hooks.slack.com/services/..."
```

## Claude Code does not send notifications

1. Restart Claude Code after installation.
2. Run `/hooks` inside Claude Code.
3. Confirm that `Notification` contains notifier entries.
4. Inspect `~/.claude/settings.json` and confirm the command points to `~/.ai-agent-slack-notifier/notify-slack.ps1`.
5. Run `.\test.ps1 -Mode Slack` to separate Slack problems from hook problems.
6. Check `notifier.log` after causing a permission or input prompt.

The installer configures the documented `permission_prompt`, `idle_prompt`, and `elicitation_dialog` notification matchers. Other Claude Code events are not claimed as supported.

## Codex CLI does not send notifications

1. Confirm that you are using Codex CLI. Desktop and IDE surfaces are not guaranteed by this repository.
2. Restart Codex CLI after installation.
3. Inspect `~/.codex/config.toml` and confirm that `[features]` contains `hooks = true`.
4. Run `/hooks`.
5. Locate the `PermissionRequest` hook.
6. Review and mark it as trusted.
7. Inspect `~/.codex/hooks.json` and confirm the command points to the installed notifier.
8. Trigger an action that genuinely requires permission.
9. Check `notifier.log`.

Codex CLI will not execute a new user hook until it has been trusted.

## The Slack webhook is rejected

- Confirm the URL begins with `https://hooks.slack.com/services/` and contains all three path segments.
- Check that the webhook has not been revoked.
- Confirm that the computer can make outbound HTTPS requests.
- Verify that the Slack app still has access to the selected channel.
- Generate a new webhook if the existing one was exposed.

## Messages are duplicated

The notifier suppresses identical alerts for 30 seconds by default. Change the value in the installed configuration:

```json
{
  "duplicateWindowSeconds": 60
}
```

Set it to `0` to disable suppression.

Re-running the installer does not duplicate its hook entries; it replaces only entries that point to this notifier.

## The wrong project is displayed

Add `.ai-agent-project.json` to the repository root:

```json
{
  "project": "Innovision Studio",
  "client": "Innovision"
}
```

The notifier searches the current directory and its parents. Alternatively, define a path override in the installed configuration:

```json
{
  "projectOverrides": {
    "C:\\Projects\\studio": "Innovision Studio"
  }
}
```

Do not replace the complete configuration with this fragment. Edit only `projectOverrides`, preserving `slackWebhookProtected`.

## The Git branch is missing

Install Git and ensure `git.exe` is available in `PATH`. Branch detection is optional and does not prevent notifications.

## Restore a previous agent configuration

The installer creates timestamped backups next to modified files, including:

```text
settings.json.backup-YYYYMMDDHHMMSS
hooks.json.backup-YYYYMMDDHHMMSS
config.toml.backup-YYYYMMDDHHMMSS
config.local.json.backup-YYYYMMDDHHMMSS
```

Stop the agent, replace the current file with the required backup, and restart the agent.

## Uninstallation reports invalid JSON

The uninstaller refuses to rewrite invalid agent configuration because doing so could destroy unrelated settings.

Repair or restore the affected JSON file from a backup, then run:

```powershell
.\uninstall.ps1
```
