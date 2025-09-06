# 1) Azurite laufen lassen (Ports 10000/10001/10002)

# 2) Az.Storage-Context für Azurite
$cs = 'DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;QueueEndpoint=http://127.0.0.1:10001/devstoreaccount1;TableEndpoint=http://127.0.0.1:10002/devstoreaccount1;'

$ctx = New-AzStorageContext -ConnectionString $cs

# 3) Container anlegen
'control','input','output','runs' | ForEach-Object {
  New-AzStorageContainer -Name $_ -Context $ctx -Permission Off -ErrorAction SilentlyContinue | Out-Null
}

# 4) Beispielmodule hochladen (Pfad anpassen auf dein Repo)
$root = "D:\GIT\REPRO\logiMailr\logiMailr-function\modules"
Set-AzStorageBlobContent -Context $ctx -Container control -File "$root\control\report-security-weekly.json" -Blob "report-security-weekly.json" -Force | Out-Null
Set-AzStorageBlobContent -Context $ctx -Container input   -File "$root\input\kql\signins-anomalies.json" -Blob "kql/signins-anomalies.json" -Force | Out-Null
Set-AzStorageBlobContent -Context $ctx -Container input   -File "$root\input\kql\defender-suspicious-process.json" -Blob "kql/defender-suspicious-process.json" -Force | Out-Null
Set-AzStorageBlobContent -Context $ctx -Container output  -File "$root\output\templates\security-summary-v1.json" -Blob "templates/security-summary-v1.json" -Force | Out-Null