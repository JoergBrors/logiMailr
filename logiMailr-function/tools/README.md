## tools — overview, files and quick usage notes

This folder contains helper files and PowerShell scripts used for local development, testing and deployment of the Function App. Below is a short English description of each file in the `tools` folder.

### Files and purpose

- `Azurite-Setup.md` — Instructions for installing and starting Azurite (local Azure Storage emulator). Describes installation options (VS Code extension, npm, Docker), default ports and guidance on using it with `local.settings.json`.

- `bootstrap-modules.ps1` — Bootstraps required PowerShell modules into the local `modules/` folder. Reads `requirements.psd1`, downloads modules using `Save-Module` and supports `-Force` and wildcard versions. Usage:
  ```powershell
  .\bootstrap-modules.ps1 -Force -ModulePath modules
  ```

- `debug-AzFunctionLocaly.ps1` — Starts the Function App locally in debug mode. Sets environment variables for the PowerShell worker, can start Azurite, set a fast timer schedule (FastCron) and enable `runOnStartup`. Useful for local debugging with VS Code.

- `Deploy-AzFunction.ps1` — Deployment script for Azure (PowerShell). Creates resource group, storage account, Function App, blob containers and app settings; performs zip-deploy and assigns roles to the managed identity. Expects parameters like `ProjectPath`, `ResourceGroup`, `Location`, `FunctionAppName`.

- `diag_simple.ps1` — (empty) placeholder for simple diagnostics scripts; currently no content. Can be extended to collect local diagnostics and logs.

- `reset-test.ps1` — Helper script to reset the test environment: attempts to stop local Azurite/Node processes, deletes transient diagnostic files under `tools/` and clears process-level environment variables (only for the current process). Useful before running a fresh test.

- `set-Defenderpermissonscope.ps1` — Script that manages permissions (app roles / appRoleAssignments) via Microsoft Graph for the registered application/tenant. Supports app-only auth (AZ_CLIENT_* env vars), DryRun and report output. Uses `Microsoft.Graph` cmdlets.

- `Start-Azurite-Alt.ps1` — Starts Azurite on alternative (non-standard) ports. Parameters: `Location`, `BlobPort`, `QueuePort`, `TablePort`. For cases where default ports are occupied.

- `Start-Azurite.ps1` — Starts Azurite on default ports (10000/10001/10002). Creates the local storage folder (default `C:\azurite`) and calls `azurite --silent --location ...`.

- `start-withoutEmulator.ps1` — Runs the timer function locally without a storage emulator: loads `local.settings.json` into environment variables, sources `Shared\Utils.ps1` and executes `TimerOrchestrator\run.ps1`. Useful to test logic without Azurite.

- `Upload-module.ps1` — Helper script that uploads example or configuration files to Azurite containers (control/input/output). Contains example calls to `New-AzStorageContext`, `New-AzStorageContainer` and `Set-AzStorageBlobContent`.

- `variables-to-azure.ps1` — Helper script that transfers variables from `local.settings.json` into the Azure Function App as App Settings.

### Quickstart (local)

1. If not installed already: start Azurite (see `Azurite-Setup.md` or `Start-Azurite.ps1`).

2. Copy `local.settings.json.example` to `local.settings.json` and adjust values.

3. Install modules (if needed):
  ```powershell
  Set-Location ..\logiMailr-function
  .\tools\bootstrap-modules.ps1 -ModulePath modules
  ```

4. Optional: upload example blobs to Azurite:
  ```powershell
  .\tools\Upload-module.ps1
  ```

5. Start the Function host (normal):
  ```powershell
  func host start
  ```
  Or for debugging with helpers:
  ```powershell
  .\tools\debug-AzFunctionLocaly.ps1 -StartAzurite -FastCron -RunOnStartup
  ```

### Notes
- Many tools expect PowerShell 7.x, the Azure PowerShell modules (`Az.*`) and the Azure Functions Core Tools (`func`).
- `set-Defenderpermissonscope.ps1` requires `Microsoft.Graph` modules and possibly app-only credentials.
- `diag_simple.ps1` is currently empty and can be populated if needed.

If you want, I can expand the README with parameter examples, common error scenarios, or inline comments for specific scripts.

Note: if you encounter missing modules, run `tools\bootstrap-modules.ps1 -Verbose` and verify `requirements.psd1`.
