# Utils.ps1 - shared helpers for logiMailr
using namespace System.Net

function Get-Env {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$Default
    )
    $val = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if (-not $val -and $PSBoundParameters.ContainsKey('Default')) { return $Default }
    return $val
}

function New-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
    $ts = (Get-Date).ToString('s')
    Write-Host ('[{0}] [{1}] {2}' -f $ts,$Level,$Message)
}

function Get-AccessToken {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('loganalytics','defender','graph')][string]$For
    )
    switch ($For) {
        'loganalytics' { $res = 'https://api.loganalytics.azure.com' }
        'defender'     { $res = 'https://api.security.microsoft.com' }
        'graph'        { $res = 'https://graph.microsoft.com' }
    }
    try {
        # Works with Managed Identity in Azure; locally requires Az login
        $token = (Get-AzAccessToken -ResourceUrl $res).Token
        return $token
    } catch {
        throw "Failed to acquire token for $For: $($_.Exception.Message)"
    }
}

function Get-BlobClient {
    # Build a simple client using Az.Storage
    $account = Get-Env -Name 'LOGIMAILR_STORAGE_ACCOUNT'
    $key     = Get-Env -Name 'LOGIMAILR_STORAGE_KEY'
    if (-not $account -or -not $key) {
        throw 'Storage account name/key not set. Configure LOGIMAILR_STORAGE_ACCOUNT / LOGIMAILR_STORAGE_KEY.'
    }
    $ctx = New-AzStorageContext -StorageAccountName $account -StorageAccountKey $key
    return $ctx
}

function Get-BlobJson {
    param(
        [Parameter(Mandatory=$true)][string]$Container,
        [Parameter(Mandatory=$true)][string]$BlobName
    )
    $ctx = Get-BlobClient
    $tmp = New-TemporaryFile
    Get-AzStorageBlobContent -Container $Container -Blob $BlobName -Destination $tmp.FullName -Context $ctx -Force | Out-Null
    $json = Get-Content $tmp.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    return $json
}

function Get-ControlModules {
    param([string]$Container = (Get-Env -Name 'LOGIMAILR_BLOB_CONTAINER_CONTROL' -Default 'control'))
    $ctx = Get-BlobClient
    $blobs = Get-AzStorageBlob -Container $Container -Context $ctx
    $items = @()
    foreach ($b in $blobs) {
        if ($b.Name -like '*.json') {
            $items += [pscustomobject]@{
                Name = $b.Name
                Json = Get-BlobJson -Container $Container -BlobName $b.Name
            }
        }
    }
    return $items
}

function Invoke-LogAnalyticsQuery {
    param(
        [Parameter(Mandatory=$true)][string]$WorkspaceId,
        [Parameter(Mandatory=$true)][string]$Kql,
        [string]$Timespan = 'P1D'
    )
    $token = Get-AccessToken -For loganalytics
    $uri = 'https://api.loganalytics.azure.com/v1/workspaces/{0}/query' -f $WorkspaceId
    $body = @{ query = $Kql; timespan = $Timespan } | ConvertTo-Json -Depth 5
    $resp = Invoke-RestMethod -Method POST -Uri $uri -Headers @{ Authorization = "Bearer $token" } -Body $body -ContentType 'application/json'
    return $resp
}

function Invoke-DefenderAHQuery {
    param(
        [Parameter(Mandatory=$true)][string]$Kql
    )
    $token = Get-AccessToken -For defender
    $uri = 'https://api.security.microsoft.com/api/advancedhunting/run'
    $body = @{ Query = $Kql } | ConvertTo-Json -Depth 5
    $resp = Invoke-RestMethod -Method POST -Uri $uri -Headers @{ Authorization = "Bearer $token" } -Body $body -ContentType 'application/json'
    return $resp
}

