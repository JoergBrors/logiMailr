# logiMailr

logiMailr is a modular Azure Functions solution written in PowerShell that generates automated HTML reports from KQL queries and sends them by email.

In short: the project loads JSON modules from Blob Storage, runs queries against Log Analytics and Defender Advanced Hunting, renders HTML templates and either sends results via Microsoft Graph or stores them locally for testing.

## Quickstart (local)

1. Copy `logiMailr-function/local.settings.json.example` → `logiMailr-function/local.settings.json` and adjust storage, workspace and mail-mode settings.

2. Start Azurite or use a real Storage account.

3. Optional: bootstrap required PowerShell modules:

   ```powershell
   .\tools\bootstrap-modules.ps1 -InstallPath .\modules
   ```

4. Start the Functions host:

   ```powershell
   cd logiMailr-function
   func start
   ```

## Layout

- `logiMailr-function/` – Function app and shared scripts
- `modules/` – vendored PowerShell modules and example JSON modules
- `tools/` – helper scripts (bootstrap, deploy, Azurite setup)

## Security & permissions

Recommended roles/permissions for the Function App's managed identity:

- Storage: Storage Blob Data Reader
- Log Analytics: Log Analytics Reader
- Microsoft Graph: Mail.Send
- Defender XDR: AdvancedHunting.Read.All (or AdvancedQuery.Read.All)

Restart the Function App after assigning roles.

## More

See `logiMailr-function/readme.md` for function-specific notes and `logiMailr-function/tools/README-local-test.md` for local testing instructions.

