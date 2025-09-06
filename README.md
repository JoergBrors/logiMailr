# logiMailr

logiMailr ist eine modulare Azure Function‑Lösung in PowerShell, die aus KQL‑Abfragen automatisierte HTML‑Reports erstellt und per E‑Mail versendet.

Kurz: Das Projekt lädt JSON‑Module aus Blob Storage, führt Abfragen gegen Log Analytics / Defender Advanced Hunting aus, rendert HTML‑Templates und verschickt Ergebnisse über Microsoft Graph oder speichert sie lokal für Tests.

## Schnellstart (lokal)

1. Kopiere `logiMailr-function/local.settings.json.example` → `logiMailr-function/local.settings.json` und passe Werte für Storage, Workspace und Mail‑Modus an.

2. Starte Azurite oder verwende ein echtes Storage Konto.

3. Optional: Bootstrap der benötigten PowerShell‑Module:

   ```powershell
   .\tools\bootstrap-modules.ps1 -InstallPath .\modules
   ```

4. Starte den Functions Host:

   ```powershell
   cd logiMailr-function
   func start
   ```

## Aufbau

- `logiMailr-function/` – Function App und Shared‑Skripte
- `modules/` – vendored PowerShell‑Module und Beispiel‑JSON‑Module
- `tools/` – Hilfsskripte (Bootstrap, Deploy, Azurite‑Setup)

## Sicherheit & Berechtigungen

Empfohlene Rollen/Berechtigungen für die Managed Identity:

- Storage: Storage Blob Data Reader
- Log Analytics: Log Analytics Reader
- Microsoft Graph: Mail.Send
- Defender XDR: AdvancedHunting.Read.All (oder AdvancedQuery.Read.All)

Nach dem Zuweisen von Rollen die Function App neu starten.

## Weiteres

Siehe `logiMailr-function/readme.md` für function‑spezifische Hinweise und `logiMailr-function/tools/README-local-test.md` für lokale Testanweisungen.

