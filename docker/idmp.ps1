#Requires -Version 5.1
<#
.SYNOPSIS
  IDMP Docker deployment helper (PowerShell port of idmp.sh).

.EXAMPLE
  .\idmp.ps1 start
  .\idmp.ps1 start --mode full
  .\idmp.ps1 start --mode 2
  .\idmp.ps1 stop
  .\idmp.ps1 clean --mode full
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
# Native docker CLI writes diagnostics to stderr; don't treat that as terminating.
if (Test-Path variable:/PSNativeCommandUseErrorActionPreference) {
  $PSNativeCommandUseErrorActionPreference = $false
}

$script:IdmpUrl = "http://localhost:6042"
$script:LicenseServerAddr = "http://localhost:6059"
$script:ComposeFile = "docker-compose.yml"
$script:ComposeCmd = @()
$script:ComposeSupportsPullPolicy = $false
$script:NeedCheckMemory = $false
$script:ModeFromCli = $false
$script:Action = $null
$script:MinDockerMemory = [int64]10737418240  # 10GB in bytes

function Write-Log {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("info", "warn", "error")]
    [string]$Level,
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  switch ($Level) {
    "info"  { Write-Host "[INFO] $Message" -ForegroundColor Green }
    "warn"  { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
    "error" { Write-Host "[ERROR] $Message" -ForegroundColor Red }
  }
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
    return @{
      ExitCode = $exitCode
      Output   = $text
    }
  }
  finally {
    $ErrorActionPreference = $prevErrorAction
  }
}

function Show-Help {
  $scriptName = Split-Path -Leaf $PSCommandPath
  Write-Host "Usage: .\$scriptName [COMMAND] [OPTIONS]"
  Write-Host ""
  Write-Host "Commands:"
  Write-Host ("  start`t`t`tStart the IDMP services")
  Write-Host ("  stop`t`t`tStop the IDMP services")
  Write-Host ("  clean`t`t`tClean the current IDMP environment")
  Write-Host ""
  Write-Host "Options:"
  Write-Host ("  --mode MODE`t`tDeployment mode: 1|standard or 2|full (skip interactive prompt)")
  Write-Host ("  -h, --help`t`tShow this help message")
  Write-Host ""
  Write-Host "Examples:"
  Write-Host ("  .\$scriptName start`t`t`t# Start with interactive mode")
  Write-Host ("  .\$scriptName start --mode full`t`t# Start Full deployment (TSDB + IDMP + TDgpt + CLS + TDModel)")
  Write-Host ("  .\$scriptName start --mode 2`t`t# Same as --mode full")
  Write-Host ("  .\$scriptName start --mode standard`t# Start Standard deployment (TSDB + IDMP)")
  Write-Host ("  .\$scriptName stop`t`t`t# Stop services")
  Write-Host ("  .\$scriptName clean --mode full`t`t# Clean Full deployment environment")
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

function Apply-DeployMode {
  param([string]$Mode)

  switch -Regex ($Mode.ToLowerInvariant()) {
    "^(1|standard)$" {
      $script:ComposeFile = "docker-compose.yml"
      $script:NeedCheckMemory = $false
      Write-Log info "Selected: Standard deployment (TSDB Enterprise + IDMP + CLS)"
    }
    "^(2|full)$" {
      $script:ComposeFile = "docker-compose-tdgpt.yml"
      $script:NeedCheckMemory = $true
      Write-Log info "Selected: Full deployment (TSDB Enterprise + IDMP + TDgpt + CLS + TDModel)"
    }
    default {
      Write-Log error "Invalid mode: $Mode (use 1|standard or 2|full)"
      exit 1
    }
  }
}

function Parse-Arguments {
  param([string[]]$ArgsList)

  if ($null -eq $ArgsList -or $ArgsList.Count -eq 0) {
    Write-Log error "No command provided."
    Write-Host ""
    Show-Help
    exit 1
  }

  $i = 0
  while ($i -lt $ArgsList.Count) {
    $arg = $ArgsList[$i]
    switch -Regex ($arg) {
      "^(start|stop|clean)$" {
        $script:Action = $arg
        $i++
      }
      "^--mode$" {
        if ($i + 1 -ge $ArgsList.Count -or [string]::IsNullOrWhiteSpace($ArgsList[$i + 1])) {
          Write-Log error "--mode requires a value: 1|standard or 2|full"
          exit 1
        }
        Apply-DeployMode $ArgsList[$i + 1]
        $script:ModeFromCli = $true
        $i += 2
      }
      "^--mode=.+" {
        Apply-DeployMode ($arg.Substring(7))
        $script:ModeFromCli = $true
        $i++
      }
      "^(-h|--help)$" {
        Show-Help
        exit 0
      }
      default {
        Write-Log error "Unknown option: $arg"
        Show-Help
        exit 1
      }
    }
  }
}

function Invoke-Compose {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$ComposeArgs
  )

  Push-Location $PSScriptRoot
  try {
    $exe = $script:ComposeCmd[0]
    $prefixArgs = @()
    if ($script:ComposeCmd.Count -gt 1) {
      $prefixArgs = $script:ComposeCmd[1..($script:ComposeCmd.Count - 1)]
    }
    return (Invoke-Native -FilePath $exe -ArgumentList ($prefixArgs + $ComposeArgs))
  }
  finally {
    Pop-Location
  }
}

