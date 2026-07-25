# Installation Guide

This guide installs AI Agent Slack Notifier on Windows for **Claude Code**, **Codex CLI**, or both.

The recommended rollout is:

1. configure Slack once;
2. install and validate on one computer;
3. trigger a real alert from each agent;
4. repeat the installation on the remaining computers.

## 1. Before you begin

Confirm the following on the computer where you will install the notifier:

- Windows 10 or Windows 11;
- Windows PowerShell 5.1 or later;
- Git installed and available in `PATH`;
- Claude Code, Codex CLI, or both already installed;
- access to a Slack Incoming Webhook.

Check PowerShell and Git:

```powershell
$PSVersionTable.PSVersion
git --version
```

The notifier does not require administrator privileges and installs under the current Windows user profile.

## 2. Create the Slack destination

Use a dedicated Slack channel such as:

```text
#ai-agents-alerts
```

Create or select a Slack app, enable **Incoming Webhooks**, and add a webhook to that channel.

The webhook must have this form:

```text
https://hooks.slack.com/services/...
```

Keep it private. Anyone who obtains the URL can post messages to the configured channel.

Full Slack instructions: [SLACK_SETUP.md](SLACK_SETUP.md)

## 3. Clone the repository

Open Windows PowerShell and run:

```powershell
cd C:\Tools
git clone https://github.com/lluisfont/agent-slack-notifier.git
cd agent-slack-notifier
```

You can use a different folder. The cloned repository is only needed for installation, updates, validation and uninstallation. The runtime notifier is copied to the current user profile.

## 4. Allow the local scripts for this PowerShell session

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

This change only affects the current PowerShell process and is discarded when the window is closed.

## 5. Validate the downloaded repository

Run static validation before installing:

```powershell
.\validate.ps1
```

Expected final output:

```text
Repository validation passed.
```

This checks PowerShell syntax, JSON files and required README content. It does not contact Slack or modify agent configuration.

## 6. Choose the installation mode

### Install Claude Code and Codex CLI

```powershell
.\install.ps1
```

The default is `Both`. The installer asks for the Slack webhook and uses the Windows computer name in notifications.

### Install only Claude Code

```powershell
.\install.ps1 -Agents Claude
```

### Install only Codex CLI

```powershell
.\install.ps1 -Agents Codex
```

### Set a friendly machine name and icon

```powershell
.\install.ps1 `
  -Agents Both `
  -MachineName "PC-OFFICE" `
  -MachineIcon office
```

Allowed icons:

```text
house
 office
 laptop
 robot
 desktop
```

### Non-interactive installation

```powershell
.\install.ps1 `
  -Agents Both `
  -MachineName "PC-OFFICE" `
  -MachineIcon office `
  -SlackWebhookUrl "https://hooks.slack.com/services/..." `
  -NonInteractive
```

Do not save the command with a real webhook in a script, shell history export, ticket, issue or documentation.

### Skip the initial Slack test

```powershell
.\install.ps1 -SkipTest
```

Use this only when Slack is temporarily unavailable. Run the test manually later.

## 7. What the installer changes

The shared runtime is installed here:

```text
%USERPROFILE%\.ai-agent-slack-notifier\
```

Files include:

```text
config.local.json
notify-slack.ps1
notifier.log
last-notification.json
```

Depending on the selected agents, the installer also updates:

```text
%USERPROFILE%\.claude\settings.json
%USERPROFILE%\.codex\config.toml
%USERPROFILE%\.codex\hooks.json
```

Before changing an existing configuration file, the installer creates a timestamped backup beside it.

The installer preserves unrelated hooks and replaces only entries belonging to this notifier.

## 8. Claude Code activation and verification

Restart Claude Code after installation.

The installer adds `Notification` hooks for:

- `permission_prompt`;
- `idle_prompt`;
- `elicitation_dialog`.

First verify Slack connectivity:

```powershell
.\test.ps1 -Mode Slack
```

Then run Claude Code in a test repository and cause it to request permission or user input. Confirm that Slack receives a message containing the correct:

- computer;
- project;
- agent;
- event;
- working directory;
- Git branch, when available.

The manual Slack test alone does not prove that Claude Code has executed the hook.

## 9. Codex CLI activation and verification

The installer:

- enables `hooks = true` under `[features]` in `%USERPROFILE%\.codex\config.toml`;
- adds a `PermissionRequest` entry to `%USERPROFILE%\.codex\hooks.json`.

