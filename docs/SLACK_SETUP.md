# Slack Incoming Webhook setup

## 1. Create or select a Slack app

Open the Slack API application management page and create a new app for your workspace, or select an existing internal app.

## 2. Enable Incoming Webhooks

In the app settings:

1. Open **Incoming Webhooks**.
2. Enable **Activate Incoming Webhooks**.
3. Select **Add New Webhook to Workspace**.
4. Choose the destination channel, for example `#ai-agents-alerts`.
5. Authorize the app.

## 3. Copy the webhook URL

The URL must begin with:

```text
https://hooks.slack.com/services/
```

Treat this URL as a secret. Anyone with the URL can post messages to the configured Slack channel.

## 4. Install the notifier

Run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
```

Paste the webhook URL when prompted.

For unattended installation:

```powershell
.\install.ps1 `
  -Agents Both `
  -MachineName "PC-OFFICE" `
  -MachineIcon office `
  -SlackWebhookUrl "https://hooks.slack.com/services/..."
```

## Multiple computers

The same webhook can be used on all computers. Each installation stores a different `machineName`, allowing Slack messages to identify which machine needs attention.

## Security recommendations

- Never commit the webhook URL.
- Never paste it into GitHub issues or pull requests.
- Revoke and regenerate it immediately if exposed.
- Restrict the Slack channel to the people who operate the AI agents.
