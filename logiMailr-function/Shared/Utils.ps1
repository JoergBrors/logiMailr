# Utils.ps1 - shared helpers for logiMailr
using namespace System.Net

function Get-Env {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$Default,
        [switch]$Fallback
    )
    $val = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if ($null -ne $val -and $val -ne '') { return $val }
    if ($Fallback.IsPresent) { return $Default }
    if ($PSBoundParameters.ContainsKey('Default')) { return $Default }
    return $null
}

function New-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
    $ts = (Get-Date).ToString('s')
    Write-Host ('[{0}] [{1}] {2}' -f $ts,$Level,$Message)
}

function Get-AccessToken {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('loganalytics','defender','graph')][string]$For,
        [string[]]$Scopes
    )
    switch ($For) {
        'loganalytics' { $res = 'https://api.loganalytics.io' }
        'defender'     { $res = 'https://api.security.microsoft.com' }
        'graph'        { $res = 'https://graph.microsoft.com' }
    }
    # Use app-only client credentials only.
    $tenant = Get-Env -Name 'AZ_TENANT_ID'
    $client = Get-Env -Name 'AZ_CLIENT_ID'
    $secret = Get-Env -Name 'AZ_CLIENT_SECRET'
    if ($tenant -and $client -and $secret) {
        New-Log -Message 'Acquiring app-only token using AZ_CLIENT_* environment variables.'
        try {
            return Get-AppOnlyAccessToken -Resource $res
        } catch {
            throw "Failed to acquire app-only token for $For : $($_.Exception.Message)"
        }
    }

    throw "No app-only credentials found. Set AZ_TENANT_ID, AZ_CLIENT_ID and AZ_CLIENT_SECRET to enable application-token authentication."
}

# Acquire an app-only access token (client credentials) for a resource (e.g. https://api.security.microsoft.com)
function Get-AppOnlyAccessToken {
    param(
        [Parameter(Mandatory=$true)][string]$Resource
    )
    # expect tenant/client/secret in environment
    $tenant = Get-Env -Name 'AZ_TENANT_ID'
    $client = Get-Env -Name 'AZ_CLIENT_ID'
    $secret = Get-Env -Name 'AZ_CLIENT_SECRET'
    if (-not $tenant -or -not $client -or -not $secret) {
        throw "App-only auth requires AZ_TENANT_ID, AZ_CLIENT_ID and AZ_CLIENT_SECRET environment variables to be set."
    }

    $tokenEndpoint = "https://login.microsoftonline.com/$tenant/oauth2/v2.0/token"
    $body = @{ grant_type = 'client_credentials'; client_id = $client; client_secret = $secret; scope = "$Resource/.default" }
    try {
        $resp = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body $body -ContentType 'application/x-www-form-urlencoded'
        return $resp.access_token
    } catch {
        throw "Failed to acquire app-only access token: $($_.Exception.Message)"
    }
}

# ConvertFrom-JwtPayload: decode the payload part of a JWT (handles URL-safe base64 and missing padding)
function ConvertFrom-JwtPayload {
    param(
        [Parameter(Mandatory=$true)][string]$Token
    )
    if (-not $Token) { throw 'Token is required.' }
    $parts = $Token -split '\.'
    if ($parts.Count -lt 2) { throw 'Invalid JWT: not enough parts.' }
    $payload = $parts[1]
    # URL-safe base64 -> regular base64
    $payload = $payload.Replace('-','+').Replace('_','/')
    # Add padding to make length a multiple of 4
    while ($payload.Length % 4 -ne 0) { $payload += '=' }
    try {
        $bytes = [System.Convert]::FromBase64String($payload)
        $json = [System.Text.Encoding]::UTF8.GetString($bytes)
        return $json
    } catch {
        throw "Failed to decode JWT payload: $($_.Exception.Message)"
    }
}

# Convenience: return the payload as an object
function Get-JwtClaims {
    param(
        [Parameter(Mandatory=$true)][string]$Token
    )
    $json = ConvertFrom-JwtPayload -Token $Token
    try { return $json | ConvertFrom-Json } catch { throw "JWT payload is not valid JSON: $($_.Exception.Message)" }
}

