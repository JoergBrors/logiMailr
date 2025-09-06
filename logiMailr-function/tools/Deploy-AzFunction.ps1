param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$ResourceGroup,
    [Parameter(Mandatory=$true)][string]$Location,
    [Parameter(Mandatory=$true)][string]$FunctionAppName,
    [string]$StorageAccountName = ("logimailr{0}" -f (Get-Random -Maximum 99999))
)

Write-Host ('Deploying to RG {0} in {1}...' -f $ResourceGroup,$Location)

# Login if needed: prefer Microsoft Graph interactive sign-in when available, otherwise Az
try {
    if (Get-Command -Name 'Connect-MgGraph' -ErrorAction SilentlyContinue) {
        try { Get-MgUser -Top 1 -ErrorAction Stop | Out-Null } catch { Connect-MgGraph -Scopes 'User.Read' | Out-Null }
    } else {
        try { (Get-AzContext) | Out-Null } catch { Connect-AzAccount | Out-Null }
    }
} catch {
    Write-Host "Warning: interactive login failed: $($_.Exception.Message)"
}

# Create RG
if (-not (Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $ResourceGroup -Location $Location | Out-Null
}

# Storage
if (-not (Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue)) {
    New-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroup -Location $Location -SkuName Standard_LRS -Kind StorageV2 | Out-Null
}

# Function App (Consumption, PowerShell)
$plan = New-AzFunctionAppPlan -Name ($FunctionAppName + '-plan') -ResourceGroupName $ResourceGroup -Location $Location -IsConsumptionPlan -Sku EP1 -WorkerType Windows -ErrorAction SilentlyContinue
$fa = New-AzFunctionApp -Name $FunctionAppName -ResourceGroupName $ResourceGroup -Location $Location -StorageAccountName $StorageAccountName -FunctionsVersion 4 -Runtime PowerShell -RuntimeVersion 7.2 -IdentityType SystemAssigned

# Blob containers
$ctx = (Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroup).Context
foreach ($c in @('control','input','output','runs')) {
    New-AzStorageContainer -Name $c -Context $ctx -Permission Off -ErrorAction SilentlyContinue | Out-Null
}

# App Settings
$kv = @{
    'LOGIMAILR_BLOB_CONTAINER_CONTROL' = 'control'
    'LOGIMAILR_BLOB_CONTAINER_INPUT'   = 'input'
    'LOGIMAILR_BLOB_CONTAINER_OUTPUT'  = 'output'
    'LOGIMAILR_BLOB_CONTAINER_RUNS'    = 'runs'
    'LOGIMAILR_SEND_MODE'              = 'Graph'
}
$settings = @()
foreach ($k in $kv.Keys) { $settings += @{ Name=$k; Value=$kv[$k] } }
Update-AzFunctionAppSetting -Name $FunctionAppName -ResourceGroupName $ResourceGroup -AppSetting $settings | Out-Null

Write-Host 'Assigning roles...'
# Allow Function to read blobs
$mi = (Get-AzFunctionApp -Name $FunctionAppName -ResourceGroupName $ResourceGroup).IdentityPrincipalId
New-AzRoleAssignment -ObjectId $mi -RoleDefinitionName 'Storage Blob Data Reader' -Scope (Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroup).Id -ErrorAction SilentlyContinue | Out-Null

Write-Host 'Zip deploy...'
# Create zip
$zip = Join-Path $env:TEMP ('logimailr-{0}.zip' -f (Get-Date -Format 'yyyyMMddHHmmss'))
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($ProjectPath, $zip)
Publish-AzWebApp -ResourceGroupName $ResourceGroup -Name $FunctionAppName -ArchivePath $zip

Write-Host 'Done. Remember to grant Graph/Defender permissions to the managed identity.'