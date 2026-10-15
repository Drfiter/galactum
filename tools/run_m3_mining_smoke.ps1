param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [int]$Port = 19325,
    [ValidateSet('m3_mining_scene_test', 'm3_mining_combat_scene_test')]
    [string]$SceneTest = 'm3_mining_scene_test'
)

$ErrorActionPreference = 'Stop'
$repositoryPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sssPath = Join-Path $repositoryPath 'server/sss'
$runId = [Guid]::NewGuid().ToString('N')
$serverLog = Join-Path ([IO.Path]::GetTempPath()) "galactum-m3-mining-$runId.out.log"
$serverError = Join-Path ([IO.Path]::GetTempPath()) "galactum-m3-mining-$runId.err.log"
$server = $null
try {
    $arguments = @('--headless', '--path', ('"{0}"' -f $sssPath), '--script', 'res://tests/mining_scene_server.gd', '--', "--port=$Port")
    $server = Start-Process -FilePath $GodotPath -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $serverLog -RedirectStandardError $serverError
    $ready = $false
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        if ($server.HasExited) { throw "SSS fixture exited. See $serverLog and $serverError" }
        if ((Test-Path -LiteralPath $serverLog) -and (Select-String -LiteralPath $serverLog -SimpleMatch "MINING_SCENE_SSS_READY port=$Port" -Quiet)) { $ready = $true; break }
        Start-Sleep -Milliseconds 100
    }
    if (-not $ready) { throw "SSS readiness timeout. See $serverLog and $serverError" }
    & $GodotPath --headless --max-fps 60 --path $repositoryPath --script "res://tests/$SceneTest.gd" -- "--port=$Port"
    if ($LASTEXITCODE -ne 0) { throw 'M3 mining scene test failed.' }
} finally {
    if ($null -ne $server -and -not $server.HasExited) { Stop-Process -Id $server.Id; $server.WaitForExit() }
}