function Test-CommandExists {
  param([string]$Name)
  return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-DockerDaemonReady {
  $result = Invoke-NativeCapture -FilePath "docker" -ArgumentList @("info")
  return ($result.ExitCode -eq 0)
}

function Get-DockerDesktopPath {
  $candidates = @(
    (Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe")
    (Join-Path ${env:ProgramFiles(x86)} "Docker\Docker\Docker Desktop.exe")
    (Join-Path $env:LOCALAPPDATA "Docker\Docker Desktop.exe")
  )

  foreach ($path in $candidates) {
    if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
      return $path
    }
  }
  return $null
}

function Start-DockerDesktopIfNeeded {
  $isWindowsHost = ($env:OS -eq "Windows_NT")
  if (-not $isWindowsHost) {
    return $false
  }

  $desktopProcess = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
  if ($null -ne $desktopProcess) {
    Write-Log info "Docker Desktop process is already running, waiting for daemon..."
    return $true
  }

  $desktopPath = Get-DockerDesktopPath
  if ($null -eq $desktopPath) {
    Write-Log warn "Docker Desktop executable not found in default install locations."
    return $false
  }

  Write-Log info "Starting Docker Desktop: $desktopPath"
  try {
    Start-Process -FilePath $desktopPath | Out-Null
    return $true
  }
  catch {
    Write-Log warn "Failed to start Docker Desktop: $($_.Exception.Message)"
    return $false
  }
}

function Wait-DockerDaemon {
  param(
    [int]$TimeoutSeconds = 120,
    [int]$IntervalSeconds = 3
  )

  $elapsed = 0
  while ($elapsed -lt $TimeoutSeconds) {
    if (Test-DockerDaemonReady) {
      Write-Log info "Docker daemon is ready."
      return $true
    }
    Start-Sleep -Seconds $IntervalSeconds
    $elapsed += $IntervalSeconds
    if (($elapsed % 15) -eq 0 -or $elapsed -ge $TimeoutSeconds) {
      Write-Log info "Waiting for Docker daemon... (${elapsed}s / ${TimeoutSeconds}s)"
    }
  }
  return $false
}

function Check-DockerDaemon {
  if (Test-DockerDaemonReady) {
    return
  }

  Write-Log warn "Docker daemon is not running or not reachable."
  $started = Start-DockerDesktopIfNeeded
  if (-not $started) {
    Write-Log error "Please start Docker Desktop (or the Docker service) manually and try again."
    exit 1
  }

  if (-not (Wait-DockerDaemon -TimeoutSeconds 120 -IntervalSeconds 3)) {
    Write-Log error "Timed out waiting for Docker daemon to become ready."
    Write-Log error "Please confirm Docker Desktop is running, then try again."
    exit 1
  }
}

function Check-DockerCompose {
  if ((Test-CommandExists "docker")) {
    $exitCode = Invoke-Native -FilePath "docker" -ArgumentList @("compose", "version") -Quiet
    if ($exitCode -eq 0) {
      $script:ComposeCmd = @("docker", "compose")
      $script:ComposeSupportsPullPolicy = $true
      Write-Log info "Found docker compose plugin"
      Check-DockerDaemon
      return
    }
  }

  if (Test-CommandExists "docker-compose") {
    $exitCode = Invoke-Native -FilePath "docker-compose" -ArgumentList @("version") -Quiet
    if ($exitCode -eq 0) {
      $script:ComposeCmd = @("docker-compose")
      $script:ComposeSupportsPullPolicy = $false
      Write-Log info "Found docker-compose command"
      Check-DockerDaemon
      return
    }
  }

  Write-Log error "Neither 'docker-compose' nor 'docker compose' command found!"
  Write-Log error "Please install Docker Compose first"
  exit 1
}

function Check-DockerMemory {
  $result = Invoke-NativeCapture -FilePath "docker" -ArgumentList @("info", "--format", "{{.MemTotal}}")
  $memLimitText = $result.Output
  if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($memLimitText)) {
    Write-Log warn "Unable to detect Docker memory limit, please ensure Docker is running."
    exit 1
  }

  [int64]$memLimit = 0
  if (-not [int64]::TryParse($memLimitText.Trim(), [ref]$memLimit) -or $memLimit -eq 0) {
    Write-Log warn "Unable to detect Docker memory limit, please ensure Docker is running."
    exit 1
  }

  $memGb = [int]($memLimit / 1GB)
  if ($memLimit -lt $script:MinDockerMemory) {
    Write-Log warn "Docker memory limit is less than 10GB (current: ${memGb}GB)."
    Write-Log warn "Please increase Docker's memory limit to at least 10GB and try again."
    exit 1
  }

  Write-Log info "Docker memory limit check passed: ${memGb}GB"
}

