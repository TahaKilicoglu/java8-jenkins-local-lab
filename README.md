# GitHub commit → yerel Jenkins → Java 8 Docker deploy → Kibana

Bu paket Windows 10 ve Docker Desktop üzerinde çalışmak için hazırlandı. Önerilen repo adı **`TahaKilicoglu/java8-jenkins-local-lab`**. Jenkins GitHub'daki `main` branch'ini yaklaşık her dakika kontrol eder; yeni push görürse kodu çeker, Java 8 ile derler, Docker image üretir, uygulamayı yerel Docker'a dağıtır ve health kontrolü yapar. Log4j2 logları Filebeat → Elasticsearch → Kibana yolundan izlenir. Ayrı sunucu, registry, SSH ve GitHub webhook tüneli gerekmez.

## Bir defalık kurulum: tek PowerShell komutu

ZIP'i çıkartıp `loadtest-demo` klasöründe PowerShell açın ve Docker Desktop'ın Linux containers modunda çalıştığından emin olun:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-and-publish.ps1
```

Kodları GitHub'a **önceden push etmiş olmanız gerekir**; repoda `main` dalı ve `Jenkinsfile` bulunmalıdır. Script, varsa yerel `origin` adresini kullanır; yoksa `https://github.com/TahaKilicoglu/java8-jenkins-local-lab.git` adresini varsayar. Repo adresiniz farklıysa `-RepoUrl https://github.com/TahaKilicoglu/REPO.git` parametresini verin. Repo herkese açık olmalıdır; Jenkins kimlik bilgisi olmadan Git üzerinden okuyacaktır. Script GitHub CLI (`gh`) veya `winget` kullanmaz; GitHub hesabına giriş yapmaz, commit ya da push oluşturmaz.

Script ardından `local-lab/.env` içinde rastgele yerel DB ve Jenkins admin parolası üretir, Jenkins/PostgreSQL/Elasticsearch/Kibana/Filebeat container'larını başlatır ve ilk Jenkins build'ini kuyruğa almayı dener. Jenkins job'ı ve `orders-db-app` DB credential'ı Configuration as Code ile otomatik oluşturulur. İlk image build'i internet hızına göre zaman alır.

Şirket ağı `updates.jenkins.io` HTTPS trafiğini kendi sertifikasıyla denetliyorsa Jenkins eklenti kurulumunda `PKIX path building failed` hatası görülebilir. Kurulum betiği Windows'un güvenilir kök sertifikalarını (özel anahtar içermez) yerel `local-lab/jenkins/certs/` dizinine aktarır; Dockerfile bu sertifikaları Jenkins'in sistem ve Java truststore'una ekleyip eklenti kurulumunu yeniden dener. Sertifika dosyaları `.gitignore` kapsamındadır; GitHub'a gönderilmez. Windows'un da güvenmediği bir sertifika varsa önce güvenilir kaynaktan alınan kurumsal kök sertifikayı Windows'un Trusted Root Certification Authorities deposuna eklemek gerekir.

| Adres | Görev |
| --- | --- |
| `http://localhost:8090` | Jenkins; kullanıcı `admin`, parola `local-lab/.env` içindeki `JENKINS_ADMIN_PASSWORD` |
| `http://localhost:8080/api/orders/ping` | Uygulama, ilk build bitince `OK` |
| `http://localhost:5601` | Kibana, `order-service-*` data view |
| `http://localhost:9200` | Elasticsearch (yalnız localhost) |
| `localhost:5433` | PostgreSQL host erişimi; Docker ağında `postgres:5432` |

İlk build kendiliğinden başlamazsa Jenkins içindeki `java8-loadtest-ci` job'unda **Build Now**'a bir kez basın. Build logunda `Checkout GitHub main`, `Build and verify with Java 8`, `Deploy on local Docker`, `Smoke check` aşamaları görünür.

## Bundan sonraki değişiklikler

Proje klasöründeki değişikliği kaydedip **GitHub'a push** edin; yalnız yerel commit Jenkins'e görünmez:

```powershell
git add .
git commit -m "Order servisi güncellendi"
git push origin main
```

Jenkins `H/1 * * * *` SCM polling ile genellikle bir dakika içinde yeni Git commit'ini algılar ve deploy eder. Aynı dakikada birkaç push olursa son `main` durumunu build edebilir; her commit için ayrı build garanti edilmez. Bu yöntem bilgisayarın ve Docker Desktop/Jenkins'in açık olmasını gerektirir. GitHub `localhost` adresine webhook gönderemediği için inbound erişim gerektirmeyen polling tercih edilmiştir.

## Hızlı kontrol ve loglar

```powershell
Invoke-RestMethod http://localhost:8080/api/orders/ping
Invoke-RestMethod -Method Post -Uri http://localhost:8080/api/orders -ContentType 'application/json' -Body '{"customerId":123,"productId":500,"quantity":1}'
docker logs --tail=60 loadtest-order
docker compose --env-file .\local-lab\.env -f .\local-lab\compose.yml logs --tail=60 filebeat
```

Kibana `http://localhost:5601` → Stack Management → Data Views → `order-service-*` → `@timestamp` → Discover. `message : "*application_ready*"` ile deploy edilen image etiketini, `message : "*order_created*"` ile sipariş logunu arayın. Jenkins'in build/deploy logları ise job'un **Console Output** ekranındadır. Ayrıntılı komut ve sorun giderme açıklamaları [rehberdedir](docs/YEREL-JENKINS-GITHUB-ELK.md).

## k6 yük testi

```powershell
$scripts = (Resolve-Path .\k6).Path
docker run --rm --network loadtest-lab --mount "type=bind,source=$scripts,target=/scripts,readonly" grafana/k6 run -e BASE_URL=http://order:8080 /scripts/smoke.js
docker run --rm --network loadtest-lab --mount "type=bind,source=$scripts,target=/scripts,readonly" grafana/k6 run -e BASE_URL=http://order:8080 /scripts/rps.js
```

`million.js` bir milyon POST hedefler; önce küçük testler geçsin ve disk kapasitesini kontrol edin. Her sipariş için örnek INFO logu yazılır, bu da yük testinde ayrıca disk ve Elasticsearch yükü yaratır.

## Durdurma ve sınırlar

```powershell
docker rm -f loadtest-order
docker compose --env-file .\local-lab\.env -f .\local-lab\compose.yml --profile observability down
```

`down` veri volume'larını korur; **`down -v` DB/Jenkins/log verilerini siler**. Jenkins'e Docker socket erişimi verildiğinden bu laboratuvar yalnız kendi bilgisayarın içindir. DB parolası yerel Docker container ortamında görülebilir; gerçek üretim secret sistemi değildir. Elastic kimlik doğrulaması yerel demo için kapalıdır. Kod otomatik derlenir ve readiness/smoke doğrulanır; projede henüz unit/integration test sınıfı yoktur.
