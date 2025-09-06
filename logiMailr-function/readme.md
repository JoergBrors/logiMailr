# logiMailr

**logiMailr** ist eine modulare Azure Function Lösung in PowerShell,
die Log Analytics und Microsoft Defender XDR Daten verarbeitet und
daraus automatisierte HTML-Reports per E-Mail generiert.

## 🚀 Ziel

- Einfache Erstellung von Reports (Tabellen, Charts) aus KQL-Abfragen.
- Vollständig modular: Eingabe (KQL), Ausgabe (Mail-Template), Steuerung (Intervall, Empfänger).
- Keine Code-Änderungen für neue Reports – nur JSON-Module im Blob Storage.
- Sichere Anbindung über Managed Identity und native Azure/Graph APIs.

## 🏗 Architektur (Kurz)

- **Azure Function App (PowerShell 7.x)**, Timer Trigger (optional Durable Functions).
- **Blob Storage**: `control/`, `input/`, `output/`, `runs/`.
- **Quellen**: Azure Monitor Logs (Log Analytics), Defender XDR Advanced Hunting.
- **Mailing**: Microsoft Graph `/sendMail` (oder lokal als Datei).

---

## 📦 Was ist drin?

- **TimerOrchestrator/** – Function (Timer), lädt Steuer-Module, führt KQL aus, rendert HTML, verschickt Mails.
- **Shared/Utils.ps1** – Helpers (Token, Blob, KQL, HTML, Mail, RunLog).
- **modules/** – Beispiel-Module (control/input/output) in JSON.
- **host.json**, **requirements.psd1**, **profile.ps1**
- **local.settings.json.example** – fürs lokale Testen (Azurite + File-Mailmodus).
- **.vscode/tasks.json** – VS Code Tasks (Azurite starten/aufräumen).
- **tools/Deploy-AzFunction.ps1** – One-Command-Deployment (RG, Storage, Function App, App Settings, Zip Deploy).
- **tools/README-local-test.md** – Kurz-Anleitung lokaler Start.
- **tools/Azurite-Setup.md** – Details zur Installation/Benutzung von Azurite.

---

## 🧪 Lokal testen

1. **Azurite** starten  
   - Über VS Code: **Terminal → Run Task → Start Azurite (Blob/Queue/Table)**  
   - Oder per Script: `./tools/Start-Azurite.ps1`
   - Details: siehe **[tools/Azurite-Setup.md](tools/Azurite-Setup.md)**

2. **local.settings.json** anlegen  
   `local.settings.json.example` → `local.settings.json` kopieren und anpassen:
   ```json
   {
     "IsEncrypted": false,
     "Values": {
       "AzureWebJobsStorage": "UseDevelopmentStorage=true",
       "FUNCTIONS_WORKER_RUNTIME": "powershell",
       "TimerOrchestrator_Schedule": "0 0 7 * * *",
       "LOGIMAILR_STORAGE_ACCOUNT": "devstoreaccount1",
       "LOGIMAILR_STORAGE_KEY": "AzuriteKeyHere",
       "LOGIMAILR_BLOB_CONTAINER_CONTROL": "control",
       "LOGIMAILR_BLOB_CONTAINER_INPUT": "input",
       "LOGIMAILR_BLOB_CONTAINER_OUTPUT": "output",
       "LOGIMAILR_BLOB_CONTAINER_RUNS": "runs",
       "LOGIMAILR_WORKSPACE_ID": "<DEIN-LAW-WORKSPACE-ID>",
       "LOGIMAILR_MAIL_SENDER": "security-reports@contoso.com",
       "LOGIMAILR_SEND_MODE": "File",
       "LOGIMAILR_TEST_OUTDIR": "./out-mail"
     }
   }
   ```

3. **Beispiel-Module** prüfen/anpassen  
   - `modules/input/kql/signins-anomalies.json` → `workspaceId` + `kql`
   - `modules/input/kql/defender-suspicious-process.json` → `kql`
   - `modules/control/report-security-weekly.json` → `mail.sender`/`recipients`/`subject`

4. **Function starten**
   ```powershell
   func start
   ```
   Mails werden lokal als **HTML** in `out-mail/` gespeichert (`LOGIMAILR_SEND_MODE=File`).

---

## ☁️ Deployment nach Azure

```powershell
./tools/Deploy-AzFunction.ps1 `
  -ProjectPath "<Pfad-zum-Ordner logiMailr-function>" `
  -ResourceGroup "rg-logimailr" `
  -Location "westeurope" `
  -FunctionAppName "logimailr-func"
```

**App Settings (Portal/CLI) nach Deploy prüfen/ergänzen:**
- `LOGIMAILR_BLOB_CONTAINER_CONTROL=input/output/runs` (falls abweichend)
- **Mail-Modus (produktiv):**
  ```text
  LOGIMAILR_SEND_MODE = Graph
  LOGIMAILR_MAIL_SENDER = security-reports@contoso.com
  LOGIMAILR_WORKSPACE_ID = <DEIN-LAW-WORKSPACE-ID>
  ```

**Rollen & Berechtigungen für Managed Identity:**
- Storage: **Storage Blob Data Reader**
- Log Analytics: **Log Analytics Reader**
- Microsoft Graph: **Mail.Send** (+ optional **Group.Read.All**)
- Defender XDR: **AdvancedHunting.Read.All** (bzw. AdvancedQuery.Read.All)
> Nach dem Zuweisen der App-Rollen die Function einmal **neu starten**.

**Module hochladen** (in das Storage der Function):
- `control/` – Steuer-Module
- `input/` – KQL-Module
- `output/` – Template-Module

---

## ⚙️ Hinweise & Best Practices

- KQL: Zeiträume begrenzen, nur benötigte Spalten, früh aggregieren.
- Templates & Module versionieren (JSON im Blob statt Code ändern).
- Optional pro Report eigener Zeitplan `schedule` im Control-JSON.
- Telemetrie: Application Insights + Run-Logs unter `runs/`.

---

## ❓Troubleshooting (Kurz)

- **Keine Module gefunden** → Container/Blobs vorhanden? App Settings korrekt?
- **401 bei Abfragen** → MI-Rollen/Graph/Defender-Berechtigungen gesetzt? App neu gestartet?
- **Mails kommen nicht an** → `LOGIMAILR_SEND_MODE=File` vs. `Graph` prüfen, `mail.sender`/Berechtigungen prüfen.

---

Made with ❤️ in PowerShell & Azure