function Select-ComposeMode {
  if ($script:ModeFromCli) {
    return
  }

  Write-Host "Please select deployment mode:" -ForegroundColor Green
  Write-Host "1) Standard deployment (TSDB Enterprise + IDMP + CLS) (docker-compose.yml)"
  Write-Host "2) Full deployment (TSDB Enterprise + IDMP + TDgpt + CLS + TDModel) (docker-compose-tdgpt.yml)"

  while ($true) {
    Write-Host -NoNewline "Enter your choice [1-2]: " -ForegroundColor Green
    $modeChoice = Read-Host
    switch ($modeChoice) {
      { $_ -in @("1", "") } {
        Apply-DeployMode "1"
        return
      }
      "2" {
        Apply-DeployMode "2"
        return
      }
      default {
        Write-Host "Invalid choice. Please enter 1 or 2." -ForegroundColor Yellow
      }
    }
  }
}

function Get-HostIpAddress {
  try {
    $addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
      Where-Object {
        $_.IPAddress -ne "127.0.0.1" -and
        $_.PrefixOrigin -ne "WellKnown" -and
        $_.InterfaceAlias -notmatch "^(Loopback|vEthernet|Docker|WSL|Hyper-V|br-|veth)"
      } |
      Sort-Object -Property InterfaceMetric |
      Select-Object -ExpandProperty IPAddress

    if ($addresses) {
      return $addresses | Select-Object -First 1
    }
  }
  catch {
    # Fallback below
  }

  try {
    $candidates = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
      Where-Object { $_.IPAddress -ne "127.0.0.1" } |
      Select-Object -ExpandProperty IPAddress
    if ($candidates) {
      return $candidates | Select-Object -First 1
    }
  }
  catch {
    return $null
  }

  return $null
}

function Test-Ipv4Address {
  param([string]$Ip)
  return $Ip -match '^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$'
}

function Setup-Url {
  $hostIp = Get-HostIpAddress
  if ($null -ne $hostIp -and (Test-Ipv4Address $hostIp)) {
    $script:IdmpUrl = "http://${hostIp}:6042"
  }
  elseif ($null -ne $hostIp) {
    Write-Log warn "Failed to detect a valid IP address: $hostIp"
  }
  else {
    Write-Log warn "Unable to detect host IP. Using default URL."
  }

  while ($true) {
    Write-Host -NoNewline "Do you want to use this URL to access IDMP web console? $($script:IdmpUrl) [Y/n] " -ForegroundColor Green
    $useDefaultUrl = Read-Host
    if ([string]::IsNullOrWhiteSpace($useDefaultUrl) -or $useDefaultUrl -match '^[Yy]$') {
      break
    }
    elseif ($useDefaultUrl -match '^[Nn]$') {
      Write-Host -NoNewline "Please input IDMP URL (http://<ip>:6042): " -ForegroundColor Green
      $newIdmpUrl = Read-Host
      if (-not [string]::IsNullOrWhiteSpace($newIdmpUrl)) {
        $script:IdmpUrl = $newIdmpUrl
      }
      break
    }
    else {
      Write-Host "Please enter y, n, or press Enter (default Y)." -ForegroundColor Yellow
    }
  }

  Write-Log info "IDMP Server URL: $($script:IdmpUrl)"
}

