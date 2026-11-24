$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
Set-Location -LiteralPath $projectRoot

$supabaseConfig = Join-Path $projectRoot 'supabase.env.json'
if (-not (Test-Path -LiteralPath $supabaseConfig)) {
  throw 'supabase.env.json is missing. Add your Supabase URL and publishable key first.'
}

$supabaseSettings = Get-Content -LiteralPath $supabaseConfig -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($supabaseSettings.SUPABASE_URL) -or
    [string]::IsNullOrWhiteSpace($supabaseSettings.SUPABASE_PUBLISHABLE_KEY)) {
  throw 'supabase.env.json must include SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.'
}

flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

flutter build web --release "--dart-define-from-file=$supabaseConfig"
if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed.' }

npx --yes vercel link
if ($LASTEXITCODE -ne 0) { throw 'Vercel project linking failed.' }

$webRoot = Join-Path $projectRoot 'build\web'
if (-not (Test-Path -LiteralPath (Join-Path $webRoot 'index.html'))) {
  throw 'Flutter did not produce build\web\index.html.'
}

$outputRoot = Join-Path $projectRoot '.vercel\output'
$projectPrefix = [System.IO.Path]::GetFullPath($projectRoot).TrimEnd('\') + '\'
$resolvedOutput = [System.IO.Path]::GetFullPath($outputRoot)
if (-not $resolvedOutput.StartsWith(
    $projectPrefix,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
  throw 'The resolved Vercel output path is outside the project folder.'
}

if (Test-Path -LiteralPath $resolvedOutput) {
  Remove-Item -LiteralPath $resolvedOutput -Recurse -Force
}

$staticRoot = Join-Path $resolvedOutput 'static'
New-Item -ItemType Directory -Force -Path $staticRoot | Out-Null
Get-ChildItem -LiteralPath $webRoot -Force | Copy-Item -Destination $staticRoot -Recurse -Force

$vercelConfig = [ordered]@{
  version = 3
  routes = @(
    @{ handle = 'filesystem' },
    @{ src = '/.*'; dest = '/index.html' }
  )
}
$configJson = $vercelConfig | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText(
  (Join-Path $resolvedOutput 'config.json'),
  $configJson,
  [System.Text.UTF8Encoding]::new($false)
)

npx --yes vercel deploy --prebuilt --prod
if ($LASTEXITCODE -ne 0) { throw 'Vercel production deployment failed.' }
