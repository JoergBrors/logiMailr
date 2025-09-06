## tools — Übersicht, Dateien und kurze Nutzungshinweise

Dieser Ordner enthält Hilfsdateien und PowerShell- sowie Dokumentationsskripte, die beim lokalen Entwickeln, Testen und Deployen der Function App unterstützt werden. Nachfolgend eine kurze, deutsche Beschreibung jeder Datei im Ordner `tools`.

### Dateien und Zweck

- `Azurite-Setup.md` — Anleitung zum Installieren und Starten von Azurite (lokaler Azure Storage Emulator). Beschreibt Installationsoptionen (VS Code Extension, npm, Docker), Standard-Ports und Hinweise zur Verwendung mit `local.settings.json`.

- `bootstrap-modules.ps1` — Bootstrapt benötigte PowerShell-Module in den lokalen `modules/`-Ordner. Liest `requirements.psd1`, lädt Module per `Save-Module` und unterstützt `-Force` sowie Wildcard-Versionen. Nutzung:
  ```powershell
  .\bootstrap-modules.ps1 -Force -ModulePath modules
  ```

- `debug-AzFunctionLocaly.ps1` — Startet die Function App lokal im Debug-Modus. Stellt Umgebungsvariablen für den PowerShell-Worker, kann Azurite starten, Timer-Schedule auf schnell (FastCron) setzen und `runOnStartup` aktivieren. Nützlich für lokales Debugging mit VS Code.

- `Deploy-AzFunction.ps1` — Deployment-Skript für Azure (PowerShell). Erstellt Resource Group, Storage Account, Function App, Blob-Container und App-Settings; führt Zip-Deploy durch und weist Managed Identity passende Rollen zu. Erwartet Parameter wie `ProjectPath`, `ResourceGroup`, `Location`, `FunctionAppName`.

- `diag_simple.ps1` — (leer) Platzhalter für einfache Diagnose-Skripte; derzeit keine Inhalte. Kann bei Bedarf erweitert werden, um lokale Diagnose und Logging aufzunehmen.

- `reset-test.ps1` — Hilfsskript zum Zurücksetzen der Testumgebung: versucht, lokale Azurite/Node-Prozesse zu beenden, löscht temporäre Diagnose-Dateien unter `tools/` und entfernt prozessweite Umgebungsvariablen (nur für den aktuellen Prozess). Gut vor einem neuen Testlauf.

- `set-Defenderpermissonscope.ps1` — Skript, das Berechtigungen (App-Rollen / AppRoleAssignments) über Microsoft Graph für die registrierte Anwendung/Mandanten verwalten kann. Unterstützt App-Only-Auth (AZ_CLIENT_* Umgebungsvariablen), DryRun und Report-Ausgabe. Nutzt `Microsoft.Graph`-Cmdlets.

- `Start-Azurite-Alt.ps1` — Startet Azurite mit alternativen (nicht-standard) Ports. Parameter: `Location`, `BlobPort`, `QueuePort`, `TablePort`. Für Fälle, in denen Standard-Ports belegt sind.

- `Start-Azurite.ps1` — Startet Azurite mit Standard-Ports (10000/10001/10002). Legt lokalen Speicherort an (Standard `C:\azurite`) und startet `azurite --silent --location ...`.

- `start-withoutEmulator.ps1` — Startet die Timer-Function lokal ohne Storage-Emulator; lädt `local.settings.json` als Umgebungsvariablen, lädt `Shared\Utils.ps1` und führt `TimerOrchestrator\run.ps1` lokal aus. Nützlich, um Funktionalität ohne Azurite zu testen.

- `Upload-module.ps1` — Hilfsskript, das Beispiel- oder Konfigurationsdateien in die Azurite-Container lädt (control/input/output). Enthält Beispiel-Aufrufe für `New-AzStorageContext`, `New-AzStorageContainer` und `Set-AzStorageBlobContent`.

- `variables-to-azure.ps1` — Hilfsskript, das die Variablen von der local.settings.json in die Azure Funktion überträgt.
 ```Beispiele:
  .\variables-to-azure.ps1 -ResourceGroup MeinRG -FunctionApp MeineFunctionApp
  .\variables-to-azure.ps1 -ResourceGroup MeinRG -FunctionApp MeineFunctionApp -DryRun
  ```


### Schnellstart (lokal)

1. Falls noch nicht installiert: Azurite starten (siehe `Azurite-Setup.md` oder `Start-Azurite.ps1`).

2. Kopiere `local.settings.json.example` nach `local.settings.json` und passe Werte an.

3. Module installieren (falls nötig):
  ```powershell
  Set-Location ..\logiMailr-function
  .\tools\bootstrap-modules.ps1 -ModulePath modules
  ```

4. Optional: Beispiel-Blobs in Azurite hochladen:
  ```powershell
  .\tools\Upload-module.ps1
  ```

5. Function Host starten (normal):
  ```powershell
  func host start
  ```
  Oder für Debug mit helpers:
  ```powershell
  .\tools\debug-AzFunctionLocaly.ps1 -StartAzurite -FastCron -RunOnStartup
  ```

### Hinweise
- Viele Tools erwarten PowerShell 7.x, die Azure PowerShell-Module (`Az.*`) und die Azure Functions Core Tools (`func`).
- `set-Defenderpermissonscope.ps1` benötigt `Microsoft.Graph`-Module und ggf. App-Only-Credentials.
- `diag_simple.ps1` ist derzeit leer und kann bei Bedarf befüllt werden.

Wenn du möchtest, kann ich die README noch um Beispiele für Parameter und typische Fehlerfälle erweitern, oder die einzelnen Skripte kommentieren. 

Hinweis: Bei Problemen mit fehlenden Modulen `tools\bootstrap-modules.ps1` mit `-Verbose` ausführen und `requirements.psd1` prüfen.
