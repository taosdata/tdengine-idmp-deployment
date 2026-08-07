# Migrate legacy idmp_data layout for IDMP 2.x Docker mounts.
#
# Old compose: idmp_data -> /var/lib/taos  (data under volume/idmp/)
# New compose: idmp_data -> /var/lib/taos/idmp  (data at volume root)
#
# Usage:
#   .\migrate-idmp-data.ps1
#   .\migrate-idmp-data.ps1 -Volume docker_idmp_data
#   .\migrate-idmp-data.ps1 -Helper tdengine/idmp-backend-ee:2.0.0.11
#   .\migrate-idmp-data.ps1 -DryRun

[CmdletBinding()]
param(
  [string]$Volume = "",
  [string]$Helper = "",
  [switch]$DryRun,
  [switch]$Help
)

$ErrorActionPreference = "Stop"
$script:LayoutMarker = ".idmp_volume_layout_v2"

function Write-Log {
  param(
    [ValidateSet("info", "warn", "error")]
    [string]$Level,
    [string]$Message
  )
  switch ($Level) {
    "info"  { Write-Host "[INFO] $Message" -ForegroundColor Green }
    "warn"  { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
    "error" { Write-Host "[ERROR] $Message" -ForegroundColor Red }
  }
}

function Show-Help {
  @"
Usage: migrate-idmp-data.ps1 [-Volume NAME] [-Helper IMAGE] [-DryRun]

Flatten legacy idmp_data volume layout (volume/idmp/* -> volume root)
for IDMP 2.x mounts at /var/lib/taos/idmp.

Parameters:
  -Volume NAME     Docker volume name (auto-detect if omitted)
  -Helper IMAGE    Helper image for docker run (auto-detect if omitted)
  -DryRun          Only probe layout; do not modify the volume
  -Help            Show this help

Environment:
  IDMP_TAG / IDMP_AI_TAG   Used when resolving helper image tags
  COMPOSE_PROJECT_NAME     Used when resolving <project>_idmp_data
"@ | Write-Host
}

function Invoke-Native {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $false)]
    [string[]]$ArgumentList = @(),
    [switch]$Quiet
  )

  $prevErrorAction = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    if ($Quiet) {
      $null = & $FilePath @ArgumentList 2>&1
    }
    else {
      & $FilePath @ArgumentList
    }
    if ($null -eq $LASTEXITCODE) { return 0 }
    return $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $prevErrorAction
  }
}

function Invoke-NativeCapture {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $false)]
    [string[]]$ArgumentList = @()
  )

  $prevErrorAction = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & $FilePath @ArgumentList 2>&1
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    $text = ($output | ForEach-Object { "$_" }) -join [Environment]::NewLine
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $text }
  }
  finally {
    $ErrorActionPreference = $prevErrorAction
  }
}

function Get-EnvOrDefault {
  param(
    [string]$Name,
    [string]$Default = "latest"
  )
  $value = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
  return $value
}

function Test-DockerImageExists {
  param([string]$ImageRef)
  $exitCode = Invoke-Native -FilePath "docker" -ArgumentList @("image", "inspect", $ImageRef) -Quiet
  return ($exitCode -eq 0)
}

function Get-NormalizedComposeProjectName {
  param([string]$Name)
  $normalized = $Name.ToLowerInvariant()
  $normalized = [regex]::Replace($normalized, '[^a-z0-9_-]+', '-')
  $normalized = $normalized.Trim('-')
  return $normalized
}

function Resolve-IdmpDataVolume {
  $containers = @(
    "tdengine-idmp-backend"
    "tdengine-idmp-ui"
    "tdengine-idmp-ai"
    "tdengine-idmp"
  )

  foreach ($containerName in $containers) {
    $inspectResult = Invoke-NativeCapture -FilePath "docker" -ArgumentList @(
      "inspect", "-f", "{{range .Mounts}}{{println .Name .Destination}}{{end}}", $containerName
    )
    if ($inspectResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($inspectResult.Output)) {
      continue
    }

    foreach ($line in ($inspectResult.Output -split "`r?`n")) {
      $parts = ($line.Trim() -split '\s+', 2)
      if ($parts.Count -lt 2) { continue }
      $volumeName = $parts[0]
      $destination = $parts[1]
      if ($destination -eq "/var/lib/taos/idmp" -or $destination -eq "/var/lib/taos") {
        $volCheck = Invoke-Native -FilePath "docker" -ArgumentList @("volume", "inspect", $volumeName) -Quiet
        if ($volCheck -eq 0) {
          return $volumeName
        }
      }
    }
  }

  $projectName = $env:COMPOSE_PROJECT_NAME
  if ([string]::IsNullOrWhiteSpace($projectName)) {
    $projectName = Split-Path -Leaf $PSScriptRoot
  }
  $projectName = Get-NormalizedComposeProjectName $projectName

  foreach ($candidate in @("${projectName}_idmp_data", "idmp_data")) {
    $volCheck = Invoke-Native -FilePath "docker" -ArgumentList @("volume", "inspect", $candidate) -Quiet
    if ($volCheck -eq 0) {
      return $candidate
    }
  }

  $listResult = Invoke-NativeCapture -FilePath "docker" -ArgumentList @("volume", "ls", "-q")
  if ($listResult.ExitCode -eq 0) {
    foreach ($line in ($listResult.Output -split "`r?`n")) {
      $name = $line.Trim()
      if ($name -match '(^|_)idmp_data$') {
        return $name
      }
    }
  }

  return $null
}

function Resolve-VolumeHelperImage {
  $candidates = @(
    "tdengine/idmp-backend-ee:$(Get-EnvOrDefault 'IDMP_TAG')"
    "tdengine/idmp-ai-ee:$(Get-EnvOrDefault 'IDMP_AI_TAG')"
    "alpine:3.20"
    "alpine:latest"
    "busybox:1.36"
    "busybox:latest"
  )

  foreach ($imageRef in $candidates) {
    if (Test-DockerImageExists $imageRef) {
      return $imageRef
    }
  }

  return $null
}

function Invoke-IdmpDataVolumeMigration {
  param(
    [string]$VolumeName,
    [string]$HelperImage,
    [switch]$DryRunOnly
  )

  Write-Log info "Using volume: ${VolumeName}"
  Write-Log info "Using helper image: ${HelperImage}"
  Write-Log info "Checking idmp_data volume layout..."

  $probeScript = @'
marker="__LAYOUT_MARKER__"
if [ -f "/data/${marker}" ]; then
  echo OK
  exit 0
fi
if [ ! -d /data/idmp ] || [ -z "$(ls -A /data/idmp 2>/dev/null)" ]; then
  echo OK
  exit 0
fi
echo NEED_MIGRATE
cd /data
for f in * .[!.]* ..?*; do
  [ -e "$f" ] || continue
  [ "$f" = "idmp" ] && continue
  [ "$f" = "__LAYOUT_MARKER__" ] && continue
  case "$f" in
    _premature_2x_*) continue ;;
  esac
  echo PREMATURE
  break
done
'@
  $probeScript = $probeScript.Replace("__LAYOUT_MARKER__", $script:LayoutMarker)
  $probeScript = $probeScript -replace "`r`n", "`n" -replace "`r", "`n"
  $probeResult = Invoke-NativeCapture -FilePath "docker" -ArgumentList @(
    "run", "--rm", "-u", "0:0", "--entrypoint", "sh",
    "-v", "${VolumeName}:/data:ro",
    $HelperImage, "-c", $probeScript
  )

  if ($probeResult.ExitCode -ne 0) {
    Write-Log error "Failed to probe volume layout (docker run failed)."
    Write-Log error $probeResult.Output
    exit 1
  }

  if ($probeResult.Output -notmatch "NEED_MIGRATE") {
    Write-Log info "No migration needed (already flat, empty, or no nested idmp/ data)."
    return
  }

  Write-Log info "Detected old idmp_data layout (volume previously mounted at /var/lib/taos)."
  if ($probeResult.Output -match "PREMATURE") {
    Write-Log warn "Volume root already has data (likely 2.x started before migration)."
    Write-Log warn "Will move root files aside, then copy legacy nested idmp/ to volume root (keeping idmp/ for rollback)."
  }
  else {
    Write-Log info "Will copy nested idmp/ data to volume root (keeping nested idmp/ for rollback)."
  }

  if ($DryRunOnly) {
    Write-Log info "Dry-run only; no changes made."
    return
  }

  $namesResult = Invoke-NativeCapture -FilePath "docker" -ArgumentList @("ps", "--format", "{{.Names}}")
  $runningNames = @{}
  if ($namesResult.ExitCode -eq 0) {
    foreach ($line in ($namesResult.Output -split "`r?`n")) {
      $name = $line.Trim()
      if (-not [string]::IsNullOrWhiteSpace($name)) {
        $runningNames[$name] = $true
      }
    }
  }

  foreach ($containerName in @("tdengine-idmp-backend", "tdengine-idmp-ui", "tdengine-idmp-ai", "tdengine-idmp")) {
    if ($runningNames.ContainsKey($containerName)) {
      Write-Log info "Stopping ${containerName} for volume migration..."
      [void](Invoke-Native -FilePath "docker" -ArgumentList @("stop", $containerName) -Quiet)
    }
  }

  $migrateScript = @'
set -e
marker="__LAYOUT_MARKER__"
if [ -f "/data/${marker}" ]; then
  echo MIGRATION_SKIP
  exit 0
fi
if [ ! -d /data/idmp ]; then
  echo MIGRATION_SKIP
  exit 0
fi

premature=0
cd /data
for f in * .[!.]* ..?*; do
  [ -e "$f" ] || continue
  [ "$f" = "idmp" ] && continue
  [ "$f" = "__LAYOUT_MARKER__" ] && continue
  case "$f" in
    _premature_2x_*) continue ;;
  esac
  premature=1
  break
done

if [ "$premature" -eq 1 ]; then
  stamp=$(date +%Y%m%d-%H%M%S)
  aside="/data/_premature_2x_${stamp}"
  mkdir -p "$aside"
  cd /data
  for f in * .[!.]* ..?*; do
    [ -e "$f" ] || continue
    [ "$f" = "idmp" ] && continue
    case "$f" in
      _premature_2x_*) continue ;;
    esac
    mv "$f" "$aside/"
  done
  echo "ASIDE:$aside"
fi

cd /data/idmp
for f in * .[!.]* ..?*; do
  [ -e "$f" ] || continue
  if [ -e "/data/$f" ]; then
    echo "CONFLICT:$f"
    rm -rf "/data/$f"
  fi
  if cp -a "$f" /data/ 2>/dev/null; then
    :
  else
    if [ -d "$f" ]; then
      cp -r "$f" /data/
    else
      cp "$f" /data/
    fi
  fi
done
printf "flat-copy\n" > "/data/${marker}"
echo MIGRATION_OK
'@
  $migrateScript = $migrateScript.Replace("__LAYOUT_MARKER__", $script:LayoutMarker)
  $migrateScript = $migrateScript -replace "`r`n", "`n" -replace "`r", "`n"

  $migrateResult = Invoke-NativeCapture -FilePath "docker" -ArgumentList @(
    "run", "--rm", "-u", "0:0", "--entrypoint", "sh",
    "-v", "${VolumeName}:/data",
    $HelperImage, "-c", $migrateScript
  )

  if ($migrateResult.ExitCode -ne 0) {
    Write-Log error "Failed to migrate idmp_data volume (${VolumeName})."
    Write-Log error $migrateResult.Output
    Write-Log error "Original data remains under nested idmp/ for rollback."
    exit 1
  }

  if ($migrateResult.Output -match "CONFLICT:") {
    Write-Log warn "Some root paths already existed and were replaced from nested idmp/."
    Write-Log warn $migrateResult.Output
  }

  if ($migrateResult.Output -match "MIGRATION_OK|MIGRATION_SKIP") {
    Write-Log info "idmp_data volume migration completed (nested idmp/ kept for rollback)."
    if ($migrateResult.Output -match "ASIDE:") {
      Write-Log info "Premature 2.x root data was moved aside (see ASIDE path in migration output)."
      ($migrateResult.Output -split "`r?`n") | Where-Object { $_ -like "ASIDE:*" } | ForEach-Object { Write-Host $_ }
    }
    Write-Log info "Rollback tip: remount idmp_data at /var/lib/taos to use nested idmp/ again."
  }
  else {
    Write-Log error "Unexpected migration result for idmp_data volume."
    Write-Log error $migrateResult.Output
    exit 1
  }
}

if ($Help) {
  Show-Help
  exit 0
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Log error "docker is required"
  exit 1
}

$volumeName = $Volume
if ([string]::IsNullOrWhiteSpace($volumeName)) {
  $volumeName = Resolve-IdmpDataVolume
}
if ([string]::IsNullOrWhiteSpace($volumeName)) {
  Write-Log error "Unable to find idmp_data volume. Pass -Volume NAME."
  exit 1
}
$volCheck = Invoke-Native -FilePath "docker" -ArgumentList @("volume", "inspect", $volumeName) -Quiet
if ($volCheck -ne 0) {
  Write-Log error "Docker volume not found: ${volumeName}"
  exit 1
}

$helperImage = $Helper
if ([string]::IsNullOrWhiteSpace($helperImage)) {
  $helperImage = Resolve-VolumeHelperImage
}
if ([string]::IsNullOrWhiteSpace($helperImage)) {
  Write-Log error "Unable to find a helper image. Pass -Helper IMAGE (e.g. alpine:3.20),"
  Write-Log error "or ensure tdengine/idmp-backend-ee / alpine / busybox exists locally."
  exit 1
}
if (-not (Test-DockerImageExists $helperImage)) {
  Write-Log error "Helper image not found locally: ${helperImage}"
  exit 1
}

Invoke-IdmpDataVolumeMigration -VolumeName $volumeName -HelperImage $helperImage -DryRunOnly:$DryRun
