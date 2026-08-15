param(
  [string]$ExpectedCanister = 'mprew-viaaa-aaaah-quola-cai'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$expectedRoot = 'C:\Users\Jesse\.openclaw\workspaces\jmai\dapps\infinity-arcade-Jay'
$activeFrontendCanister = 'mprew-viaaa-aaaah-quola-cai'
$deniedFrontendTargets = @('ewgfh-vqaaa-aaaah-qtixa-cai')
$deniedValidationDomains = @('icparcade.dev')

if ($root -ne $expectedRoot) { throw "Wrong project root: $root. Active Infinity Arcade root is $expectedRoot" }
if ($ExpectedCanister -ne $activeFrontendCanister) { throw "Refusing non-active frontend target: $ExpectedCanister. Active frontend canister is $activeFrontendCanister" }
if ($deniedFrontendTargets -contains $ExpectedCanister) { throw "Refusing legacy frontend target: $ExpectedCanister" }

$manifestPath = Join-Path $root 'deploy-manifest.json'
if (-not (Test-Path $manifestPath)) { throw 'deploy-manifest.json missing' }

$manifest = Get-Content $manifestPath | ConvertFrom-Json
$manifestProperties = @($manifest.PSObject.Properties.Name)
$hasFrontendCanister = $manifestProperties -contains 'frontendCanister'
$hasProductionCanister = $manifestProperties -contains 'productionCanister'

if ($hasFrontendCanister -and -not [string]::IsNullOrWhiteSpace($manifest.frontendCanister)) {
  $manifestCanister = $manifest.frontendCanister
  $manifestCanisterField = 'frontendCanister'
} elseif ($hasProductionCanister -and -not [string]::IsNullOrWhiteSpace($manifest.productionCanister)) {
  $manifestCanister = $manifest.productionCanister
  $manifestCanisterField = 'productionCanister'
} else {
  throw 'Canister mismatch: deploy-manifest.json must define frontendCanister (preferred) or productionCanister (legacy fallback)'
}

if ($manifestCanister -ne $ExpectedCanister) { throw "Canister mismatch: $manifestCanister from $manifestCanisterField" }
if ($manifestCanister -ne $activeFrontendCanister) { throw "Manifest points at non-active frontend target: $manifestCanister" }
if ($deniedFrontendTargets -contains $manifestCanister) { throw "Manifest points at quarantined legacy frontend target: $manifestCanister" }
if ($root -ne $manifest.sourceDir) { throw "Wrong canonical source dir: $root" }
if (($manifestProperties -contains 'canonicalSource') -and $manifest.canonicalSource -ne $expectedRoot) { throw "Wrong manifest canonicalSource: $($manifest.canonicalSource)" }
if (Test-Path (Join-Path $root 'LEGACY_DO_NOT_DEPLOY.md')) { throw 'This tree is marked legacy' }

$expectedPublishDir = Join-Path $root '.deploy\frontend-public'
if (($manifestProperties -contains 'frontendDeploySource') -and -not [string]::IsNullOrWhiteSpace($manifest.frontendDeploySource)) {
  if ($manifest.frontendDeploySource -ne $expectedPublishDir) {
    throw "Wrong frontend deploy source: $($manifest.frontendDeploySource)"
  }
} else {
  throw 'deploy-manifest.json must define frontendDeploySource=.deploy/frontend-public'
}

if (-not (Test-Path $expectedPublishDir)) {
  throw 'Sanitized frontend payload missing. Run: node scripts/build-frontend-publish.mjs'
}

$forbiddenPatterns = @(
  '^backend/',
  '^docs/',
  '^scripts/',
  '^tasks/',
  '^\.openclaw-review/',
  '^\.git/',
  '^\.deploy/',
  '^node_modules/',
  '^CANONICAL\.md$',
  '^PROJECT\.md$',
  '^PROJECT_ROOT_STRUCTURE\.md$',
  '^README_CANONICAL_DEPLOY\.md$',
  '^ROLLBACK\.md$',
  '^deploy-manifest\.json$',
  '^\.deployignore$',
  '^\.gitignore$'
)

$payloadFiles = Get-ChildItem -Path $expectedPublishDir -Recurse -File | ForEach-Object {
  $_.FullName.Substring($expectedPublishDir.Length + 1).Replace('\\', '/')
} | Sort-Object

if (-not ($payloadFiles -contains 'index.html')) { throw 'Sanitized payload missing index.html' }
if (-not ($payloadFiles -contains 'manifesto.txt')) { throw 'Sanitized payload missing manifesto.txt' }

foreach ($file in $payloadFiles) {
  $payloadFilePath = Join-Path $expectedPublishDir ($file -replace '/', [System.IO.Path]::DirectorySeparatorChar)
  $payloadBytes = [System.IO.File]::ReadAllBytes($payloadFilePath)
  $payloadText = [System.Text.Encoding]::ASCII.GetString($payloadBytes)
  foreach ($legacyTarget in $deniedFrontendTargets) {
    if ($payloadText -match [regex]::Escape($legacyTarget)) { throw "Sanitized payload file $file references quarantined legacy frontend target: $legacyTarget" }
  }
  foreach ($legacyDomain in $deniedValidationDomains) {
    if ($payloadText -match [regex]::Escape($legacyDomain)) { throw "Sanitized payload file $file references abandoned validation domain: $legacyDomain" }
  }
}

foreach ($file in $payloadFiles) {
  foreach ($pattern in $forbiddenPatterns) {
    if ($file -match $pattern) { throw "Forbidden internal path in sanitized payload: $file" }
  }
}

$gitCheckOutput = & git -C $root rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0 -or $gitCheckOutput -ne 'true') { throw 'Canonical tree is not under git' }

Write-Host "Predeploy check passed. Verified $manifestCanisterField=$manifestCanister and frontendDeploySource=$expectedPublishDir."
Write-Host "Sanitized payload files: $($payloadFiles.Count)"
