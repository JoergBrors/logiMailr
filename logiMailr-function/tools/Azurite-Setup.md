# Azurite — local Azure Storage for logiMailr

This app uses **Azurite** for local Blob Storage. Official guidance: Microsoft Learn: Install and run Azurite emulator.

## Installation (options)

### 1) Visual Studio Code (Extension)
- Open **Extensions** in VS Code, search for **Azurite** and install it.
- Default ports: **Blob 10000**, **Queue 10001**, **Table 10002**.

### 2) npm (Node.js)
```bash
npm install -g azurite
# Start (persist data under c:/azurite, Windows example)
azurite --silent --location c:\azurite --debug c:\azurite\debug.log
```
(Requires Node.js. Alternatively run `azurite -h` for options.)

### 3) Docker
```bash
docker run -p 10000:10000 -p 10001:10001 -p 10002:10002 mcr.microsoft.com/azure-storage/azurite
```
(Optional with volume: `-v c:/azurite:/data`)

## Usage in this project

- `local.settings.json` (example provided) can use `UseDevelopmentStorage=true` for the connection.
- The deployment script creates default containers (`control`, `input`, `output`, `runs`).
- Example modules for local tests are available in `modules/*`.

## VS Code Task

The repo contains `.vscode/tasks.json` with a task named **Start Azurite (Blob/Queue/Table)**. Run it via **Terminal → Run Task**.

## Ports & endpoints (default)

- Blob: `http://127.0.0.1:10000/`
- Queue: `http://127.0.0.1:10001/`
- Table: `http://127.0.0.1:10002/`