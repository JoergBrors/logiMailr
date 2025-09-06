<#
.SYNOPSIS
  Bootstrap required PowerShell modules into the project's modules/ folder using Save-Module.
.DESCRIPTION
  Reads requirements.psd1 in the function project root and calls Save-Module for each entry.
.PARAMETER Force
  If set, overwrite existing module versions.
.PARAMETER ModulePath
  Custom path to save modules (default: ./modules)
.EXAMPLE
  .\bootstrap-modules.ps1 -Force
#>
param(
  [switch]$Force,
  [string]$ModulePath = "modules"
)

function New-Log { param($m,$l='INFO') Write-Host ("[{0}] {1}" -f $l,$m) }


$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# project root is parent of tools folder (string path)
$root = (Resolve-Path (Join-Path $scriptDir '..')).Path
Push-Location $root
$reqPath = Join-Path $root 'requirements.psd1'
if (-not (Test-Path $reqPath)) { Write-Error "requirements.psd1 not found in $root"; exit 1 }

# Import .psd1 safely. Prefer Import-PowerShellDataFile when available (PowerShell 7+), else dot-source.
if (Get-Command Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
  $req = Import-PowerShellDataFile -Path $reqPath
} else {
  # Dot-source the file to get the hashtable it contains
  $req = . $reqPath
}

if (-not $req -or $req.Keys.Count -eq 0) { Write-Error "No modules listed in requirements.psd1"; exit 1 }

$dest = Join-Path $root $ModulePath
if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }

foreach ($k in $req.Keys) {
  $ver = $req[$k]
  New-Log "Processing $k => $ver"
  try {
    # If we already have the exact version in dest, skip unless Force
    $moduleDir = Join-Path $dest $k
    $versionDir = Join-Path $moduleDir $ver
    New-Log ("Checking existing module path: {0}" -f $versionDir)
    if (Test-Path $versionDir -PathType Container) {
      if (-not $Force) {
        New-Log ("{0} {1} already present under {2} - skipping" -f $k, $ver, $versionDir)
        continue
      } else {
        New-Log ("{0} {1} present but Force requested - re-saving" -f $k, $ver)
      }
    }

    # Attempt to save the module. Support wildcard versions like '2.*'
    $targetVersion = $null
    if ($ver -match '\*') {
      New-Log ("Version pattern detected for {0}: {1} - resolving latest matching version from PSGallery" -f $k, $ver)
      if (Get-Command Find-Module -ErrorAction SilentlyContinue) {
        $found = Find-Module -Name $k -Repository PSGallery -AllVersions | Where-Object { $_.Version.ToString() -like $ver } | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
        if ($found) { $targetVersion = $found.Version.ToString() }
        else {
          Write-Host "No exact match found in PSGallery for pattern $ver; will attempt to Save-Module without -RequiredVersion to get latest."
          $targetVersion = $null
        }
      } else {
        Write-Host "Find-Module not available or PSGallery unreachable; will attempt to Save-Module without -RequiredVersion to get latest."
        $targetVersion = $null
      }
    } else {
      $targetVersion = $ver
    }

    New-Log ("Resolved version for {0}: {1}" -f $k, $targetVersion)
    if (-not (Get-Command Save-Module -ErrorAction SilentlyContinue)) {
      Write-Error "Save-Module is not available in this PowerShell session; ensure PowerShellGet is installed."
      continue
    }
    if ($null -ne $targetVersion) {
      if ($Force) {
        New-Log ("Calling Save-Module -Name {0} -RequiredVersion {1} -Path {2} -Force" -f $k, $targetVersion, $dest)
        Save-Module -Name $k -RequiredVersion $targetVersion -Path $dest -Force -ErrorAction Stop
      } else {
        New-Log ("Calling Save-Module -Name {0} -RequiredVersion {1} -Path {2}" -f $k, $targetVersion, $dest)
        Save-Module -Name $k -RequiredVersion $targetVersion -Path $dest -ErrorAction Stop
      }
    } else {
      if ($Force) {
        New-Log ("Calling Save-Module -Name {0} -Path {1} -Force (no RequiredVersion)" -f $k, $dest)
        Save-Module -Name $k -Path $dest -Force -ErrorAction Stop
      } else {
        New-Log ("Calling Save-Module -Name {0} -Path {1} (no RequiredVersion)" -f $k, $dest)
        Save-Module -Name $k -Path $dest -ErrorAction Stop
      }
    }
    New-Log "Saved $k $targetVersion into $dest"
  } catch {
    Write-Error ("Failed to bootstrap module {0}. Error record: {1}" -f $k, ($_ | Out-String))
    Write-Error ("Exception: {0}" -f ($_.Exception | Out-String))
  }
}

Pop-Location
Write-Host "Bootstrap complete. Modules saved to: $dest"