function New-TempFileObject {
    try { return New-TemporaryFile } catch { return [PSCustomObject]@{ FullName = [System.IO.Path]::GetTempFileName() } }

}

function Get-BlobClient {
    # accept several env var names
    $cs = Get-Env -Name 'LOGIMAILR_STORAGE_CONNECTION'
    if (-not $cs) { $cs = Get-Env -Name 'LOGIMAILR_STORAGE_CONNECTION_STRING' }
    if (-not $cs) { $cs = Get-Env -Name 'AzureWebJobsStorage' }

    if ($cs) {
        New-Log -Message "Found storage connection string (len=$($cs.Length)). Trying New-AzStorageContext(ConnectionString)"
        try {
            if (Get-Command -Name 'Add-Type' -ErrorAction SilentlyContinue) {
                try { [void][Microsoft.Azure.Storage.CloudStorageAccount]::Parse($cs) } catch { }
            }
        } catch { throw "LOGIMAILR_STORAGE_CONNECTION ist ungültig: $($_.Exception.Message)" }
        try { return New-AzStorageContext -ConnectionString $cs } catch {
            New-Log -Level 'WARN' -Message ("New-AzStorageContext(ConnectionString) failed: {0}" -f $_.Exception.Message)
            # account/key fallback
            $account = Get-Env -Name 'LOGIMAILR_STORAGE_ACCOUNT'
            $key     = Get-Env -Name 'LOGIMAILR_STORAGE_KEY'
            New-Log -Message ("Fallback: account present: {0}, key present: {1}" -f ([bool]$account, [bool]$key))
            if ($account -and $key) {
                try { New-Log -Message "Trying New-AzStorageContext(StorageAccountName/Key)"; return New-AzStorageContext -StorageAccountName $account -StorageAccountKey $key } catch {
                    New-Log -Level 'WARN' -Message ("Account/key fallback failed: {0}" -f $_.Exception.Message)
                    # try endpoints fallback e.g. Azurite
                    $url = Get-Env -Name 'LOGIMAILR_STORAGE_URL'
                    if ($url) {
                        try {
                            New-Log -Message ("Trying endpoints fallback using LOGIMAILR_STORAGE_URL: {0}" -f $url)
                            $blobEndpoint = $url
                            $queueEndpoint = Get-Env -Name 'LOGIMAILR_STORAGE_QUEUE_ENDPOINT' -Default ($blobEndpoint -replace ':10000',':10001')
                            $tableEndpoint = Get-Env -Name 'LOGIMAILR_STORAGE_TABLE_ENDPOINT' -Default ($blobEndpoint -replace ':10000',':10002')
                            return New-AzStorageContext -StorageAccountName $account -StorageAccountKey $key -BlobEndpoint $blobEndpoint -QueueEndpoint $queueEndpoint -TableEndpoint $tableEndpoint
                        } catch { throw "Could not create storage context using endpoints fallback: $($_.Exception.Message)" }
                    }
                    throw "Could not create storage context with account/key fallback: $($_.Exception.Message)"
                }
            }
            throw $_
        }
    }

    # no connection string — try account/key
    $account = Get-Env -Name 'LOGIMAILR_STORAGE_ACCOUNT'
    $key     = Get-Env -Name 'LOGIMAILR_STORAGE_KEY'
    if (-not $account -or -not $key) { throw 'Storage: Bitte LOGIMAILR_STORAGE_CONNECTION **oder** LOGIMAILR_STORAGE_ACCOUNT / LOGIMAILR_STORAGE_KEY setzen.' }
    $suffix = Get-Env -Name 'LOGIMAILR_STORAGE_SUFFIX'
    if ([string]::IsNullOrWhiteSpace($suffix)) { $suffix = 'core.windows.net' }
    try {
        if ([string]::IsNullOrWhiteSpace($suffix)) { return New-AzStorageContext -StorageAccountName $account -StorageAccountKey $key }
        else { return New-AzStorageContext -StorageAccountName $account -StorageAccountKey $key -EndpointSuffix $suffix }
    } catch { throw "Failed to create storage context: $($_.Exception.Message)" }
}

