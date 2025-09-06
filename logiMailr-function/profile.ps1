# profile.ps1 - minimal & safe
try {
    . "$PSScriptRoot\Shared\Utils.ps1"
    Write-Host "[profile] Utils geladen."
} catch {
    Write-Host ("[profile] Fehler: {0}" -f $_.Exception.Message)
    throw
}
