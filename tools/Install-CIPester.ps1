# CI dependency setup only. Test assertions are never retried.
[CmdletBinding()]
param(
    [ValidateRange(1, 5)]
    [int]$MaxAttempts = 3,
    [ValidateRange(0, 60)]
    [int]$DelaySeconds = 10
)

$ErrorActionPreference = 'Stop'
for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    Write-Host "Pester setup attempt $attempt of $MaxAttempts (PowerShell $($PSVersionTable.PSVersion))."
    try {
        Install-Module Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99 -Force -SkipPublisherCheck -Scope CurrentUser -ErrorAction Stop
        $module = Import-Module Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99 -Force -PassThru -ErrorAction Stop
        if (-not $module -or $module.Version -lt [version]'5.5.0' -or $module.Version -gt [version]'5.99.99') {
            throw 'Pester setup did not load a supported version (5.5.0 through 5.99.99).'
        }
        Write-Host "Pester $($module.Version) loaded successfully."
        return
    }
    catch {
        Write-Warning "Pester setup attempt $attempt failed: $($_.Exception.Message)"
        if ($attempt -eq $MaxAttempts) {
            throw "Pester setup failed after $MaxAttempts attempts. Tests will not run. Last error: $($_.Exception.Message)"
        }
        Start-Sleep -Seconds $DelaySeconds
    }
}
