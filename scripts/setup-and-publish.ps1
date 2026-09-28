param([string]$RepoName = 'java8-jenkins-local-lab')
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $projectRoot
$slug = "TahaKilicoglu/$RepoName"
$repoUrl = "https://github.com/$slug.git"

function Resolve-Executable([string]$name, [string]$packageId, [string[]]$locations) {
    $found = Get-Command $name -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "$name bulunamadı. Git for Windows ve GitHub CLI kurup tekrar çalıştırın."
    }
    Write-Host "$name yükleniyor..."
    & winget install --id $packageId --exact --source winget --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw "$name kurulamadı." }
    foreach ($path in $locations) { if (Test-Path $path) { return $path } }
    $found = Get-Command $name -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    throw "$name kuruldu ancak bu oturumda bulunamadı. PowerShell'i yeniden açıp tekrar çalıştırın."
}

$git = Resolve-Executable 'git' 'Git.Git' @('C:\Program Files\Git\cmd\git.exe')
$gh = Resolve-Executable 'gh' 'GitHub.cli' @('C:\Program Files\GitHub CLI\gh.exe')
$env:PATH = "$(Split-Path $git);$(Split-Path $gh);$env:PATH"
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker Desktop bulunamadı.' }
& docker info *> $null
if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop açık ve Linux containers modunda olmalı.' }

& $gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'GitHub hesabına tarayıcıda bir kez giriş yapın.'
    & $gh auth login --web --git-protocol https
    if ($LASTEXITCODE -ne 0) { throw 'GitHub oturumu açılamadı.' }
}
$account = & $gh api user --jq .login
if ($LASTEXITCODE -ne 0 -or $account.Trim() -ine 'TahaKilicoglu') {
    throw "GitHub oturumu beklenen TahaKilicoglu hesabına ait değil: $account"
}

if (-not (Test-Path '.git')) {
    & $git init -b main
    if ($LASTEXITCODE -ne 0) { throw 'Git başlatılamadı.' }
}
& $git config user.name 'TahaKilicoglu'
& $git config user.email 'TahaKilicoglu@users.noreply.github.com'
& $git add -A
& $git ls-files --error-unmatch local-lab/.env 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { throw 'local-lab/.env Git tarafından izleniyor; parolalar yayımlanmadan önce dosyayı Git takibinden çıkarın.' }
& $git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Git diff kontrolü başarısız.' }
& $git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
    & $git commit -m 'Add local Jenkins Java 8 deployment lab'
    if ($LASTEXITCODE -ne 0) { throw 'Git commit oluşturulamadı.' }
}

& $gh repo view $slug --json name *> $null
$repoExists = ($LASTEXITCODE -eq 0)
& $git remote get-url origin 2>$null | Out-Null
$hasOrigin = ($LASTEXITCODE -eq 0)
if ($repoExists) {
    if (-not $hasOrigin) { throw "$slug zaten mevcut. Üzerine otomatik yazılmadı. Yeni RepoName seçin veya remote'u inceleyin." }
    $originUrl = & $git remote get-url origin
    if ($originUrl.Trim() -ne $repoUrl) { throw "Mevcut origin farklı: $originUrl" }
    & $git push -u origin main
    if ($LASTEXITCODE -ne 0) { throw 'Git push başarısız.' }
} else {
    if ($hasOrigin) { throw 'origin remote zaten var; önce hangi repository olduğunu kontrol edin.' }
    Write-Host "$slug adlı herkese açık demo repository oluşturuluyor. Kaynak kod yayımlanacak."
    & $gh repo create $slug --public --source . --remote origin --push
    if ($LASTEXITCODE -ne 0) { throw 'GitHub repo oluşturma veya push başarısız.' }
}

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

$compose = Join-Path $projectRoot 'local-lab\compose.yml'
& docker compose --env-file $envPath -f $compose --profile observability up -d --build
if ($LASTEXITCODE -ne 0) { throw 'Docker Compose başlatılamadı.' }

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