Codex CLI requires manual review and trust.

After installation:

1. close and restart Codex CLI;
2. run `/hooks`;
3. locate the `PermissionRequest` hook;
4. inspect the command;
5. mark the hook as trusted.

Then cause Codex CLI to request permission and confirm that Slack receives the alert.

A successful installation message or `test.ps1` result proves only that Slack is reachable. It does not prove that Codex has trusted the hook.

This repository does not guarantee support for Codex Desktop or Codex IDE extensions.

## 10. Run the complete validation

After installation:

```powershell
.\test.ps1 -Mode All
```

Available modes:

```powershell
.\test.ps1 -Mode Configuration
.\test.ps1 -Mode Slack
.\test.ps1 -Mode All
```

`Configuration` validates repository scripts, JSON and installed configuration.

`Slack` sends a manual notification using the installed runtime.

`All` performs both.

## 11. Configure the project display name

By default, the notifier uses the Git repository folder as the project name.

To display a different name, copy the example file into the root of a project:

```powershell
Copy-Item .\examples\.ai-agent-project.json C:\Projects\your-project\.ai-agent-project.json
```

Edit it:

```json
{
  "project": "Innovision Studio",
  "client": "Innovision"
}
```

The notifier searches the current working directory and its parent directories for the nearest `.ai-agent-project.json`.

Project names can also be overridden globally in:

```text
%USERPROFILE%\.ai-agent-slack-notifier\config.local.json
```

Example:

```json
{
  "projectOverrides": {
    "C:\\Projects\\studio": "Innovision Studio"
  }
}
```

Do not replace the full local configuration with this fragment. Merge only the `projectOverrides` property into the existing file.

## 12. Recommended four-computer deployment

Install and test one computer first. After both real agent alerts work, repeat the process on the other machines.

Example naming:

```powershell
.\install.ps1 -MachineName "PC-HOME" -MachineIcon house
.\install.ps1 -MachineName "PC-OFFICE" -MachineIcon office
.\install.ps1 -MachineName "LAPTOP-MSI" -MachineIcon laptop
.\install.ps1 -MachineName "MINIPC-AI" -MachineIcon robot
```

Use the same Slack webhook on all four computers. Each machine stores its own encrypted copy under its Windows user profile.

Do not copy `config.local.json` between computers. Windows DPAPI protection prevents another machine or Windows account from decrypting the webhook.

## 13. Updating an existing installation

Open PowerShell in the cloned repository:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
git pull
.\validate.ps1
.\install.ps1
.\test.ps1 -Mode All
```

You do not need to provide the webhook again when updating under the same Windows user. The installer reads and decrypts the existing protected value.

Reinstallation preserves runtime settings and project overrides.

Restart the affected agents after updating.

## 14. Moving the installation to another Windows account or computer

The protected webhook cannot be decrypted elsewhere.

On the new account or computer:

1. clone the repository;
2. run `validate.ps1`;
3. run `install.ps1`;
4. provide the Slack webhook again;
5. repeat the agent-specific activation tests.

## 15. Uninstalling

From the repository folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\uninstall.ps1
```

The uninstaller:

- removes notifier hook groups from Claude Code and Codex CLI;
- preserves unrelated hooks;
- removes `%USERPROFILE%\.ai-agent-slack-notifier`;
- leaves the Codex `hooks` feature enabled because other hooks may use it.

Restart Claude Code and Codex CLI after uninstalling.

## 16. Troubleshooting checklist

Run:

```powershell
.\validate.ps1
.\test.ps1 -Mode All
Get-Content "$HOME\.ai-agent-slack-notifier\notifier.log" -Tail 50
```

Also check:

```text
%USERPROFILE%\.claude\settings.json
%USERPROFILE%\.codex\config.toml
%USERPROFILE%\.codex\hooks.json
```

For Codex CLI, confirm the hook is trusted through `/hooks`.

Detailed troubleshooting: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## 17. Security checklist

- Keep the Slack webhook secret.
- Never commit `config.local.json`.
- Revoke the webhook immediately if exposed.
- Do not copy the encrypted configuration between computers.
- Restrict the Slack channel to people who supervise the agents.
- Review hook commands before trusting them.
- Keep the repository updated and run `validate.ps1` after updates.
