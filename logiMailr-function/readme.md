# logiMailr Function

Die PowerShell Azure Function App für logiMailr lädt Module und Templates aus Blob Storage, führt KQL‑Abfragen aus und rendert E‑Mail‑Reports.

## Schnellstart (lokal)

1. Kopiere `local.settings.json.example` → `local.settings.json` und trage Storage‑ und Workspace‑Werte ein.

1. Starte Azurite oder verwende ein echtes Storage Konto.

1. Module bootstrap (falls erforderlich):

```powershell
.\tools\bootstrap-modules.ps1 -InstallPath .\modules
```

1. Starte den Functions Host:

```powershell
cd logiMailr-function
func start
```

## Konfiguration

- `local.settings.json` enthält Verbindungsdaten und Modus (`LOGIMAILR_SEND_MODE` = `File` | `Graph`).
- `requirements.psd1` listet Module für das Vendoring.

## Module & Vendoring

Das Repo besitzt ein `modules/`‑Verzeichnis mit vendored Modulen. `tools/bootstrap-modules.ps1` liest `requirements.psd1` und lädt fehlende Module lokal herunter.

Beispiel `requirements.psd1`:

```powershell
@{
  RootModule = @()
  ModulesToLoad = @('Az.Accounts', 'Microsoft.Graph.Authentication')
}
```

## Fehlerbehebung

- "No module listed in requirements": `requirements.psd1` prüfen und Module in `ModulesToLoad` eintragen.
- Beim Auth‑Fehler: Managed Identity‑Rollen prüfen und Function neu starten.

Weitere Details: `logiMailr-function/tools/README-local-test.md`.
