# logiMailr

**logiMailr** ist eine modulare Azure Function Lösung in PowerShell,  
die Log Analytics und Microsoft Defender XDR Daten verarbeitet und  
daraus automatisierte HTML-Reports per E-Mail generiert.  

## 🚀 Ziel

- Einfache Erstellung von Reports (Tabellen, Charts) aus KQL-Abfragen.  
- Vollständig modular: Eingabe (KQL), Ausgabe (Mail-Template), Steuerung (Intervall, Empfänger).  
- Keine Code-Änderungen für neue Reports – nur JSON-Module im Blob Storage.  
- Sichere Anbindung über Managed Identity und native Azure/Graph APIs.  

## 🏗 Architektur

- **Azure Function App (PowerShell 7.x)**  
  - Timer Trigger oder Durable Functions für Orchestrierung.  
  - Managed Identity für Authentifizierung.  

- **Azure Storage (Blob)**  
  - `control/` – Steuer-Module (Verknüpfung Eingabe + Ausgabe + Intervall + Empfänger).  
  - `input/` – Eingabe-Module (KQL-Abfragen für Log Analytics oder Defender AH).  
  - `output/` – Ausgabe-Module (HTML-/Chart-Templates).  
  - `runs/` – Laufzeit-Protokolle und Logs.  

- **Quellen**  
  - Azure Monitor Logs (Log Analytics REST API).  
  - Microsoft Defender XDR (Advanced Hunting API).  

- **Mailing**  
  - Versand über Microsoft Graph API (`/sendMail`) via Managed Identity.  

## 📂 Beispiel-Struktur im Blob

```
control/
  report-security-weekly.json
  report-ops-daily.json

input/
  kql/signins-anomalies.json
  kql/defender-suspicious-process.json

output/
  templates/security-summary-v1.json
  templates/ops-capacity-v1.json

runs/
  2025-09-06/report-security-weekly.log.json
```

## 📝 Beispiel Steuer-Modul

```json
{
  "name": "Security Weekly",
  "enabled": true,
  "schedule": "0 0 7 ? * MON *",
  "sources": [
    { "type": "LogAnalytics", "module": "kql/signins-anomalies.json" },
    { "type": "DefenderAH",   "module": "kql/defender-suspicious-process.json" }
  ],
  "output": { "template": "templates/security-summary-v1.json" },
  "mail": {
    "sender": "security-reports@contoso.com",
    "recipients": ["soc@contoso.com","itsec@contoso.com"],
    "subject": "Security Weekly – {Date:yyyy-MM-dd}"
  }
}
```

## 🔐 Sicherheit & Berechtigungen

- **Managed Identity**  
  - Storage Blob Data Reader (für Module).  
  - Log Analytics Reader (für Workspaces).  
  - Defender XDR: `AdvancedQuery.Read.All`.  
  - Microsoft Graph: `Mail.Send`.  

## 🛠 Best Practices

- KQL-Abfragen optimieren (Zeiträume begrenzen, nur benötigte Spalten).  
- Templates im Blob versionieren, keine Hardcodierung im Code.  
- Orchestrierung mit Durable Functions für Skalierung & Wiederholungen.  
- Logging in Application Insights + Blob (`runs/`).  

---

## 📧 Ergebnis

- Automatisierte HTML-Mails mit Tabellen und optional Balkendiagrammen.  
- Zeitgesteuert (täglich, wöchentlich, monatlich).  
- Vollständig steuerbar über JSON-Module.  

---

Made with ❤️ in PowerShell & Azure