function Setup-LicenseServerAddr {
  if ($script:IdmpUrl -match '^(https?://[^:/]+)(:[0-9]+)?(/.*)?$') {
    $script:LicenseServerAddr = "$($Matches[1]):6059"
  }
  else {
    $script:LicenseServerAddr = "http://localhost:6059"
  }

  while ($true) {
    Write-Host -NoNewline "Do you want to use this URL for license server ? $($script:LicenseServerAddr) [Y/n] " -ForegroundColor Green
    $useDefaultLicense = Read-Host
    if ([string]::IsNullOrWhiteSpace($useDefaultLicense) -or $useDefaultLicense -match '^[Yy]$') {
      break
    }
    elseif ($useDefaultLicense -match '^[Nn]$') {
      Write-Host -NoNewline "Please input license server URL (http://<ip>:6059): " -ForegroundColor Green
      $newLicenseServerAddr = Read-Host
      if (-not [string]::IsNullOrWhiteSpace($newLicenseServerAddr)) {
        $script:LicenseServerAddr = $newLicenseServerAddr
      }
      break
    }
    else {
      Write-Host "Please enter y, n, or press Enter (default Y)." -ForegroundColor Yellow
    }
  }

  Write-Log info "License Server URL: $($script:LicenseServerAddr)"
}

function Test-DockerImageExists {
  param([string]$ImageRef)
  $exitCode = Invoke-Native -FilePath "docker" -ArgumentList @("image", "inspect", $ImageRef) -Quiet
  return ($exitCode -eq 0)
}

function Check-AndUpgradeImages {
  $images = @(
    "tdengine/tsdb-ee:$(Get-EnvOrDefault 'TSDB_TAG')"
    "tdengine/idmp-backend-ee:$(Get-EnvOrDefault 'IDMP_TAG')"
    "tdengine/idmp-ui-ee:$(Get-EnvOrDefault 'IDMP_TAG')"
    "tdengine/idmp-ai-ee:$(Get-EnvOrDefault 'IDMP_AI_TAG')"
    "tdengine/cls:$(Get-EnvOrDefault 'CLS_TAG')"
  )

  if ($script:ComposeFile -eq "docker-compose-tdgpt.yml") {
    $images += "tdengine/tdgpt-full:$(Get-EnvOrDefault 'TDGPT_TAG')"
    $images += "tdengine/tdmodel:$(Get-EnvOrDefault 'TDMODEL_TAG')"
  }

  Write-Log info "Checking local images..."

  $missingImages = New-Object System.Collections.Generic.List[string]
  $existingImages = New-Object System.Collections.Generic.List[string]

  foreach ($imageRef in $images) {
    if (-not (Test-DockerImageExists $imageRef)) {
      $missingImages.Add($imageRef) | Out-Null
    }
    else {
      $existingImages.Add($imageRef) | Out-Null
    }
  }

  if ($missingImages.Count -gt 0) {
    Write-Host "The following images do not exist locally and will be pulled by Docker Compose on start:" -ForegroundColor Yellow
    foreach ($imageRef in $missingImages) {
      Write-Host "  - $imageRef"
    }
  }

  if ($existingImages.Count -eq 0) {
    return
  }

  Write-Host "The following images already exist locally:" -ForegroundColor Yellow
  foreach ($imageRef in $existingImages) {
    Write-Host "  - $imageRef"
  }

  while ($true) {
    Write-Host -NoNewline "Do you want to update existing images? [Y/n] " -ForegroundColor Green
    $upgradeChoice = Read-Host
    if ([string]::IsNullOrWhiteSpace($upgradeChoice) -or $upgradeChoice -match '^[Yy]$') {
      Write-Log info "Pulling latest images with Docker Compose..."
      if ($script:ComposeSupportsPullPolicy) {
        [void](Invoke-Compose -ComposeArgs @("-f", $script:ComposeFile, "pull", "--policy", "always"))
      }
      else {
        [void](Invoke-Compose -ComposeArgs @("-f", $script:ComposeFile, "pull"))
      }
      break
    }
    elseif ($upgradeChoice -match '^[Nn]$') {
      Write-Log info "Skipping update, using existing images."
      break
    }
    else {
      Write-Host "Please enter y, n, or press Enter (default Y)." -ForegroundColor Yellow
    }
  }
}

function Ask-GitEnable {
  while ($true) {
    Write-Host -NoNewline "Do you want to disable git version control (experimental)? [Y/n] " -ForegroundColor Green
    $gitChoice = Read-Host
    if ([string]::IsNullOrWhiteSpace($gitChoice) -or $gitChoice -match '^[Yy]$') {
      $env:TDA_GIT_ENABLE = "false"
      Write-Log info "Git version control disabled."
      break
    }
    elseif ($gitChoice -match '^[Nn]$') {
      $env:TDA_GIT_ENABLE = "true"
      Write-Log info "Git version control enabled."
      break
    }
    else {
      Write-Host "Please enter y, n, or press Enter (default Y, y disables)." -ForegroundColor Yellow
    }
  }
}

