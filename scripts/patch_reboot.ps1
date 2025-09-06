# patch_reboot.ps1
# Run as Administrator
param(
  [switch]$DryRun
)

$LogDir = "C:\patch_scheduler\logs"
$LogFile = Join-Path $LogDir "patch_reboot.log"
$Retries = 2
$SleepBetween = 60 # seconds
$SlackWebhook = $env:SLACK_WEBHOOK
$AdminEmail = $env:ADMIN_EMAIL

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Log($msg) {
    $line = "$(Get-Date -Format o) | $msg"
    $line | Tee-Object -FilePath $LogFile -Append
}

function Send-Slack($msg) {
    if (-not $env:SLACK_WEBHOOK) { return }
    $payload = @{ text = $msg } | ConvertTo-Json
    Invoke-RestMethod -Uri $env:SLACK_WEBHOOK -Method Post -ContentType 'application/json' -Body $payload -ErrorAction SilentlyContinue
}

# Ensure PSWindowsUpdate module is available
try {
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop
        Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction Stop
    }
    Import-Module PSWindowsUpdate -ErrorAction Stop
} catch {
    Log "ERROR: Unable to install/import PSWindowsUpdate. $_"
    Send-Slack "ERROR: PSWindowsUpdate missing on $(hostname)"
    exit 1
}

$attempt = 0
while ($attempt -le $Retries) {
    $attempt++
    Log "Attempt #$attempt: Starting Windows update (DryRun=$DryRun)"
    try {
        if ($DryRun) {
            Log "Dry run: listing available updates..."
            Get-WindowsUpdate -MicrosoftUpdate -Verbose | Out-String | Tee-Object -FilePath $LogFile -Append
            $rc = 0
        } else {
            # Install and auto reboot if required
            Install-WindowsUpdate -AcceptAll -AutoReboot -MicrosoftUpdate -Verbose -Confirm:$false
            $rc = 0
        }
    } catch {
        Log "ERROR: Update/install failed: $_"
        $rc = 1
    }

    if ($rc -eq 0) {
        Log "Patch attempt #$attempt SUCCESS."
        Send-Slack "Patch succeeded on $(hostname) (attempt $attempt)."
        if (-not $DryRun) {
            # If Install-WindowsUpdate triggers reboot itself, this may be unnecessary.
            Log "If needed, a reboot will occur automatically from the update command."
        }
        exit 0
    } else {
        Log "Patch attempt #$attempt FAILED."
        Send-Slack "ALERT: Patch failed on $(hostname) (attempt $attempt)."
        Start-Sleep -Seconds $SleepBetween
        if ($attempt -gt $Retries) {
            Log "All attempts exhausted."
            exit 1
        }
    }
}
