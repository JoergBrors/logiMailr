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
    # Preferred: Microsoft Graph SDK for PowerShell for Graph & Defender operations
    'Microsoft.Graph.Authentication' = '2.*'
    # Keep Az.Storage for Storage cmdlets used in deployment and local emulation
    'Az.Storage'  = '5.*'
}
```

## Fehlerbehebung

- "No module listed in requirements": `requirements.psd1` prüfen und Module in `ModulesToLoad` eintragen.
- Beim Auth‑Fehler: Managed Identity‑Rollen prüfen und Function neu starten.

Weitere Details: `logiMailr-function/tools/README-local-test.md`.

## Ordnerstruktur / kurze Beschreibung der Dateien

Hier eine kurze Übersicht über die wichtigsten Ordner und Dateien im Ordner `logiMailr-function` und deren Zweck:

- `.vscode/` — VS Code Arbeitsbereichs- und Task-Settings (z.B. Start-Tasks, Launch-Konfigurationen). Enthält projektspezifische Entwickler-Tasks.
- `host.json` — Azure Functions Host-Konfiguration (Binding- und Host-bezogene Einstellungen).
- `local.settings.json` / `local.settings.json.example` — Lokale Laufzeitkonfiguration (App-Einstellungen, Connection-Strings). `local.settings.json.example` als Vorlage kopieren und anpassen für lokale Entwicklung.
- `modules/` — Vendored PowerShell-Module (lokal gespeicherte Module, die `tools\bootstrap-modules.ps1` aus `requirements.psd1` lädt). Wird genutzt, um Abhängigkeiten offline/gebündelt bereitzustellen.
- `out-mail/` — Ausgabeordner für lokal gespeicherte E-Mail-HTML-Dateien (wenn `LOGIMAILR_SEND_MODE=File` gesetzt ist). Nützlich zum Testen der generierten Reports ohne echten Mailversand.
- `package-lock.json` — Lockfile (falls Node/Tools verwendet werden); nicht zentral für die PowerShell-Function, aber kann Tasks/Tools betreffen.
- `profile.ps1` — Optionales PowerShell-Profil/Helper für lokale Developer-Workflows (falls vorhanden).
- `readme.md` — Diese Dokumentation (kurze Anleitung & Hinweise zum lokalen Betrieb).
- `requirements.psd1` — Liste der benötigten PowerShell-Module (Name => Version), genutzt von `tools\bootstrap-modules.ps1` zum Vendoring.
- `Shared/` — Gemeinsame Hilfsfunktionen und Scripts
    - `Shared\Utils.ps1` enthält zentrale Helper (Logging, Token-Akquise, Storage-Context, KQL/Defender-Aufrufe, HTML-Renderer und Mail-Sende-Wrapper). Diese Funktionen werden von den Function-Skripten wiederverwendet.
- `TimerOrchestrator/` — Die eigentliche Timer-Function
    - `TimerOrchestrator\function.json` definiert das Timer-Binding (Schedule via `%TimerOrchestrator_Schedule%`, `runOnStartup`).
    - `TimerOrchestrator\run.ps1` ist das Haupt-Skript der Function: lädt Control-Module aus Blob Storage, führt die konfigurierten Quellen (LogAnalytics, Defender AH) aus, rendert HTML-Reports und versendet oder speichert diese.
- `tools/` — Hilfs-Skripte für Entwicklung & Deployment (z. B. `Start-Azurite.ps1`, `bootstrap-modules.ps1`, `Deploy-AzFunction.ps1`, `debug-AzFunctionLocaly.ps1`). Sie enthalten Setup-, Debug- und Deploy-Hilfen; siehe `tools/README.md` für Details.

Diese Liste deckt die Dateien ab, die für Entwicklung, lokales Testen und Deployment am relevantesten sind. Wenn Du möchtest, kann ich die Beschreibungen erweitern (z. B. typische Parameter für `Deploy-AzFunction.ps1`, Beispiele für `local.settings.json`, oder eine kurze Bedienungsanleitung für `tools/debug-AzFunctionLocaly.ps1`).
