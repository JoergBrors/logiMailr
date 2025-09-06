# reset-test.ps1 - stop azurite/node started by this repo, clear transient env vars and remove diagnostic files
Write-Host '=== RESET-TEST START ==='

# stop azurite or node processes that look like they run azurite
try {
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'azurite|node|Azurite' }
    if ($procs) {
        foreach ($p in $procs) {
            # attempt to inspect commandline to avoid killing unrelated node processes
            $cmd = try { (Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)").CommandLine } catch { $null }
            if ($cmd -and $cmd -match 'azurite') {
                Write-Host "Stopping process $($p.Id) ($($p.ProcessName)) - cmd: $cmd"
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            } elseif ($p.ProcessName -ieq 'azurite') {
                Write-Host "Stopping process $($p.Id) ($($p.ProcessName))"
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            }
        }
    } else { Write-Host 'No azurite/node processes found.' }
} catch {
    Write-Host 'Error while stopping processes:' $_.Exception.Message
}

# clear transient process env vars (only affects this process and children)
[Environment]::SetEnvironmentVariable('LOGIMAILR_STORAGE_CONNECTION',$null,'Process')
[Environment]::SetEnvironmentVariable('LOGIMAILR_STORAGE_URL',$null,'Process')
[Environment]::SetEnvironmentVariable('LOGIMAILR_STORAGE_ACCOUNT',$null,'Process')
[Environment]::SetEnvironmentVariable('LOGIMAILR_STORAGE_KEY',$null,'Process')
Write-Host 'Cleared process environment variables (LOGIMAILR_STORAGE_* for this process).' 
Write-Host 'Note: Please restart any open terminals to clear their environment too.'

# remove diagnostic files created under tools/
$toolsPath = Join-Path $PSScriptRoot '.'
$patterns = @("$toolsPath\\diag*","$toolsPath\\ctx_try_output.txt","$toolsPath\\diag_run_capture.txt","$toolsPath\\diag_out*.txt")
$deleted = @()
foreach ($pat in $patterns) {
    Get-ChildItem -Path $pat -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop; $deleted += $_.FullName; Write-Host ("Deleted {0}" -f $_.FullName) } catch { Write-Host ("Could not delete {0}: {1}" -f $_.FullName,$_.Exception.Message) }
    }
}

Write-Host '=== RESET-TEST SUMMARY ==='
Write-Host ('Deleted files: {0}' -f ($deleted -join ', '))
Write-Host '=== RESET-TEST END ==='