function Setup-Timezone {
  # Keep explicit TZ from environment or .env if already set
  if (-not [string]::IsNullOrWhiteSpace($env:TZ)) {
    Write-Log info "Using existing TZ: $($env:TZ)"
    return
  }

  $detectedTz = $null

  # .NET 6+ / PowerShell 7+: convert Windows timezone ID to IANA
  try {
    $ianaId = $null
    $ok = [TimeZoneInfo]::TryConvertWindowsIdToIanaId([TimeZoneInfo]::Local.Id, [ref]$ianaId)
    if ($ok -and -not [string]::IsNullOrWhiteSpace($ianaId)) {
      $detectedTz = $ianaId
    }
  }
  catch {
    # Method unavailable on older .NET / Windows PowerShell 5.1
  }

  # Common Windows -> IANA fallbacks for Windows PowerShell 5.1
  if ([string]::IsNullOrWhiteSpace($detectedTz)) {
    $windowsToIana = @{
      "China Standard Time"           = "Asia/Shanghai"
      "Taipei Standard Time"          = "Asia/Taipei"
      "Tokyo Standard Time"           = "Asia/Tokyo"
      "Korea Standard Time"           = "Asia/Seoul"
      "Singapore Standard Time"       = "Asia/Singapore"
      "SE Asia Standard Time"         = "Asia/Bangkok"
      "India Standard Time"           = "Asia/Kolkata"
      "GMT Standard Time"             = "Europe/London"
      "W. Europe Standard Time"       = "Europe/Berlin"
      "Central Europe Standard Time"  = "Europe/Budapest"
      "Romance Standard Time"         = "Europe/Paris"
      "Russian Standard Time"         = "Europe/Moscow"
      "Eastern Standard Time"         = "America/New_York"
      "Central Standard Time"         = "America/Chicago"
      "Mountain Standard Time"        = "America/Denver"
      "Pacific Standard Time"         = "America/Los_Angeles"
      "UTC"                           = "UTC"
    }
    $windowsId = [TimeZoneInfo]::Local.Id
    if ($windowsToIana.ContainsKey($windowsId)) {
      $detectedTz = $windowsToIana[$windowsId]
    }
  }

  if ([string]::IsNullOrWhiteSpace($detectedTz)) {
    $detectedTz = "UTC"
    Write-Log warn "Unable to detect system timezone, falling back to UTC"
  }

  $env:TZ = $detectedTz
  Write-Log info "Timezone set to: $($env:TZ)"
}

# Old compose mounted idmp_data at /var/lib/taos (data lived in volume/idmp/).
# New compose mounts idmp_data at /var/lib/taos/idmp (data at volume root).
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

  Write-Log info "Pulling alpine:3.20 for idmp_data volume migration..."
  $pullExit = Invoke-Native -FilePath "docker" -ArgumentList @("pull", "alpine:3.20") -Quiet
  if ($pullExit -eq 0) {
    return "alpine:3.20"
  }

  $fallbackImages = @(
    "tdengine/idmp-backend-ee:$(Get-EnvOrDefault 'IDMP_TAG')"
    "tdengine/idmp-ai-ee:$(Get-EnvOrDefault 'IDMP_AI_TAG')"
  )
  foreach ($imageRef in $fallbackImages) {
    if (Test-DockerImageExists $imageRef) {
      return $imageRef
    }
  }

  return $null
}

