<#
Überträgt die Werte aus local.settings.json (Objekt `Values`) in die App Settings einer Azure Function App.

Beispiele:
  .\variables-to-azure.ps1 -ResourceGroup MeinRG -FunctionApp MeineFunctionApp
  .\variables-to-azure.ps1 -ResourceGroup MeinRG -FunctionApp MeineFunctionApp -DryRun

Hinweise:
- Standardpfad für local.settings.json ist der Parent-Ordner dieses Skripts: ..\local.settings.json
- Achtung: secrets wie ConnectionStrings werden ebenfalls übertragen. Nutze `-SkipSecrets` wenn Du sensible Werte nicht übertragen willst.
#>

param(
	[Parameter(Mandatory=$true)][string]$ResourceGroup,
	[Parameter(Mandatory=$true)][string]$FunctionApp,
	[string]$LocalSettingsPath,
	[switch]$DryRun,
	[switch]$WhatIf,
	[switch]$Force,
	[switch]$SkipSecrets
)

function New-Log([string]$msg,[string]$level='INFO') {
	$ts = (Get-Date).ToString('s')
	Write-Host "[$ts] [$level] $msg"
}

 # If LocalSettingsPath wasn't provided, resolve relative to the script location
 if ([string]::IsNullOrWhiteSpace($LocalSettingsPath)) {
	 try { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { $scriptDir = $PSScriptRoot }
	 if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = Get-Location }
	 $LocalSettingsPath = Join-Path $scriptDir '..\local.settings.json'
 }

# Validate local.settings.json
if (-not (Test-Path $LocalSettingsPath)) {
	New-Log "local.settings.json not found at: $LocalSettingsPath" 'ERROR'
	exit 1
}

try {
	$raw = Get-Content -Path $LocalSettingsPath -Raw -ErrorAction Stop
	$ls = $raw | ConvertFrom-Json -ErrorAction Stop
} catch {
	New-Log "Failed to read/parse local.settings.json: $($_.Exception.Message)" 'ERROR'
	exit 1
}

if (-not $ls.Values) {
	New-Log "No 'Values' object found in local.settings.json" 'ERROR'
	exit 1
}

# Build AppSetting list for Update-AzFunctionAppSetting
$appSettings = @()

# Optionally skip well-known secrets
$secretKeys = @('AzureWebJobsStorage','StorageAccountKey','LOGIMAILR_STORAGE_KEY','AZ_CLIENT_SECRET','AZ_CLIENT_ID','AZ_TENANT_ID')



foreach ($p in $ls.Values.PSObject.Properties) {
	$name = $p.Name
	$value = $p.Value

	if ($SkipSecrets.IsPresent -and ($secretKeys -contains $name)) {
		New-Log "Skipping secret key: $name" 'WARN'
		continue
	}

	# ensure value is string; if complex, serialize compactly
	if ($value -is [System.Management.Automation.PSObject] -or $value -is [hashtable] -or $value -is [array]) {
		$valStr = $value | ConvertTo-Json -Compress -Depth 10
	} else {
		$valStr = [string]$value
	}

	$entry = @{ Name = $name; Value = $valStr }
	$appSettings += $entry
}

if ($appSettings.Count -eq 0) {
	New-Log "No app settings were prepared (empty Values or all skipped)." 'WARN'
	exit 0
}

New-Log "Prepared $($appSettings.Count) app settings for Function App '$FunctionApp' in RG '$ResourceGroup'."

if ($DryRun.IsPresent) {
	New-Log "DRY RUN: The following App Settings would be applied:" 'INFO'
	$appSettings | ForEach-Object { Write-Host ("  {0} = {1}" -f $_.Name, $_.Value) }
	exit 0
}

# Convert array of @{Name=..;Value=..} to a hashtable expected by Update-AzFunctionAppSetting
$appSettingsHash = @{}
foreach ($e in $appSettings) { $appSettingsHash[$e.Name] = $e.Value }

if ($WhatIf.IsPresent) {
	New-Log "WHATIF: The following App Settings would be applied to Function App '$FunctionApp' in RG '$ResourceGroup':" 'INFO'
	$appSettingsHash.GetEnumerator() | ForEach-Object { Write-Host ("  {0} = {1}" -f $_.Name, $_.Value) }
	exit 0
}

# Ensure Az module context
if (-not (Get-Command -Name 'Get-AzContext' -ErrorAction SilentlyContinue)) {
	New-Log "Az PowerShell module not available in this session. Please install Az and import the module." 'ERROR'
	exit 1
}

try {
	$ctx = Get-AzContext -ErrorAction SilentlyContinue
	if (-not $ctx) {
		New-Log "Not logged in to Azure. Calling Connect-AzAccount..." 'INFO'
		Connect-AzAccount -ErrorAction Stop
	}
} catch {
	New-Log "Azure login failed: $($_.Exception.Message)" 'ERROR'
	exit 1
}

# If Force not specified, warn about overwrites
if (-not $Force.IsPresent) {
	New-Log "Note: existing App Settings with the same names will be overwritten. Use -Force to acknowledge." 'WARN'
}

# Call Update-AzFunctionAppSetting (it accepts an array of @{Name=..;Value=..})
try {
	if ($Force.IsPresent) {
		New-Log "Applying App Settings (Force) to $FunctionApp in $ResourceGroup" 'INFO'
		Update-AzFunctionAppSetting -Name $FunctionApp -ResourceGroupName $ResourceGroup -AppSetting $appSettingsHash -Force
	} else {
		New-Log "Applying App Settings to $FunctionApp in $ResourceGroup" 'INFO'
		Update-AzFunctionAppSetting -Name $FunctionApp -ResourceGroupName $ResourceGroup -AppSetting $appSettingsHash
	}
	New-Log "Update complete." 'INFO'
} catch {
	New-Log "Update failed: $($_.Exception.Message)" 'ERROR'
	throw
}
