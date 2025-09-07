# logiMailr Function

The PowerShell Azure Function app for logiMailr loads modules and templates from Blob Storage, executes KQL queries and renders email reports.

## Quickstart (local)

1. Copy `local.settings.json.example` → `local.settings.json` and fill in storage and workspace values.

2. Start Azurite or use a real Storage account.

3. Bootstrap modules (if required):

```powershell
.\tools\bootstrap-modules.ps1 -InstallPath .\modules
```

4. Start the Functions host:

```powershell
cd logiMailr-function
func start
```

## Configuration

- `local.settings.json` contains connection values and mode (`LOGIMAILR_SEND_MODE` = `File` | `Graph`).
- `requirements.psd1` lists modules used for vendoring.

## Modules & vendoring

This repository contains a `modules/` directory with vendored modules. `tools/bootstrap-modules.ps1` reads `requirements.psd1` and downloads missing modules locally.

Example `requirements.psd1`:

```powershell
@{
    # Preferred: Microsoft Graph SDK for PowerShell for Graph & Defender operations
    'Microsoft.Graph.Authentication' = '2.*'
    # Keep Az.Storage for Storage cmdlets used in deployment and local emulation
    'Az.Storage'  = '5.*'
}
```

## Troubleshooting

- "No module listed in requirements": check `requirements.psd1` and add modules to `ModulesToLoad`.
- Authentication errors: check managed identity roles and restart the Function.

See `logiMailr-function/tools/README-local-test.md` for more details.

## Folder structure / short description of files

A short overview of key folders and files in `logiMailr-function` and their purpose:

- `.vscode/` — VS Code workspace and task settings (e.g. start tasks, launch configurations). Contains project-specific developer tasks.
- `host.json` — Azure Functions host configuration (binding and host-level settings).
- `local.settings.json` / `local.settings.json.example` — Local runtime configuration (app settings, connection strings). Copy `local.settings.json.example` and adapt it for local development.
- `modules/` — Vendored PowerShell modules (locally stored modules that `tools\bootstrap-modules.ps1` downloads based on `requirements.psd1`). Used to provide dependencies offline/bundled.
- `out-mail/` — Output folder for locally saved email HTML files (when `LOGIMAILR_SEND_MODE=File`). Useful for testing generated reports without sending real emails.
- `package-lock.json` — Lockfile (if Node/tools are used); not central to the PowerShell function but may affect tasks/tools.
- `profile.ps1` — Optional PowerShell profile/helper for local developer workflows (if present).
- `readme.md` — This documentation (quick guide & notes for local use).
- `requirements.psd1` — List of required PowerShell modules (Name => Version), used by `tools\bootstrap-modules.ps1` for vendoring.
- `Shared/` — Shared helper functions and scripts
  - `Shared\Utils.ps1` contains core helpers (logging, token acquisition, storage context, KQL/Defender calls, HTML renderer and mail-sending wrapper). These functions are reused by the function scripts.
- `TimerOrchestrator/` — The timer-triggered function
  - `TimerOrchestrator\function.json` defines the timer binding (schedule via `%TimerOrchestrator_Schedule%`, `runOnStartup`).
  - `TimerOrchestrator\run.ps1` is the main function script: it loads control modules from Blob Storage, runs configured sources (Log Analytics, Defender AH), renders HTML reports and sends or stores them.
- `tools/` — Helper scripts for development & deployment (e.g. `Start-Azurite.ps1`, `bootstrap-modules.ps1`, `Deploy-AzFunction.ps1`, `debug-AzFunctionLocaly.ps1`). See `tools/README.md` for details.

This list covers files most relevant for development, local testing and deployment. If you like, I can expand the descriptions (for example parameter examples for `Deploy-AzFunction.ps1`, sample `local.settings.json` content, or a short guide for using `tools/debug-AzFunctionLocaly.ps1`).
