# Azurite – Lokales Azure Storage für logiMailr

Diese App nutzt **Azurite** für lokales Blob Storage. Offizielle Anleitung hier:  
▶️ Microsoft Learn: *Install and run Azurite emulator* citeturn0view0

## Installation (Optionen)

### 1) Visual Studio Code (Extension)
- In VS Code **Extensions** öffnen, nach **Azurite** suchen und installieren.  
- Standard-Ports: **Blob 10000**, **Queue 10001**, **Table 10002**. citeturn0view0

### 2) npm (Node.js)
```bash
npm install -g azurite
# Start (persistenter Speicher unter c:/azurite, Windows-Beispiel)
azurite --silent --location c:\azurite --debug c:\azurite\debug.log
```
(Erfordert Node.js. Alternativ `azurite -h` für Optionen.) citeturn0view0

### 3) Docker
```bash
docker run -p 10000:10000 -p 10001:10001 -p 10002:10002   mcr.microsoft.com/azure-storage/azurite
```
(Optional mit Volume: `-v c:/azurite:/data`) citeturn0view0

## Verwendung im Projekt

- **local.settings.json** (Beispiel liegt bei) nutzt `UseDevelopmentStorage=true` für die Verbindung.  
- Standard-Container werden beim Deployment-Script erstellt (`control`, `input`, `output`, `runs`).  
- Für lokale Tests sind Beispiel-Module in `modules/*` enthalten.

## VS Code Task

Im Repo liegt `.vscode/tasks.json` mit einem Task **Start Azurite (Blob/Queue/Table)**.  
Ausführen via **Terminal → Run Task**.

## Ports & Endpunkte (Default)

- Blob: `http://127.0.0.1:10000/`
- Queue: `http://127.0.0.1:10001/`
- Table: `http://127.0.0.1:10002/` citeturn0view0