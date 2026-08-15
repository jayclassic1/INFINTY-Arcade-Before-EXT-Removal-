param(
  [switch]$Deploy,
  [switch]$Check,
  [string]$ExpectedCanister = 'mprew-viaaa-aaaah-quola-cai'
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Resolve-Path (Join-Path $ScriptDir '..')
$RootPath = $Root.Path
$CanonicalRoot = 'C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay'
$FrontendCanister = 'mprew-viaaa-aaaah-quola-cai'

if ($RootPath -ne $CanonicalRoot) {
  throw "Refusing non-canonical root: $RootPath; expected $CanonicalRoot"
}
if ($ExpectedCanister -ne $FrontendCanister) {
  throw "Refusing frontend canister $ExpectedCanister; expected $FrontendCanister"
}

Push-Location $RootPath
try {
  Write-Host 'Building explicit frontend publish payload...'
  node scripts\build-frontend-publish.mjs

  Write-Host 'Running frontend canister predeploy guard...'
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\predeploy-check.ps1 -ExpectedCanister mprew-viaaa-aaaah-quola-cai

  Write-Host 'Running deploy identity guard...'
  npm run deploy:guard

  Write-Host 'Preparing /index.html store args...'
  node scripts\prepare-index-only-deploy.mjs --check --write-args --no-build

  $IdentityArg = Join-Path $RootPath '.deploy\index-only\store-index-identity.did'
  $GzipArg = Join-Path $RootPath '.deploy\index-only\store-index-gzip.did'
  $IdentityArgCli = '.deploy/index-only/store-index-identity.did'
  $GzipArgCli = '.deploy/index-only/store-index-gzip.did'
  $LocalIndex = Join-Path $RootPath '.deploy\frontend-public\index.html'
  $ExpectedSha = (Get-FileHash -LiteralPath $LocalIndex -Algorithm SHA256).Hash.ToLowerInvariant()

  $PasswordFile = '/mnt/c/Users/Jesse/.openclaw/secrets/icp-cli/mcp-identity.password'
  $IdentityCommand = "node scripts\run-icp-tool.mjs icp canister call $FrontendCanister store --args-file $IdentityArgCli --environment ic --identity mcp-identity --identity-password-file $PasswordFile"
  $GzipCommand = "node scripts\run-icp-tool.mjs icp canister call $FrontendCanister store --args-file $GzipArgCli --environment ic --identity mcp-identity --identity-password-file $PasswordFile"

  Write-Host "Expected identity SHA256: $ExpectedSha"
  Write-Host "Prepared arg files:"
  Write-Host "- $IdentityArg"
  Write-Host "- $GzipArg"
  Write-Host 'Store commands:'
  Write-Host $IdentityCommand
  Write-Host $GzipCommand

  if (-not $Deploy) {
    Write-Host 'Dry-run/check mode only; not calling canister. Pass -Deploy to store /index.html and verify live identity bytes.'
    exit 0
  }

  Write-Host 'Deploy mode: storing identity encoding...'
  node scripts\run-icp-tool.mjs icp canister call $FrontendCanister store --args-file $IdentityArgCli --environment ic --identity mcp-identity --identity-password-file $PasswordFile
  if ($LASTEXITCODE -ne 0) { throw "Identity store call failed with exit $LASTEXITCODE" }

  Write-Host 'Deploy mode: storing gzip encoding...'
  node scripts\run-icp-tool.mjs icp canister call $FrontendCanister store --args-file $GzipArgCli --environment ic --identity mcp-identity --identity-password-file $PasswordFile
  if ($LASTEXITCODE -ne 0) { throw "Gzip store call failed with exit $LASTEXITCODE" }

  $LiveUrl = "https://$FrontendCanister.raw.icp0.io/index.html"
  $TempLive = Join-Path $env:TEMP "infinity-arcade-live-index-$FrontendCanister.html"
  Write-Host "Verifying live raw /index.html identity SHA from $LiveUrl ..."
  Invoke-WebRequest -Uri $LiveUrl -Headers @{ 'Accept-Encoding' = 'identity' } -OutFile $TempLive
  $LiveSha = (Get-FileHash -LiteralPath $TempLive -Algorithm SHA256).Hash.ToLowerInvariant()
  Remove-Item -LiteralPath $TempLive -Force -ErrorAction SilentlyContinue

  if ($LiveSha -ne $ExpectedSha) {
    throw "Live /index.html SHA mismatch: expected $ExpectedSha got $LiveSha"
  }

  Write-Host "Live /index.html verified: $LiveSha"
} finally {
  Pop-Location
}
