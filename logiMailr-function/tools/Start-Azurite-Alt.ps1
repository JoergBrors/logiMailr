param(
  [string]$Location = "C:\azurite",
  [int]$BlobPort = 10010,
  [int]$QueuePort = 10011,
  [int]$TablePort = 10012
)

# validate ports (use approved verb 'Test')
function Test-PortRange {
  param(
    [int]$Port,
    [string]$Name
  )
  if ($Port -lt 0 -or $Port -gt 65535) {
    Write-Error ("{0} ({1}) is out of range. Must be 0..65535." -f $Name, $Port)
    exit 1
  }
}

Test-PortRange -Port $BlobPort -Name 'BlobPort'
Test-PortRange -Port $QueuePort -Name 'QueuePort'
Test-PortRange -Port $TablePort -Name 'TablePort'

Write-Host ('Starting Azurite (alt ports) at {0} ...' -f $Location)
if (-not (Test-Path $Location)) { New-Item -ItemType Directory -Path $Location | Out-Null }

# start azurite with explicit ports
azurite --silent --location $Location --blobHost 127.0.0.1 --blobPort $BlobPort --queueHost 127.0.0.1 --queuePort $QueuePort --tableHost 127.0.0.1 --tablePort $TablePort --debug "$Location\debug-alt.log"
