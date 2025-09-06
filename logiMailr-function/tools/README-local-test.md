# Lokaler Test

1. **Azurite** starten (Storage-Emulator).  
2. `local.settings.json` aus `local.settings.json.example` kopieren und Keys anpassen.  
3. PowerShell: `func start` im Ordner `logiMailr-function`.  
4. Module-JSONs liegen unter `modules/*`.  
5. Mails werden bei `LOGIMAILR_SEND_MODE=File` als HTML in `out-mail/` gespeichert.

Weitere Details & Installationswege siehe **tools/Azurite-Setup.md**.