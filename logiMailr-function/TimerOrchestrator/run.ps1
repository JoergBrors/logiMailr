param($Timer)

New-Log -Message ('logiMailr run started at {0}' -f (Get-Date))

try {
    $controls = Get-ControlModules
    if (-not $controls -or $controls.Count -eq 0) {
        New-Log -Level 'WARN' -Message 'No control modules found.'
        return
    }

    foreach ($c in $controls) {
        if (-not $c.Json.enabled) { New-Log -Message ("Skipping disabled control: {0}" -f $c.Name); continue }

        # CRON check is simplified: function schedule governs frequency; you can add per-control schedule later if needed
        $results = @{
            LogAnalytics = @()
            DefenderAH   = @()
        }

        foreach ($src in $c.Json.sources) {
            switch ($src.type) {
                'LogAnalytics' {
                    $mod = Get-BlobJson -Container (Get-Env -Name 'LOGIMAILR_BLOB_CONTAINER_INPUT' -Default 'input') -BlobName $src.module
                    $kql = $mod.kql
                    # PowerShell-compatible defaulting
                    if ($mod.PSObject.Properties.Name -contains 'timeRange' -and $mod.timeRange) { $timespan = $mod.timeRange } else { $timespan = 'P1D' }
                    if ($mod.PSObject.Properties.Name -contains 'workspaceId' -and $mod.workspaceId) { $workspace = $mod.workspaceId } else { $workspace = (Get-Env -Name 'LOGIMAILR_WORKSPACE_ID') }
                    if (-not $workspace) { throw 'WorkspaceId not set in module or env LOGIMAILR_WORKSPACE_ID' }
                    $resp = Invoke-LogAnalyticsQuery -WorkspaceId $workspace -Kql $kql -Timespan $timespan
                    $results.LogAnalytics += $resp
                }
                'DefenderAH' {
                    $mod = Get-BlobJson -Container (Get-Env -Name 'LOGIMAILR_BLOB_CONTAINER_INPUT' -Default 'input') -BlobName $src.module
                    $kql = $mod.kql
                    $resp = Invoke-DefenderAHQuery -Kql $kql -AppOnly
                    $results.DefenderAH += $resp
                }
                default {
                    New-Log -Level 'WARN' -Message ("Unknown source type: {0}" -f $src.type)
                }
            }
        }

        $template = Get-BlobJson -Container (Get-Env -Name 'LOGIMAILR_BLOB_CONTAINER_OUTPUT' -Default 'output') -BlobName $c.Json.output.template
        if (-not $template.title) { $template | Add-Member -NotePropertyName title -NotePropertyValue $c.Json.name -Force }

        $html = Render-HtmlReport -TemplateJson $template -ResultsMap $results

        $subject = $c.Json.mail.subject -replace '{Date:yyyy-MM-dd}', (Get-Date).ToString('yyyy-MM-dd')
        $recips  = @($c.Json.mail.recipients)
        Send-ReportMail -Subject $subject -HtmlBody $html -To $recips

        $runLog = [pscustomobject]@{
            control   = $c.Name
            timestamp = (Get-Date).ToString('o')
            rowsLA    = (($results.LogAnalytics | ForEach-Object {
                            if ($null -ne $_ -and $_.tables -and $_.tables.Count -gt 0 -and $_.tables[0].rows) { $_.tables[0].rows.Count } else { 0 }
                         } | Measure-Object -Sum).Sum)
            rowsAH    = (($results.DefenderAH | ForEach-Object {
                            if ($null -ne $_ -and $_.Results) { $_.Results.Count } else { 0 }
                         } | Measure-Object -Sum).Sum)
            recipients= ($recips -join ', ')
        } | ConvertTo-Json -Depth 5
        $runBlob = '{0:yyyy-MM-dd}/run-{1}.json' -f (Get-Date), ($c.Name -replace '.json$','')
        Write-RunLogBlob -FileName $runBlob -Content $runLog
    }

} catch {
    New-Log -Level 'ERROR' -Message $_.Exception.Message
    throw
}

New-Log -Message ('logiMailr run finished at {0}' -f (Get-Date))