function Get-BlobJson {
    param([Parameter(Mandatory=$true)][string]$Container, [Parameter(Mandatory=$true)][string]$BlobName)
    $ctx = Get-BlobClient
    $tmp = New-TempFileObject
    Get-AzStorageBlobContent -Container $Container -Blob $BlobName -Destination $tmp.FullName -Context $ctx -Force | Out-Null
    return Get-Content $tmp.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-ControlModules { param([string]$Container = (Get-Env -Name 'LOGIMAILR_BLOB_CONTAINER_CONTROL' -Default 'control'))
    $ctx = Get-BlobClient; $blobs = Get-AzStorageBlob -Container $Container -Context $ctx; $items = @()
    foreach ($b in $blobs) { if ($b.Name -like '*.json') { $items += [pscustomobject]@{ Name = $b.Name; Json = Get-BlobJson -Container $Container -BlobName $b.Name } } }
    return $items
}

function Invoke-LogAnalyticsQuery { param([Parameter(Mandatory=$true)][string]$WorkspaceId, [Parameter(Mandatory=$true)][string]$Kql, [string]$Timespan = 'P1D')
    $token = Get-AccessToken -For loganalytics
    $uri = 'https://api.loganalytics.io/v1/workspaces/{0}/query' -f $WorkspaceId
    $body = @{ query = $Kql; timespan = $Timespan } | ConvertTo-Json -Depth 5
    return Invoke-RestMethod -Method POST -Uri $uri -Headers @{ Authorization = "Bearer $token" } -Body $body -ContentType 'application/json'
}

function Invoke-DefenderAHQuery {
    param(
        [Parameter(Mandatory=$true)][string]$Kql,
        [switch]$AppOnly
    )
    $body = @{ Query = $Kql } | ConvertTo-Json -Depth 5

    $graphPath = 'https://graph.microsoft.com/v1.0/security/microsoft.graph.security.runHuntingQuery'

    # If AppOnly requested, prefer using an app-only token immediately (no delegated SDK calls)
    if ($AppOnly.IsPresent) {
        New-Log -Message 'AppOnly requested: acquiring app-only token and calling Defender advanced hunting.'
        $token = Get-AppOnlyAccessToken -Resource 'https://graph.microsoft.com'
        try {
            New-Log -Message "Attempting Graph endpoint with app-only token: $graphPath"
            return Invoke-RestMethod -Method POST -Uri $graphPath -Headers @{ Authorization = "Bearer $token" } -Body $body -ContentType 'application/json'
        } catch {
            New-Log -Level 'WARN' -Message ("Graph app-only call failed: {0}. Falling back to api.security.microsoft.com" -f $_.Exception.Message)
            $uri = 'https://api.security.microsoft.com/api/advancedhunting/run'
            return Invoke-RestMethod -Method POST -Uri $uri -Headers @{ Authorization = "Bearer $token" } -Body $body -ContentType 'application/json'
        }
    }

    # Delegated path: Prefer Microsoft.Graph.Authentication request helper if available (Invoke-MgGraphRequest)
    if (Get-Command -Name 'Invoke-MgGraphRequest' -ErrorAction SilentlyContinue) {
        try {
            New-Log -Message "Using Invoke-MgGraphRequest to call $graphPath"
            return Invoke-MgGraphRequest -Method POST -Uri $graphPath -Body $body -ContentType 'application/json'
        } catch {
            New-Log -Level 'WARN' -Message ("Invoke-MgGraphRequest failed: {0}" -f $_.Exception.Message)
            New-Log -Message 'Falling back to direct REST call with bearer token.'
            # continue to fallback below
        }
    } else {
        New-Log -Message 'Invoke-MgGraphRequest not present; using bearer token REST fallback.'
    }

    # Fallback delegated: explicit bearer token call against api.security.microsoft.com
    $uri = 'https://api.security.microsoft.com/api/advancedhunting/run'
    $token = Get-AccessToken -For defender
    return Invoke-RestMethod -Method POST -Uri $uri -Headers @{ Authorization = "Bearer $token" } -Body $body -ContentType 'application/json'
}

function Convert-TableToHtml {
    param([Parameter(Mandatory=$true)]$Table, [string]$Title = 'Results')
    $html = "<h3>$Title</h3><table style='border-collapse:collapse;width:100%'>"
    $t = if ($Table.tables) { $Table.tables[0] } else { $Table }
    $cols = $t.columns.name
    $html += '<thead><tr>' + ($cols | ForEach-Object { "<th style='border:1px solid #ddd;padding:6px;text-align:left'>{0}</th>" -f $_ }) -join '' + '</tr></thead>'
    $html += '<tbody>'
    foreach ($r in $t.rows) { $html += '<tr>' + ($r | ForEach-Object { "<td style='border:1px solid #ddd;padding:6px'>{0}</td>" -f [System.Net.WebUtility]::HtmlEncode([string]$_) }) -join '' + '</tr>' }
    $html += '</tbody></table>'
    return $html
}

# Render-HtmlReport: dynamic renderer that understands multiple KQL result shapes
function Render-HtmlReport {
    param([Parameter(Mandatory=$true)]$TemplateJson, [Parameter(Mandatory=$true)]$ResultsMap)

    $brand = $TemplateJson.style.brandColor -or '#0078D4'
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!doctype html><html><head><meta charset="utf-8"><title>logiMailr</title>')
    [void]$sb.AppendLine("<style>h2{color:$brand} table{font-family:Segoe UI,Arial,sans-serif;font-size:12px;border-collapse:collapse} th,td{border:1px solid #ddd;padding:6px;text-align:left}</style>")
    [void]$sb.AppendLine('</head><body>')
    [void]$sb.AppendLine("<h2>{0}</h2>" -f ($TemplateJson.title -or 'Report'))
    [void]$sb.AppendLine(("<p style='color:#666;font-size:12px'>Generated: {0}</p>" -f (Get-Date).ToString('u')))

    # helper: convert array of objects (DefenderAH / generic JSON arrays) to HTML table
    function Convert-ObjectsToHtmlTable {
        param([Parameter(Mandatory=$true)][object[]]$Objects, [string]$Title = 'Results')
        if (-not $Objects -or $Objects.Count -eq 0) { return ("<h3>$Title</h3><p><em>No results</em></p>") }
        # derive columns from first object (fallback: union of keys)
        $first = $Objects | Select-Object -First 1
        $cols = @()
        if ($first -is [System.Management.Automation.PSCustomObject] -or $first -is [hashtable]) { $cols = $first.PSObject.Properties.Name } else { $cols = $first | Get-Member -MemberType NoteProperty,Property | Select-Object -ExpandProperty Name }
        $html = "<h3>$Title</h3><table style='width:100%'>"
        $html += '<thead><tr>' + ($cols | ForEach-Object { "<th>{0}</th>" -f ([System.Net.WebUtility]::HtmlEncode($_)) }) -join '' + '</tr></thead>'
        $html += '<tbody>'
        foreach ($o in $Objects) {
            $html += '<tr>'
            foreach ($c in $cols) {
                $val = $null
                try { $val = $o.$c } catch { $val = $null }
                if ($null -ne $val) {
                    if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
                        $txt = ($val -join ', ')
                    } else {
                        $txt = [string]$val
                    }
                    $s = [System.Net.WebUtility]::HtmlEncode($txt)
                } else {
                    $s = ''
                }
                $html += "<td>$s</td>"
            }
            $html += '</tr>'
        }
        $html += '</tbody></table>'
        return $html
    }

    foreach ($sec in $TemplateJson.sections) {
        switch ($sec.type) {
            'table' {
                $bind = $sec.bind.Split('[')[0]; $idx = 0
                if ($sec.bind -match '\[(\d+)\]') { $idx = [int]$matches[1] }
                $tbl = $null
                if ($ResultsMap.ContainsKey($bind) -and $ResultsMap[$bind].Count -gt $idx) { $tbl = $ResultsMap[$bind][$idx] }
                if (-not $tbl) { [void]$sb.AppendLine("<!-- Missing result for bind: $bind[$idx] -->"); continue }

                # Log Analytics response shape: has 'tables' array
                if ($tbl.tables) {
                    [void]$sb.AppendLine((Convert-TableToHtml -Table $tbl -Title $sec.title))
                    continue
                }

                # Defender Advanced Hunting (app responses) often contain 'Results' array of objects
                if ($tbl.Results -and ($tbl.Results -is [System.Collections.IEnumerable])) {
                    # ensure Results is an object[]
                    $objs = @($tbl.Results) -as [object[]]
                    [void]$sb.AppendLine((Convert-ObjectsToHtmlTable -Objects $objs -Title $sec.title))
                    continue
                }

                # Some Graph/Defender Graph responses return 'value' arrays
                if ($tbl.value -and ($tbl.value -is [System.Collections.IEnumerable])) {
                    $objs = @($tbl.value) -as [object[]]
                    [void]$sb.AppendLine((Convert-ObjectsToHtmlTable -Objects $objs -Title $sec.title))
                    continue
                }

                # Generic: if object has rows/columns (other variants)
                if ($tbl.rows -and $tbl.columns) {
                    # Build a small table using columns/rows
                    $cols = $tbl.columns | ForEach-Object { $_.name }
                    $html = "<h3>$($sec.title)</h3><table style='width:100%'>"
                    $html += '<thead><tr>' + ($cols | ForEach-Object { "<th>{0}</th>" -f ([System.Net.WebUtility]::HtmlEncode($_)) }) -join '' + '</tr></thead>'
                    $html += '<tbody>'
                    foreach ($r in $tbl.rows) { $html += '<tr>' + ($r | ForEach-Object { "<td>{0}</td>" -f ([System.Net.WebUtility]::HtmlEncode([string]$_)) }) -join '' + '</tr>' }
                    $html += '</tbody></table>'
                    [void]$sb.AppendLine($html)
                    continue
                }

                # Fallback: if it's already raw HTML string
                if ($sec.rawHtml -and ($tbl -is [string])) { [void]$sb.AppendLine($tbl); continue }

                # Unknown shape: render JSON blob
                [void]$sb.AppendLine("<h3>$($sec.title)</h3><pre>" + [System.Net.WebUtility]::HtmlEncode(($tbl | ConvertTo-Json -Depth 5)) + '</pre>')
            }
            default { [void]$sb.AppendLine("<!-- Unsupported section type: $($sec.type) -->") }
        }
    }

    [void]$sb.AppendLine('</body></html>')
    return $sb.ToString()
}