function Invoke-IdmpDataVolumeMigrationIfNeeded {
  $volumeName = Resolve-IdmpDataVolume
  if ([string]::IsNullOrWhiteSpace($volumeName)) {
    return
  }

  $helperImage = Resolve-VolumeHelperImage
  if ([string]::IsNullOrWhiteSpace($helperImage)) {
    Write-Log warn "Unable to find a helper image to inspect idmp_data; skipping volume migration check."
    return
  }

  Write-Log info "Checking idmp_data volume layout (${volumeName})..."
  $probeScript = @'
if [ -d /data/idmp ] && [ -n "$(ls -A /data/idmp 2>/dev/null)" ]; then
  echo NEED_MIGRATE
else
  echo OK
fi
'@
  $probeScript = $probeScript -replace "`r`n", "`n" -replace "`r", "`n"
  $probeResult = Invoke-NativeCapture -FilePath "docker" -ArgumentList @(
    "run", "--rm", "--entrypoint", "sh",
    "-v", "${volumeName}:/data:ro",
    $helperImage, "-c", $probeScript
  )

  if ($probeResult.Output -notmatch "NEED_MIGRATE") {
    return
  }

  Write-Log info "Detected old idmp_data layout (volume previously mounted at /var/lib/taos)."
  Write-Log info "Migrating data to new layout (volume mounted at /var/lib/taos/idmp)..."

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
if [ ! -d /data/idmp ]; then
  echo MIGRATION_SKIP
  exit 0
fi
cd /data/idmp
for f in * .[!.]* ..?*; do
  [ -e "$f" ] || continue
  if [ -e "/data/$f" ]; then
    echo "CONFLICT:$f"
    continue
  fi
  mv "$f" /data/
done
cd /data
if [ -z "$(ls -A /data/idmp 2>/dev/null)" ]; then
  rmdir /data/idmp 2>/dev/null || rm -rf /data/idmp
else
  echo "WARN: leftover files remain under nested idmp/"
fi
echo MIGRATION_OK
'@
  $migrateScript = $migrateScript -replace "`r`n", "`n" -replace "`r", "`n"

  $migrateResult = Invoke-NativeCapture -FilePath "docker" -ArgumentList @(
    "run", "--rm", "--entrypoint", "sh",
    "-v", "${volumeName}:/data",
    $helperImage, "-c", $migrateScript
  )

  if ($migrateResult.ExitCode -ne 0) {
    Write-Log error "Failed to migrate idmp_data volume (${volumeName})."
    Write-Log error $migrateResult.Output
    exit 1
  }

  if ($migrateResult.Output -match "CONFLICT:") {
    Write-Log warn "Some files already existed at volume root and were kept; nested copies may remain."
    Write-Log warn $migrateResult.Output
  }

  if ($migrateResult.Output -match "MIGRATION_OK|MIGRATION_SKIP") {
    Write-Log info "idmp_data volume migration completed."
  }
  else {
    Write-Log error "Unexpected migration result for idmp_data volume."
    Write-Log error $migrateResult.Output
    exit 1
  }
}

function Start-Services {
  Check-DockerCompose
  Select-ComposeMode
  Check-AndUpgradeImages
  Setup-Url
  Setup-LicenseServerAddr
  Ask-GitEnable
  Setup-Timezone

  $env:IDMP_URL = $script:IdmpUrl
  $env:TDA_LICENSE_SERVER_ADDR = $script:LicenseServerAddr

  if ($script:NeedCheckMemory) {
    Check-DockerMemory
  }

  Invoke-IdmpDataVolumeMigrationIfNeeded
  Remove-LegacyIdmpContainer

  $upArgs = [System.Collections.Generic.List[string]]::new()
  $upArgs.AddRange([string[]]@("-f", $script:ComposeFile, "up", "-d"))
  if (Test-ComposeServicesExist) {
    Write-Log info "Existing services detected, forcing recreate..."
    $upArgs.Add("--force-recreate") | Out-Null
  }
  if ($script:ComposeSupportsPullPolicy) {
    $upArgs.AddRange([string[]]@("--pull", "missing"))
  }

  Write-Log info "Starting services with $($script:ComposeFile)..."
  $ret = Invoke-Compose -ComposeArgs $upArgs.ToArray()

  if ($ret -eq 0) {
    Write-Log info "Services started successfully!"
    Write-Log info "IDMP Web Console: $($script:IdmpUrl)"
    Write-Log info "License Server: $($script:LicenseServerAddr)"
  }
  else {
    Write-Host "Failed to start services. Please check the logs." -ForegroundColor Yellow
  }
}

function Test-ComposeServicesExist {
  if ($script:ComposeFile -eq "docker-compose-tdgpt.yml") {
    $names = @(
      "tdengine-tdgpt"
      "tdengine-tsdb"
      "tdengine-idmp-backend"
      "tdengine-idmp-ui"
      "tdengine-idmp-ai"
      "tdengine-idmp"
      "tdengine-model"
      "tdengine-cls"
    )
  }
  else {
    $names = @(
      "tdengine-tsdb"
      "tdengine-idmp-backend"
      "tdengine-idmp-ui"
      "tdengine-idmp-ai"
      "tdengine-idmp"
      "tdengine-cls"
    )
  }

  $result = Invoke-NativeCapture -FilePath "docker" -ArgumentList @("ps", "-a", "--format", "{{.Names}}")
  if ($result.ExitCode -ne 0) {
    return $false
  }

  $existing = @{}
  foreach ($line in ($result.Output -split "`r?`n")) {
    $name = $line.Trim()
    if (-not [string]::IsNullOrWhiteSpace($name)) {
      $existing[$name] = $true
    }
  }

  foreach ($name in $names) {
    if ($existing.ContainsKey($name)) {
      return $true
    }
  }
  return $false
}

