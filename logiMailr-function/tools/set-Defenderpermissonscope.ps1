# Parameters
param(
  [Parameter(Mandatory=$false)]
  [array]
  $Permissions,
  [switch]
  $DryRun,
  [string]
  $ReportPath
)

# Connect to Microsoft Graph.
# If AZ_CLIENT_ID/AZ_TENANT_ID/AZ_CLIENT_SECRET are set, prefer app-only (client credentials) auth.
$tenantEnv = $env:AZ_TENANT_ID
$clientEnv = $env:AZ_CLIENT_ID
$secretEnv = $env:AZ_CLIENT_SECRET

if ($tenantEnv -and $clientEnv -and $secretEnv) {
  if (Get-Command -Name 'Connect-MgGraph' -ErrorAction SilentlyContinue) {
    try {
      Write-Host 'AZ_CLIENT_* present — connecting to Microsoft Graph using app-only client credentials.'
      Connect-MgGraph -ClientId $clientEnv -TenantId $tenantEnv -ClientSecret $secretEnv -Scopes @() -ErrorAction Stop
      Write-Host 'Connected (app-only) to Microsoft Graph.'
    } catch {
      throw "Connect-MgGraph (app-only) failed: $($_.Exception.Message)"
    }
  } else {
    throw 'Microsoft.Graph.Authentication module not available (Connect-MgGraph not found).'
  }
} else {
  if (Get-Command -Name 'Connect-MgGraph' -ErrorAction SilentlyContinue) {
    $ctx = $null
    if (Get-Command -Name 'Get-MgContext' -ErrorAction SilentlyContinue) {
      try { $ctx = Get-MgContext -ErrorAction Stop } catch { $ctx = $null }
    }
    if (-not $ctx) {
      Write-Host 'No existing MgGraph context found — calling Connect-MgGraph.'
      Connect-MgGraph -Scopes 'Application.ReadWrite.All','AppRoleAssignment.ReadWrite.All','Directory.Read.All'
    } else {
      Write-Host 'Existing MgGraph context detected; skipping Connect-MgGraph.'
    }
  } else {
    throw 'Microsoft.Graph.Authentication module not available (Connect-MgGraph not found).'
  }
}

$clientAppId = '30808d99-543c-44c5-be32-47e3358fce79'
$clientSp = Get-MgServicePrincipal -Filter "appId eq '$clientAppId'"
$mtpSp    = Get-MgServicePrincipal -Filter "appId eq 'fc780465-2017-40d4-a0c5-307022471b92'"
# Microsoft Graph service principal (regular graph permissions live here)
$graphSp  = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

# Also operate on the Application registration so the permissions show up under "Configured permissions"
try {
  $clientApp = Get-MgApplication -Filter "appId eq '$clientAppId'"
} catch {
  Write-Warning "Could not retrieve Application object for appId ${clientAppId}: $($_.Exception.Message)"
  $clientApp = $null
}

# Default permission specs when none are provided. Each entry needs AppId and Values (array of permission names)
if (-not $Permissions -or $Permissions.Count -eq 0) {
  $Permissions = @(
    @{ AppId = 'fc780465-2017-40d4-a0c5-307022471b92'; Values = @('AdvancedQuery.Read.All'); Name = 'WindowsDefenderATP' },
    @{ AppId = '00000003-0000-0000-c000-000000000000'; Values = @('ThreatHunting.Read.All'); Name = 'Microsoft Graph' },
    @{ AppId = '00000003-0000-0000-c000-000000000000'; Values = @('Mail.Send'); Name = 'Microsoft Graph' }
  )
}

$results = @()

