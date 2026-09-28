param([string]$RepoUrl = '')
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $projectRoot

if (-not $RepoUrl) {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git -and (Test-Path '.git') -and (@(& git remote) -contains 'origin')) {
        $RepoUrl = (& git remote get-url origin).Trim()
    } else {
        $RepoUrl = 'https://github.com/TahaKilicoglu/java8-jenkins-local-lab.git'
    }
}
$repoMatch = [regex]::Match($RepoUrl.Trim(), '^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)(TahaKilicoglu/[A-Za-z0-9._-]+?)(?:\.git)?/?$', 'IgnoreCase')
if (-not $repoMatch.Success) { throw 'GitHub adresi beklenen biçimde değil. -RepoUrl https://github.com/TahaKilicoglu/REPO.git kullanın.' }
$slug = $repoMatch.Groups[1].Value
$repoUrl = "https://github.com/$slug.git"
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker Desktop bulunamadı.' }
function Invoke-DockerCommand([string[]]$DockerArguments, [switch]$Quiet) {
    $previousPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 turns native stderr warnings into errors under Stop.
        $ErrorActionPreference = 'Continue'
        if ($Quiet) {
            & docker @DockerArguments *> $null
        } else {
            & docker @DockerArguments 2>&1 | ForEach-Object { Write-Host $_ }
        }
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}
if ((Invoke-DockerCommand -DockerArguments @('info') -Quiet) -ne 0) { throw 'Docker Desktop açık ve Linux containers modunda olmalı.' }
Write-Host "Jenkins için GitHub deposu: $repoUrl"
Write-Host 'Bu betik GitHub CLI kullanmaz; commit veya push oluşturmaz.'

$envPath = Join-Path $projectRoot 'local-lab\.env'
if (-not (Test-Path $envPath)) {
    function New-Secret {
        $bytes = New-Object byte[] 24
        $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $generator.GetBytes($bytes) } finally { $generator.Dispose() }
        return [BitConverter]::ToString($bytes).Replace('-', '')
    }
    @(
        "LAB_DB_PASSWORD=$(New-Secret)",
        "JENKINS_ADMIN_PASSWORD=$(New-Secret)",
        "GITHUB_REPO_URL=$repoUrl"
    ) | Set-Content -Path $envPath -Encoding ASCII
    Write-Host 'Yerel parolalar local-lab/.env dosyasında oluşturuldu (Git dışında).'
} else {
    $configuredRepo = (Get-Content $envPath | Where-Object { $_ -like 'GITHUB_REPO_URL=*' } | Select-Object -First 1)
    if ($configuredRepo -and $configuredRepo -ne "GITHUB_REPO_URL=$repoUrl") {
        throw "local-lab/.env içindeki GITHUB_REPO_URL beklenen URL değil: $repoUrl"
    }
    if (-not $configuredRepo) { Add-Content -Path $envPath -Value "GITHUB_REPO_URL=$repoUrl" }
    $existingAdmin = Get-Content $envPath | Where-Object { $_ -like 'JENKINS_ADMIN_PASSWORD=*' } | Select-Object -First 1
    if (-not $existingAdmin) {
        $bytes = New-Object byte[] 24
        $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $generator.GetBytes($bytes) } finally { $generator.Dispose() }
        Add-Content -Path $envPath -Value "JENKINS_ADMIN_PASSWORD=$([BitConverter]::ToString($bytes).Replace('-', ''))"
    }
    $existingDb = Get-Content $envPath | Where-Object { $_ -like 'LAB_DB_PASSWORD=*' } | Select-Object -First 1
    if (-not $existingDb) { throw 'local-lab/.env içinde LAB_DB_PASSWORD eksik.' }
}

$certDir = Join-Path $projectRoot 'local-lab\jenkins\certs'
New-Item -ItemType Directory -Path $certDir -Force | Out-Null
$trustedRoots = @{}
foreach ($rootStore in @('Cert:\CurrentUser\Root', 'Cert:\LocalMachine\Root')) {
    foreach ($certificate in @(Get-ChildItem -Path $rootStore -ErrorAction SilentlyContinue)) {
        if ($certificate.NotAfter -gt (Get-Date) -and $certificate.Thumbprint) {
            $trustedRoots[$certificate.Thumbprint] = $certificate
        }
    }
}
if ($trustedRoots.Count -eq 0) { throw 'Windows güvenilir kök sertifikaları okunamadı.' }
foreach ($thumbprint in $trustedRoots.Keys) {
    $certFile = Join-Path $certDir "windows-$thumbprint.crt"
    if (-not (Test-Path $certFile)) {
        $base64 = [Convert]::ToBase64String($trustedRoots[$thumbprint].RawData, [Base64FormattingOptions]::InsertLineBreaks)
        $pem = "-----BEGIN CERTIFICATE-----`r`n$base64`r`n-----END CERTIFICATE-----`r`n"
        [IO.File]::WriteAllText($certFile, $pem, [Text.Encoding]::ASCII)
    }
}
Write-Host "$($trustedRoots.Count) Windows güvenilir kök sertifikası Jenkins image'ına aktarılacak (yalnız public sertifika; Git dışında)."

$compose = Join-Path $projectRoot 'local-lab\compose.yml'
$composeArgs = @('compose', '--env-file', $envPath, '-f', $compose, '--profile', 'observability', 'up', '-d', '--build')
if ((Invoke-DockerCommand -DockerArguments $composeArgs) -ne 0) { throw 'Docker Compose başlatılamadı.' }

$values = @{}
Get-Content $envPath | ForEach-Object {
    if ($_ -match '^([^#=]+)=(.*)$') { $values[$matches[1]] = $matches[2] }
}
$auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$($values['JENKINS_ADMIN_PASSWORD'])"))
$headers = @{ Authorization = "Basic $auth" }
$ready = $false
for ($i = 0; $i -lt 90; $i++) {
    try {
        $response = Invoke-WebRequest -Uri 'http://localhost:8090/login' -UseBasicParsing -TimeoutSec 2
        if ($response.StatusCode -eq 200) { $ready = $true; break }
    } catch { }
    Start-Sleep -Seconds 2
}
if (-not $ready) { throw 'Jenkins hazır olmadı. docker compose logs jenkins ile hatayı inceleyin.' }

try {
    $crumb = Invoke-RestMethod -Uri 'http://localhost:8090/crumbIssuer/api/json' -Headers $headers -TimeoutSec 10
    $headers[$crumb.crumbRequestField] = $crumb.crumb
    Invoke-WebRequest -Method Post -Uri 'http://localhost:8090/job/java8-loadtest-ci/build' -Headers $headers -UseBasicParsing -TimeoutSec 15 | Out-Null
    Write-Host 'İlk Jenkins build kuyruğa alındı.'
} catch {
    Write-Host 'İlk build otomatik başlatılamadı. Jenkins > java8-loadtest-ci > Build Now ile bir kez başlatın.'
}
Write-Host "GitHub: https://github.com/$slug"
Write-Host 'Jenkins: http://localhost:8090 (admin; parola local-lab/.env içinde)'
Write-Host 'Uygulama: http://localhost:8080/api/orders/ping (ilk build tamamlandıktan sonra)'
Write-Host 'Kibana: http://localhost:5601'