# Pre-split monolith container from older compose files; not in current compose.
function Remove-LegacyIdmpContainer {
  $result = Invoke-NativeCapture -FilePath "docker" -ArgumentList @("ps", "-a", "--format", "{{.Names}}")
  if ($result.ExitCode -ne 0) {
    return
  }

  $found = $false
  foreach ($line in ($result.Output -split "`r?`n")) {
    if ($line.Trim() -eq "tdengine-idmp") {
      $found = $true
      break
    }
  }

  if (-not $found) {
    return
  }

  Write-Log info "Removing legacy container tdengine-idmp..."
  [void](Invoke-Native -FilePath "docker" -ArgumentList @("rm", "-f", "tdengine-idmp") -Quiet)
}

function Detect-ComposeFile {
  $runningResult = Invoke-NativeCapture -FilePath "docker" -ArgumentList @("ps", "-q")
  if ($runningResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($runningResult.Output.Trim())) {
    Write-Log warn "No running containers found"
    return $false
  }

  $namesResult = Invoke-NativeCapture -FilePath "docker" -ArgumentList @("ps", "--format", "{{.Names}}")
  $nameSet = @{}
  foreach ($line in ($namesResult.Output -split "`r?`n")) {
    $name = $line.Trim()
    if (-not [string]::IsNullOrWhiteSpace($name)) {
      $nameSet[$name] = $true
    }
  }

  if ($nameSet.ContainsKey("tdengine-tdgpt")) {
    $script:ComposeFile = "docker-compose-tdgpt.yml"
    Write-Log info "Detected TDgpt containers, using: $($script:ComposeFile)"
    return $true
  }

  $standardNames = @(
    "tdengine-idmp-backend"
    "tdengine-idmp-ui"
    "tdengine-idmp-ai"
    "tdengine-idmp"
    "tdengine-tsdb"
    "tdengine-cls"
  )
  foreach ($name in $standardNames) {
    if ($nameSet.ContainsKey($name)) {
      $script:ComposeFile = "docker-compose.yml"
      Write-Log info "Detected standard deployment containers, using: $($script:ComposeFile)"
      return $true
    }
  }

  Write-Log warn "No IDMP related containers found"
  return $false
}

function Stop-Services {
  Check-DockerCompose

  if (-not (Detect-ComposeFile)) {
    Write-Log warn "Could not detect any running IDMP services."
    return
  }

  Write-Log info "Stopping services with $($script:ComposeFile)..."
  $ret = 1
  while ($true) {
    Write-Host -NoNewline "Do you want to clear data and logs? [y/N] " -ForegroundColor Green
    $cleanVolumes = Read-Host
    if ($cleanVolumes -match '^[Yy]$') {
      Write-Log info "Stopping services and cleaning volumes ..."
      $ret = Invoke-Compose -ComposeArgs @("-f", $script:ComposeFile, "down", "-v")
      break
    }
    elseif ([string]::IsNullOrWhiteSpace($cleanVolumes) -or $cleanVolumes -match '^[Nn]$') {
      Write-Log info "Stopping services without cleaning volumes..."
      $ret = Invoke-Compose -ComposeArgs @("-f", $script:ComposeFile, "down")
      break
    }
    else {
      Write-Host "Please enter y, n, or press Enter (default N)." -ForegroundColor Yellow
    }
  }

  # New compose no longer defines tdengine-idmp; remove it explicitly on upgrade/stop.
  Remove-LegacyIdmpContainer

  if ($ret -eq 0) {
    Write-Log info "Services stopped successfully!"
  }
  else {
    Write-Log error "Failed to stop services. Please check the logs."
  }
}