function New-LogiHtmlReport { param([Parameter(Mandatory=$true)]$TemplateJson, [Parameter(Mandatory=$true)]$ResultsMap)
    $brand = $TemplateJson.style.brandColor; $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!doctype html><html><head><meta charset="utf-8"><title>logiMailr</title>')
    [void]$sb.AppendLine("<style>h2{color:$brand} table{font-family:Segoe UI,Arial,sans-serif;font-size:12px}</style>")
    [void]$sb.AppendLine('</head><body>')
    [void]$sb.AppendLine("<h2>{0}</h2>" -f ($TemplateJson.title -or 'Report'))
    foreach ($sec in $TemplateJson.sections) {
        switch ($sec.type) {
            'table' {
                $bind = $sec.bind.Split('[')[0]; $idx = [int]($sec.bind -replace '.*\[(\d+)\].*','$1')
                $tbl = $null
                if ($ResultsMap.ContainsKey($bind) -and $ResultsMap[$bind].Count -gt $idx) { $tbl = $ResultsMap[$bind][$idx] }
                if (-not $tbl) { [void]$sb.AppendLine("<!-- Missing result for bind: $bind[$idx] -->"); continue }
                [void]$sb.AppendLine((Convert-TableToHtml -Table $tbl -Title $sec.title))
            }
            default { [void]$sb.AppendLine("<!-- Unsupported section type: $($sec.type) -->") }
        }
    }
    [void]$sb.AppendLine('</body></html>')
    return $sb.ToString()
}

