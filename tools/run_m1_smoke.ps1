param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath,
    [int]$Port = 9100
)

$ErrorActionPreference = "Stop"
$workspacePath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$sssPath = Join-Path $workspacePath "server\sss"
$serverLogPath = Join-Path ([System.IO.Path]::GetTempPath()) "galactum-m1-sss.out.log"
$serverErrorLogPath = Join-Path ([System.IO.Path]::GetTempPath()) "galactum-m1-sss.err.log"
$serverEngineLogPath = Join-Path ([System.IO.Path]::GetTempPath()) "galactum-m1-sss.engine.log"
$clientEngineLogPath = Join-Path ([System.IO.Path]::GetTempPath()) "galactum-m1-client.engine.log"
$clientLogPath = Join-Path ([System.IO.Path]::GetTempPath()) "galactum-m1-client.out.log"
$clientErrorLogPath = Join-Path ([System.IO.Path]::GetTempPath()) "galactum-m1-client.err.log"
$serverProcess = $null

try {
    $serverArguments = @(
        "--headless",
        "--log-file", $serverEngineLogPath,
        "--path", $sssPath,
        "--",
        "--port=$Port"
    )
    $serverProcess = Start-Process -FilePath $GodotPath -ArgumentList $serverArguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $serverLogPath -RedirectStandardError $serverErrorLogPath
    $ready = $false
    for ($attempt = 0; $attempt -lt 25; $attempt++) {
        Start-Sleep -Milliseconds 200
        if ($serverProcess.HasExited) {
            throw "El SSS termino antes del smoke test. Revisa $serverLogPath y $serverErrorLogPath."
        }
        if ((Test-Path -LiteralPath $serverLogPath) -and (Select-String -LiteralPath $serverLogPath -SimpleMatch "SSS_READY protocol=team3-m1.0" -Quiet)) {
            $ready = $true
            break
        }
    }
    if (-not $ready) {
        throw "El SSS M1 no informo SSS_READY dentro de 5 segundos. Revisa $serverLogPath y $serverErrorLogPath."
    }
    Start-Sleep -Milliseconds 800

    $clientArguments = @(
        "--headless",
        "--log-file", $clientEngineLogPath,
        "--path", $workspacePath,
        "--script", "res://tests/m1_protocol_smoke.gd",
        "--",
        "--host=127.0.0.1",
        "--port=$Port"
    )
    $clientProcess = Start-Process -FilePath $GodotPath -ArgumentList $clientArguments -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $clientLogPath -RedirectStandardError $clientErrorLogPath
    $smokeOutput = @()
    if (Test-Path -LiteralPath $clientLogPath) {
        $smokeOutput += Get-Content -LiteralPath $clientLogPath
    }
    if (Test-Path -LiteralPath $clientErrorLogPath) {
        $smokeOutput += Get-Content -LiteralPath $clientErrorLogPath
    }
    $smokeOutput | Write-Output
    if ($clientProcess.ExitCode -ne 0 -or ($smokeOutput -join [Environment]::NewLine) -notmatch "M1_SMOKE_OK") {
        throw "El smoke test no informo M1_SMOKE_OK. Revisa $clientEngineLogPath, $serverLogPath y $serverErrorLogPath."
    }
}
finally {
    if ($null -ne $serverProcess -and -not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id
        $serverProcess.WaitForExit()
    }
}