function Add-PermissionForResource {
  param(
    $resourceAppId,
    $permissionValues
  )
  # fetch service principal for resource
  $sp = Get-MgServicePrincipal -Filter "appId eq '$resourceAppId'"
  if (-not $sp) {
    $results += [pscustomobject]@{ ResourceAppId = $resourceAppId; Error = 'Resource service principal not found'; Action = 'skip' }
    return
  }

  $roles = $sp.AppRoles | Where-Object { $permissionValues -contains $_.Value -and $_.AllowedMemberTypes -contains 'Application' }
  if (-not $roles -or $roles.Count -eq 0) {
    $results += [pscustomobject]@{ ResourceAppId = $resourceAppId; Error = 'No matching app-roles found'; Action = 'skip' }
    return
  }

    foreach ($r in $roles) {
    $entry = @{
      ResourceAppId = $resourceAppId
      Permission = $r.Value
      AppRoleId = $r.Id
      Assigned = $false
      AlreadyAssigned = $false
      AssignedError = $null
      ManifestUpdated = $false
      ManifestError = $null
      Action = $null
    }

    # check existing assignment
    $already = $false
    try {
      if (Get-Command -Name 'Invoke-MgGraphRequest' -ErrorAction SilentlyContinue) {
        $resp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($clientSp.Id)/appRoleAssignedTo" -ErrorAction Stop
        $vals = $resp.value
        if ($vals) { $already = $vals | Where-Object { ($_.resourceId -eq $sp.Id) -and ($_.appRoleId -eq $r.Id) -and ($_.principalId -eq $clientSp.Id) } }
      }
    } catch {
      Write-Warning "Could not enumerate existing role assignments: $($_.Exception.Message) -- will attempt to assign anyway."
      $already = $false
    }

        if ($already) {
      $entry['AlreadyAssigned'] = $true
      $entry['Action'] = 'none'
      Write-Host "Role $($r.Value) already assigned; skipping."
    } else {
      if ($DryRun) {
        $entry.Action = 'plan-assign'
        Write-Host "[DRY-RUN] Would assign $($r.Value) to service principal $($clientSp.Id) against resource $($sp.Id)"
      } else {
        try {
          New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $clientSp.Id -PrincipalId $clientSp.Id -ResourceId $sp.Id -AppRoleId $r.Id
          $entry.Assigned = $true
          $entry.Action = 'assigned'
          Write-Host "Assigned $($r.Value) successfully."
        } catch {
          $msg = $_.Exception.Message
          # if the permission already exists, mark as already assigned
          if ($msg -and $msg -match 'Permission being assigned already exists') {
            $entry['AlreadyAssigned'] = $true
            $entry['Action'] = 'none'
            Write-Host "Permission already exists according to Graph response; marking as already assigned."
          } else {
            $entry['AssignedError'] = $msg
            $entry['Action'] = 'assign-failed'
            Write-Warning "Failed to assign role $($r.Value): $msg"
          }
        }
      }
    }

    # update application manifest requiredResourceAccess so permission appears in Configured permissions
    if ($clientApp) {
      try {
        $req = @()
        if ($clientApp.RequiredResourceAccess) { $req = @($clientApp.RequiredResourceAccess) }
        $existing = $req | Where-Object { $_.resourceAppId -eq $sp.AppId } | Select-Object -First 1
        $resAccess = @(@{ id = $r.Id; type = 'Role' })
        if ($existing) {
          $existingIds = @($existing.resourceAccess) | Select-Object -ExpandProperty id -ErrorAction SilentlyContinue
          if (-not $existingIds) { $existingIds = @() }
          $toAdd = $resAccess | Where-Object { $existingIds -notcontains $_.id }
          if ($toAdd.Count -gt 0) {
            if (-not $DryRun) {
              $existing.resourceAccess = @($existing.resourceAccess) + $toAdd
              $entry['ManifestUpdated'] = $true
              if ($entry['Action'] -eq 'assigned') { $entry['Action'] = 'assigned+manifest' }
            }
            $ids = ($toAdd | ForEach-Object { $_.id }) -join ','
            Write-Host "Added permission(s) to manifest for resource $($sp.AppId): $ids"
          } else { Write-Host 'ResourceAccess already present in application manifest.' }
        } else {
          $newEntry = @{ resourceAppId = $sp.AppId; resourceAccess = $resAccess }
          if (-not $DryRun) {
            $req += $newEntry
            $entry['ManifestUpdated'] = $true
            if ($entry['Action'] -eq 'assigned') { $entry['Action'] = 'assigned+manifest' }
          }
          Write-Host "Added new requiredResourceAccess entry for resource $($sp.AppId)."
        }

    if (-not $DryRun -and $entry['ManifestUpdated']) {
          Update-MgApplication -ApplicationId $clientApp.Id -RequiredResourceAccess $req
        }
      } catch {
    $entry['ManifestError'] = $_.Exception.Message
    Write-Warning "Failed to update Application manifest for resource $($sp.AppId): $($_.Exception.Message)"
      }
    }

  $results += [pscustomobject]$entry
  }
}

# Iterate requested permissions
foreach ($spec in $Permissions) {
  $appId = $spec.AppId
  $vals = @()
  if ($spec.Values) { $vals = @($spec.Values) }
  Add-PermissionForResource -resourceAppId $appId -permissionValues $vals
}

# Emit JSON report
$json = $results | ConvertTo-Json -Depth 5
if ($ReportPath) { $json | Out-File -FilePath $ReportPath -Encoding UTF8 }
Write-Host 'Permission operation report:'
Write-Host $json



