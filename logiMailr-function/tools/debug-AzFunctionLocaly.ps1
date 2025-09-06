<#
.SYNOPSIS
  Startet die Azure Function (PowerShell) LOKAL im DEBUG-Modus.

.DESCRIPTION
  - Setzt den PowerShell-Worker in den Debug-Wartemodus (NamedPipe oder TCP).
  - Optional: setzt schnellen Cron (*/10) und/oder runOnStartup=true für sofortige Ausführung.
  - Optional: startet Azurite (Blob/Queue/Table) lokal.
  - Startet anschließend 'func host start' im Projektordner.

.PARAMETER ProjectPath
  Pfad zum Function-Projekt (Ordner mit host.json). Default: aktuelles Verzeichnis.

.PARAMETER StartAzurite
  Startet Azurite lokal (nutzt tools\Start-Azurite.ps1, wenn vorhanden).

.PARAMETER FastCron
  Setzt 'TimerOrchestrator_Schedule' in local.settings.json auf '*/10 * * * * *' (alle 10 Sek.).

.PARAMETER RunOnStartup
  Fügt im Timer-Binding 'runOnStartup': true hinzu (TimerOrchestrator\function.json).

.PARAMETER Transport
  Debug-Transport des PowerShell-Workers: 'NamedPipe' (Default) oder 'Tcp'.

.PARAMETER TcpPort
  Port für TCP-Debugging (nur bei -Transport Tcp). Default: 55888.

.PARAMETER OpenVSCode
  Öffnet VS Code im Projektordner. Die mitgelieferte launch.json kann den Attach übernehmen.

.PARAMETER Revert
  Macht Änderungen von -FastCron und -RunOnStartup rückgängig (stellt Standardwerte wieder her).

.EXAMPLE
  # Schnell lokal debuggen (mit Azurite, alle 10s, runOnStartup, NamedPipe)
  .\debug-AzFunctionLocaly.ps1 -ProjectPath . -StartAzurite -FastCron -RunOnStartup

.EXAMPLE
  # TCP-Debug auf Port 55900 und VS Code öffnen
  .\debug-AzFunctionLocaly.ps1 -ProjectPath . -Transport Tcp -TcpPort 55900 -OpenVSCode

.NOTES
  Erfordert: Azure Functions Core Tools (func), PowerShell 7.x, Azurite (optional).
#>

[CmdletBinding()]
param(
  [string]$ProjectPath = ".",
  [switch]$StartAzurite,
  [switch]$FastCron,
  [switch]$RunOnStartup,
  [ValidateSet('NamedPipe','Tcp')][string]$Transport = 'NamedPipe',
  [int]$TcpPort = 55888,
  [switch]$OpenVSCode,
  [switch]$Revert
)

# If ProjectPath is default or not provided, try to locate the function project relative to this script (parent folder)
if ($ProjectPath -eq '.' -or [string]::IsNullOrWhiteSpace($ProjectPath)) {
  try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $candidate = Join-Path $scriptDir '..'
    $resolved = Resolve-Path $candidate -ErrorAction Stop
    $ProjectPath = $resolved.Path
    Write-Info "Auto-detected ProjectPath: $ProjectPath"
  } catch {
    Write-Warn "Could not auto-detect ProjectPath; using current directory '.'"
  }
}

# logging helpers (define immediately so aut-detect can use them)
function Write-Info([string]$m){ Write-Host ('[info] {0}' -f $m) -ForegroundColor Cyan }
function Write-Warn([string]$m){ Write-Host ('[warn] {0}' -f $m) -ForegroundColor Yellow }
function Write-Err ([string]$m){ Write-Host ('[err ] {0}' -f $m) -ForegroundColor Red }

# 0) Pfade & Tools prüfen
$full = Resolve-Path $ProjectPath
Set-Location $full
if (-not (Test-Path ".\host.json")) { Write-Err "host.json nicht gefunden unter '$full'"; exit 1 }

if (-not (Get-Command func -ErrorAction SilentlyContinue)) {
  Write-Err "Azure Functions Core Tools ('func') nicht gefunden. Installationshilfe: https://aka.ms/azfunc-install"
  exit 1
}


# 2) Optional FastCron / Revert
$lsPath = Join-Path $full "local.settings.json"
if (Test-Path $lsPath) {
  $ls = Get-Content $lsPath -Raw | ConvertFrom-Json
  if ($Revert) {
    if ($ls.Values.TimerOrchestrator_Schedule -eq "*/10 * * * * *") {
      $ls.Values.TimerOrchestrator_Schedule = "0 0 7 * * *"
      Write-Info "TimerOrchestrator_Schedule zurück auf 07:00 gestellt."
    }
  } elseif ($FastCron) {
    $ls.Values.TimerOrchestrator_Schedule = "*/10 * * * * *"
    Write-Info "TimerOrchestrator_Schedule auf */10 gesetzt."
  }
  $ls | ConvertTo-Json -Depth 20 | Set-Content $lsPath -Encoding UTF8
} else {
  Write-Warn "local.settings.json nicht gefunden – FastCron/Revert wird übersprungen."
}