function Send-ReportMail {
    param([Parameter(Mandatory=$true)][string]$Subject, [Parameter(Mandatory=$true)][string]$HtmlBody, [Parameter(Mandatory=$true)][string[]]$To)
    $mode = Get-Env -Name 'LOGIMAILR_SEND_MODE' -Default 'File'
    if ($mode -eq 'File') {
        $outDir = Get-Env -Name 'LOGIMAILR_TEST_OUTDIR' -Default './out-mail'
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
        $file = Join-Path $outDir ('{0:yyyyMMdd-HHmmss}-{1}.html' -f (Get-Date), ($Subject -replace '[^\w\-]+','_'))
        Set-Content -Path $file -Value $HtmlBody -Encoding UTF8
        New-Log -Message ("Saved mail to file: {0}" -f $file)
        return
    }
    # Prefer Microsoft.Graph.Authentication request helper if available (Invoke-MgGraphRequest)
    $mailSender = Get-Env -Name 'LOGIMAILR_MAIL_SENDER'
    $body = @{ message = @{ subject = $Subject; body = @{ contentType = 'HTML'; content = $HtmlBody }; toRecipients = @($To | ForEach-Object { @{ emailAddress = @{ address = $_ } } }) }; saveToSentItems = $true } | ConvertTo-Json -Depth 8

    if (Get-Command -Name 'Invoke-MgGraphRequest' -ErrorAction SilentlyContinue) {
        try {
            $uri = if ($mailSender) { "https://graph.microsoft.com/v1.0/users/$mailSender/sendMail" } else { "https://graph.microsoft.com/v1.0/me/sendMail" }
            Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType 'application/json' | Out-Null
            New-Log -Message ('Sent mail via Graph (Invoke-MgGraphRequest) to: {0}' -f ($To -join ', '))
            return
        } catch {
            New-Log -Level 'WARN' -Message ("Invoke-MgGraphRequest send failed: {0}" -f $_.Exception.Message)
            New-Log -Message 'Falling back to other methods.'
        }
    }

    # Legacy SDK helper (if the user installed full Microsoft.Graph modules)
    if (Get-Command -Name 'Send-MgUserMessage' -ErrorAction SilentlyContinue) {
        try {
            $recips = $To | ForEach-Object { @{ emailAddress = @{ address = $_ } } }
            $message = @{ subject = $Subject; body = @{ contentType = 'HTML'; content = $HtmlBody }; toRecipients = $recips }
            if ($mailSender) { Send-MgUserMessage -UserId $mailSender -Message $message -SaveToSentItems } else { Send-MgUserMessage -UserId 'me' -Message $message -SaveToSentItems }
            New-Log -Message ('Sent mail via Graph SDK to: {0}' -f ($To -join ', '))
            return
        } catch {
            New-Log -Level 'WARN' -Message ("Send-MgUserMessage failed: {0}" -f $_.Exception.Message)
            New-Log -Message 'Falling back to raw REST send via Get-AccessToken.'
        }
    }

    # Final fallback: manual REST call using token acquisition helper
    $token = Get-AccessToken -For graph
    $uri = if ($mailSender) { "https://graph.microsoft.com/v1.0/users/$mailSender/sendMail" } else { "https://graph.microsoft.com/v1.0/me/sendMail" }
    Invoke-RestMethod -Method POST -Uri $uri -Headers @{ Authorization = "Bearer $token" } -Body $body -ContentType 'application/json' | Out-Null
    New-Log -Message ('Sent mail via Graph (REST) to: {0}' -f ($To -join ', '))
}

function Write-RunLogBlob { param([Parameter(Mandatory=$true)][string]$FileName, [Parameter(Mandatory=$true)][string]$Content)
    $ctx = Get-BlobClient
    $container = Get-Env -Name 'LOGIMAILR_BLOB_CONTAINER_RUNS' -Default 'runs'
    $tmp = New-TempFileObject
    Set-Content -Path $tmp.FullName -Value $Content -Encoding UTF8
    Set-AzStorageBlobContent -Context $ctx -Container $container -File $tmp.FullName -Blob $FileName -Force | Out-Null
}