# Lädt Settings aus local.settings.json, setzt sie als Umgebungsvariablen,
# lädt Utils.ps1 und führt TimerOrchestrator/run.ps1 lokal aus.

# local.settings.json einlesen
$settingsPath = Join-Path $PSScriptRoot '..\local.settings.json'
if (!(Test-Path $settingsPath)) {
    Write-Error "local.settings.json nicht gefunden: $settingsPath"
    exit 1
}
$settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

# ApplicationSettings als Umgebungsvariablen setzen
if ($settings.Values) {
    foreach ($prop in $settings.Values.PSObject.Properties) {
        $envName = $prop.Name
        $envValue = $prop.Value
        # Normalize common key aliases so scripts that expect slightly different names still work
        switch ($envName) {
            'LOGIMAILR_STORAGE_CONNECTION_STRING' { $target = 'LOGIMAILR_STORAGE_CONNECTION'; break }
            default { $target = $envName }
        }
        [System.Environment]::SetEnvironmentVariable($target, $envValue, 'Process')
        Write-Host "Setze Umgebungsvariable: $target = $envValue"
    }
}

# Utils.ps1 laden
$utilsPath = Join-Path $PSScriptRoot '..\Shared\Utils.ps1'
if (Test-Path $utilsPath) {
    . $utilsPath
    Write-Host "Utils.ps1 geladen."
} else {
    Write-Warning "Utils.ps1 nicht gefunden: $utilsPath"
}

# Optional: Timer-Objekt simulieren
$Timer = @{
    ScheduleStatus = @{
        Last = (Get-Date).AddMinutes(-5)
        Next = (Get-Date).AddMinutes(5)
    }
    IsPastDue = $false
}

# TimerOrchestrator/run.ps1 ausführen
$functionScript = Join-Path $PSScriptRoot '..\TimerOrchestrator\run.ps1'
if (Test-Path $functionScript) {
    Write-Host "Starte TimerOrchestrator/run.ps1 ..."
    # & $functionScript -Timer $Timer   # falls $Timer-Parameter benötigt wird
    & $functionScript
    Write-Host "Fertig."
} else {
    Write-Error ("Function-Skript nicht gefunden: {0}" -f $functionScript)
    exit 1
}