# 3) Optional runOnStartup / Revert
$funcJson = Join-Path $full "TimerOrchestrator\function.json"
if (Test-Path $funcJson) {
  $fj = Get-Content $funcJson -Raw | ConvertFrom-Json
  $binding = $fj.bindings | Where-Object { $_.type -eq 'timerTrigger' }
  if ($Revert) {
    if ($binding.PSObject.Properties.Name -contains 'runOnStartup' -and $binding.runOnStartup -eq $true) {
      $binding.runOnStartup = $false
      Write-Info "runOnStartup=false gesetzt."
    }
  } elseif ($RunOnStartup) {
    if ($binding.PSObject.Properties.Name -contains 'runOnStartup') {
      $binding.runOnStartup = $true
    } else {
      Add-Member -InputObject $binding -NotePropertyName runOnStartup -NotePropertyValue $true
    }
    Write-Info "runOnStartup aktiviert."
  }
  $fj | ConvertTo-Json -Depth 20 | Set-Content $funcJson -Encoding UTF8
} else {
  Write-Warn "TimerOrchestrator\function.json nicht gefunden – runOnStartup/Revert wird übersprungen."
}

# 4) Debug-Umgebung setzen
$env:AZURE_FUNCTIONS_ENVIRONMENT = "Development"
$env:languageWorkers__powershell__debug__waitForDebugger = "true"
if ($Transport -eq 'NamedPipe') {
  $env:languageWorkers__powershell__debug__transport = "NamedPipe"
  Write-Info "Debug-Transport: NamedPipe (Attach in VS Code: 'Attach to Azure Functions (PowerShell)')"
} else {
  $env:languageWorkers__powershell__debug__transport = "tcp"
  $env:languageWorkers__powershell__debug__port = "$TcpPort"
  Write-Info ("Debug-Transport: TCP Port {0}" -f $TcpPort)
}

# 5) Optional VS Code öffnen
if ($OpenVSCode) {
  if (Get-Command code -ErrorAction SilentlyContinue) {
    Write-Info "VS Code wird geöffnet …"
    Start-Process code -ArgumentList "." | Out-Null
  } else {
    Write-Warn "'code' (VS Code CLI) nicht gefunden. Öffne VS Code manuell im Projektordner."
  }
}

## 6) Functions Host starten (foreground)
Write-Host ""
Write-Host '----------------------------------------------------------------' -ForegroundColor Gray
Write-Host ' WARTEMODUS AKTIV - Host startet jetzt im DEBUG-Modus.' -ForegroundColor Green
Write-Host '  * Triggere den Timer (*/10 oder runOnStartup) oder' -ForegroundColor Gray
Write-Host '  * loese per Admin-API aus:' -ForegroundColor Gray
Write-Host '----------------------------------------------------------------' -ForegroundColor Gray
Write-Host ""

# choose port (start at 7071) and find a free port if needed
$selectedPort = 7071
function Test-PortFree($port) {
  try {
    $out = netstat -ano | Select-String -Pattern ":$port\s"
    return -not $out
  } catch { return $false }
}

if (-not (Test-PortFree $selectedPort)) {
  Write-Warn "Port $selectedPort is unavailable. Searching for a free port..."
  $found = $false
  for ($p = $selectedPort + 1; $p -le ($selectedPort + 10); $p++) {
    if (Test-PortFree $p) { $selectedPort = $p; $found = $true; break }
  }
  if ($found) { Write-Info "Using fallback port: $selectedPort" } else { Write-Err "No free port found in range $($selectedPort)..$($selectedPort+10). Close the process using the port or specify a port with the script."; exit 1 }
}

Write-Host "Admin-API endpoint (for triggering TimerOrchestrator):" -ForegroundColor DarkGray
Write-Host "    Invoke-RestMethod -Method POST -Uri http://127.0.0.1:$selectedPort/admin/functions/TimerOrchestrator -ContentType 'application/json' -Body (@{ input = '' } | ConvertTo-Json)" -ForegroundColor DarkGray
Write-Host ""

# Start
Write-Info "Starting Functions host: func host start --port $selectedPort"
# Ensure worker runtime is set to PowerShell to avoid interactive language prompt
$env:FUNCTIONS_WORKER_RUNTIME = 'powershell'
& func host start --port $selectedPort
