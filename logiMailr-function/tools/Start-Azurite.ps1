param(
  [string]$Location = ".\.azurite"
)
Write-Host ('Starting Azurite at {0} ...' -f $Location)
if (-not (Test-Path $Location)) { New-Item -ItemType Directory -Path $Location | Out-Null }
azurite --silent --location $Location --debug "$Location\debug.log"