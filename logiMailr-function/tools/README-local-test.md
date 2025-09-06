# Lokaler Test

Kurzanleitung zum lokalen Test der Function App.

1. Azurite (Storage Emulator) starten.

2. `local.settings.json` aus `local.settings.json.example` kopieren und Werte anpassen.

3. Optional: Module bootstrapen (falls noch nicht vorhanden):

    ```powershell
    .\bootstrap-modules.ps1 -InstallPath ..\modules
    ```

4. Function Host starten:

    ```powershell
    cd ..\logiMailr-function
    func start
    ```

5. Laufende Tests: Bei `LOGIMAILR_SEND_MODE=File` werden generierte E‑Mails als HTML in `out-mail/` gespeichert.

Hinweis: Bei Problemen mit fehlenden Modulen `tools\bootstrap-modules.ps1` mit `-Verbose` ausführen und `requirements.psd1` prüfen.
