try {
    . "$PSScriptRoot\Shared\Utils.ps1"
    $LocalModules = Join-Path $PSScriptRoot 'modules'
    if ($env:PSModulePath -notlike "*$LocalModules*") { $env:PSModulePath = "$LocalModules;$env:PSModulePath" }
    # Prefer Microsoft Graph modules for Graph/Defender interactions
    Import-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
    # Keep Az.Storage for storage cmdlets if present
    Import-Module Az.Storage -ErrorAction SilentlyContinue
    Write-Host "[profile] Utils geladen. Modules (Microsoft.Graph / Microsoft.Graph.Security / Az.Storage) geladen wenn verfügbar."

    # Diagnostic output to help troubleshoot missing modules during local debug
    try {
        Write-Host "[profile] PSModulePath entries:" -ForegroundColor Cyan
        ($env:PSModulePath -split ';') | ForEach-Object { Write-Host "  $_" }
        Write-Host "[profile] Available (Microsoft.Graph.Authentication / Az.Storage):" -ForegroundColor Cyan
        Get-Module -ListAvailable Microsoft.Graph.Authentication,Az.Storage | Sort-Object Name,Version | ForEach-Object {
            Write-Host ('  {0} {1} -> {2}' -f $_.Name, $_.Version, $_.Path)
        }
    } catch {
        Write-Host "[profile] Diagnostics failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} catch {
    Write-Host ("[profile] Fehler: {0}" -f $_.Exception.Message)
    throw
}