function Clean-Environment {
  Check-DockerCompose
  Select-ComposeMode

  $composeFiles = @($script:ComposeFile)
  $containerNames = @(
    "tdengine-tsdb"
    "tdengine-idmp-backend"
    "tdengine-idmp-ui"
    "tdengine-idmp-ai"
    "tdengine-idmp"
    "tdengine-cls"
  )
  $volumeNames = @(
    "tsdb_data"
    "tsdb_log"
    "idmp_data"
    "idmp_log"
    "cls_data"
    "cls_log"
  )
  $networkNames = @("taos_net")
  $candidateImages = @(
    "tdengine/tsdb-ee:$(Get-EnvOrDefault 'TSDB_TAG')"
    "tdengine/idmp-backend-ee:$(Get-EnvOrDefault 'IDMP_TAG')"
    "tdengine/idmp-ui-ee:$(Get-EnvOrDefault 'IDMP_TAG')"
    "tdengine/idmp-ai-ee:$(Get-EnvOrDefault 'IDMP_AI_TAG')"
    "tdengine/cls:$(Get-EnvOrDefault 'CLS_TAG')"
  )

  if ($script:ComposeFile -eq "docker-compose-tdgpt.yml") {
    $containerNames = @(
      "tdengine-tdgpt"
      "tdengine-tsdb"
      "tdengine-idmp-backend"
      "tdengine-idmp-ui"
      "tdengine-idmp-ai"
      "tdengine-idmp"
      "tdengine-model"
      "tdengine-cls"
    )
    $volumeNames += @("tdmodel_data", "tdmodel_mysql", "tdmodel_log")
    $candidateImages += @(
      "tdengine/tdgpt-full:$(Get-EnvOrDefault 'TDGPT_TAG')"
      "tdengine/tdmodel:$(Get-EnvOrDefault 'TDMODEL_TAG')"
    )
  }

  foreach ($containerName in $containerNames) {
    $inspectResult = Invoke-NativeCapture -FilePath "docker" -ArgumentList @("inspect", "--format", "{{.Config.Image}}", $containerName)
    if ($inspectResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($inspectResult.Output)) {
      $candidateImages += $inspectResult.Output.Trim()
    }
  }

  $images = New-Object System.Collections.Generic.List[string]
  foreach ($imageRef in $candidateImages) {
    if ([string]::IsNullOrWhiteSpace($imageRef)) { continue }
    if (-not (Test-DockerImageExists $imageRef)) { continue }
    if (-not $images.Contains($imageRef)) {
      $images.Add($imageRef) | Out-Null
    }
  }

  Write-Host "This will remove containers, volumes, and images for the IDMP environment." -ForegroundColor Yellow
  Write-Host "Compose files used:" -ForegroundColor Yellow
  foreach ($composeFileRef in $composeFiles) {
    Write-Host "  - $composeFileRef"
  }

  Write-Host "Containers managed by this environment:" -ForegroundColor Yellow
  foreach ($containerName in $containerNames) {
    Write-Host "  - $containerName"
  }

  Write-Host "Compose volumes to remove:" -ForegroundColor Yellow
  foreach ($volumeName in $volumeNames) {
    Write-Host "  - $volumeName"
  }

  Write-Host "Compose networks to remove:" -ForegroundColor Yellow
  foreach ($networkName in $networkNames) {
    Write-Host "  - $networkName"
  }

  if ($images.Count -gt 0) {
    Write-Host "The following images will be removed:" -ForegroundColor Yellow
    foreach ($imageRef in $images) {
      Write-Host "  - $imageRef"
    }
  }
  else {
    Write-Log info "No local IDMP images found to remove."
  }

  while ($true) {
    Write-Host -NoNewline "Do you want to clean the entire current environment? [y/N] " -ForegroundColor Green
    $cleanChoice = Read-Host
    if ($cleanChoice -match '^[Yy]$') {
      break
    }
    elseif ([string]::IsNullOrWhiteSpace($cleanChoice) -or $cleanChoice -match '^[Nn]$') {
      Write-Log info "Clean canceled."
      return
    }
    else {
      Write-Host "Please enter y, n, or press Enter (default N)." -ForegroundColor Yellow
    }
  }

  foreach ($composeFileRef in $composeFiles) {
    Write-Log info "Removing services and volumes with $composeFileRef..."
    $ret = Invoke-Compose -ComposeArgs @("-f", $composeFileRef, "down", "-v")
    if ($ret -ne 0) {
      Write-Log error "Failed to remove services and volumes with $composeFileRef. Please check the logs."
      return
    }
  }

  Remove-LegacyIdmpContainer

  foreach ($imageRef in $images) {
    Write-Log info "Removing image $imageRef..."
    $rmExit = Invoke-Native -FilePath "docker" -ArgumentList @("image", "rm", $imageRef) -Quiet
    if ($rmExit -ne 0) {
      Write-Log warn "Failed to remove image $imageRef, it may not exist or may still be in use."
    }
  }

  Write-Log info "Current IDMP environment cleaned successfully!"
}

# main
Parse-Arguments $args

switch ($script:Action) {
  "start" { Start-Services }
  "stop"  { Stop-Services }
  "clean" { Clean-Environment }
  default {
    Write-Log error "Unknown action: $($script:Action)"
    Show-Help
    exit 1
  }
}