function Convert-TableToHtml {
    param(
        [Parameter(Mandatory=$true)]$Table,  # expects rows/columns format similar to LA/Defender response
        [string]$Title = 'Results'
    )
    $html = "<h3>$Title</h3><table style='border-collapse:collapse;width:100%'>"
    # detect schema
    if ($Table.tables) { $t = $Table.tables[0] } else { $t = $Table } # LA schema vs simple
    $cols = $t.columns.name
    $html += '<thead><tr>' + ($cols | ForEach-Object { "<th style='border:1px solid #ddd;padding:6px;text-align:left'>{0}</th>" -f $_ }) -join '' + '</tr></thead>'
    $html += '<tbody>'
    foreach ($r in $t.rows) {
        $html += '<tr>' + ($r | ForEach-Object { "<td style='border:1px solid #ddd;padding:6px'>{0}</td>" -f [Web.HttpUtility]::HtmlEncode([string]$_) }) -join '' + '</tr>'
    }
    $html += '</tbody></table>'
    return $html
}

function Render-HtmlReport {
    param(
        [Parameter(Mandatory=$true)]$TemplateJson,
        [Parameter(Mandatory=$true)]$ResultsMap  # hashtable like @{ LogAnalytics = @($resp1,...); DefenderAH = @($resp2,...) }
    )
    $brand = $TemplateJson.style.brandColor
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!doctype html><html><head><meta charset="utf-8"><title>logiMailr</title>')
    [void]$sb.AppendLine("<style>h2{color:$brand} table{font-family:Segoe UI,Arial,sans-serif;font-size:12px}</style>")
    [void]$sb.AppendLine('</head><body>')
    [void]$sb.AppendLine("<h2>{0}</h2>" -f ($TemplateJson.title ?? 'Report'))
    foreach ($sec in $TemplateJson.sections) {
        switch ($sec.type) {
            'table' {
                $bind = $sec.bind.Split('[')[0]
                $idx  = [int]($sec.bind -replace '.*\[(\d+)\].*','$1')
                $tbl  = $ResultsMap[$bind][$idx]
                $html = Convert-TableToHtml -Table $tbl -Title $sec.title
                [void]$sb.AppendLine($html)
            }
            default {
                [void]$sb.AppendLine("<!-- Unsupported section type: $($sec.type) -->")
            }
        }
    }
    [void]$sb.AppendLine('</body></html>')
    return $sb.ToString()
}

function Send-ReportMail {
    param(
        [Parameter(Mandatory=$true)][string]$Subject,
        [Parameter(Mandatory=$true)][string]$HtmlBody,
        [Parameter(Mandatory=$true)][string[]]$To
    )
    $mode = Get-Env -Name 'LOGIMAILR_SEND_MODE' -Default 'File'
    if ($mode -eq 'File') {
        $outDir = Get-Env -Name 'LOGIMAILR_TEST_OUTDIR' -Default './out-mail'
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
        $file = Join-Path $outDir ('{0:yyyyMMdd-HHmmss}-{1}.html' -f (Get-Date), ($Subject -replace '[^\w\-]+','_'))
        Set-Content -Path $file -Value $HtmlBody -Encoding UTF8
        New-Log -Message ("Saved mail to file: {0}" -f $file)
        return
    }
    # Graph mode
    $token = Get-AccessToken -For graph
    $body = @{
        message = @{
            subject = $Subject
            body    = @{ contentType = 'HTML'; content = $HtmlBody }
            toRecipients = @($To | ForEach-Object { @{ emailAddress = @{ address = $_ } } })
        }
        saveToSentItems = $true
    } | ConvertTo-Json -Depth 8
    $sender = Get-Env -Name 'LOGIMAILR_MAIL_SENDER'
    $uri = if ($sender) { "https://graph.microsoft.com/v1.0/users/$sender/sendMail" } else { "https://graph.microsoft.com/v1.0/me/sendMail" }
    Invoke-RestMethod -Method POST -Uri $uri -Headers @{ Authorization = "Bearer $token" } -Body $body -ContentType 'application/json' | Out-Null
    New-Log -Message ('Sent mail via Graph to: {0}' -f ($To -join ', '))
}

function Write-RunLogBlob {
    param(
        [Parameter(Mandatory=$true)][string]$FileName,
        [Parameter(Mandatory=$true)][string]$Content
    )
    $ctx = Get-BlobClient
    $container = Get-Env -Name 'LOGIMAILR_BLOB_CONTAINER_RUNS' -Default 'runs'
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp.FullName -Value $Content -Encoding UTF8
    Set-AzStorageBlobContent -Context $ctx -Container $container -File $tmp.FullName -Blob $FileName -Force | Out-Null
}