try {
    . "$PSScriptRoot\Shared\Utils.ps1"
    $LocalModules = Join-Path $PSScriptRoot 'modules'
    if ($env:PSModulePath -notlike "*$LocalModules*") { $env:PSModulePath = "$LocalModules;$env:PSModulePath" }
    # Prefer Microsoft Graph modules for Graph/Defender interactions
    Import-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
    # Keep Az.Storage for storage cmdlets if present
    Import-Module Az.Storage -ErrorAction SilentlyContinue
    Write-Host "[profile] Utils geladen. Modules (Microsoft.Graph / Microsoft.Graph.Security / Az.Storage) geladen wenn verfügbar."
} catch {
    Write-Host ("[profile] Fehler: {0}" -f $_.Exception.Message)
    throw
}