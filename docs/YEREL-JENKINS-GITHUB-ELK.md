# GitHub push sonrası otomatik Jenkins build ve yerel mikroservis deploy'u

Bu proje için tek komut `powershell -ExecutionPolicy Bypass -File .\scripts\setup-and-publish.ps1`. Kodunuzu önce herkese açık GitHub reposundaki `main` dalına push edin; `Jenkinsfile` de repoda olmalıdır. Script GitHub CLI kullanmaz ve push yapmaz. Yerel `origin` varsa adresini kullanır, yoksa `TahaKilicoglu/java8-jenkins-local-lab` reposunu varsayar; farklı repo için `-RepoUrl https://github.com/TahaKilicoglu/REPO.git` verin. Sonraki her `git push origin main` için Jenkins, GitHub'ı yaklaşık dakikada bir yoklar. GitHub'dan `localhost` adresine webhook gelmez. Yerel makine kapalıyken yeni commit birikir; Jenkins tekrar açıldığında son `main` durumunu kontrol eder.

## 1. Ne nerede çalışıyor?

| Bileşen | Docker ağı veya adres | İşlev |
| --- | --- | --- |
| Jenkins | `localhost:8090`, iç ağ `jenkins` | GitHub SCM polling, Maven build, Docker deploy, Console Output |
| PostgreSQL | `localhost:5433`, iç ağ `postgres:5432` | Order tablosu; demo uygulama hesabı `loadtest` |
| Order Service | `localhost:8080`, iç ağ `order:8080` | REST API, Actuator, HikariCP, Log4j2 |
| Filebeat | `loadtest-lab` ağı | Log4j2 JSON dosyasını okur |
| Elasticsearch | `localhost:9200` | `order-service-*` log indeksleri |
| Kibana | `localhost:5601` | İstek ve hata loglarını arama |

Jenkins ve uygulama iki ayrı Java sürümü kullanır. Jenkins controller Java 21 ile başlar, `Dockerfile` Maven/Temurin 8 image'ında `mvn clean verify` çalıştırır ve uygulama JRE 8 image'ına kopyalanır. Bu yüzden Windows'taki Java kurulumun build sonucunu değiştirmez. Docker ağı container isimlerini DNS adı olarak çözer; Order içinden DB için `localhost` değil `postgres:5432` kullanılır.

## 2. GitHub ve ilk kurulum

PowerShell scripti `TahaKilicoglu` hesabındaki repo adresini yerel `origin` üzerinden okur veya varsayılan adresi kullanır; gerekli durumda `-RepoUrl` ile açıkça belirtebilirsiniz. GitHub'a yazmaz. Ardından `local-lab/.env` içinde iki rastgele parola üretir: `LAB_DB_PASSWORD` PostgreSQL ve Jenkins DB credential'ı için, `JENKINS_ADMIN_PASSWORD` Jenkins admin girişi için. Yerel parola dosyasını `.gitignore` ile Git dışında tutun.

Repository herkese açıktır çünkü Jenkins GitHub'ı kimlik bilgisi olmadan okuyabilir. Özel repo tercih edilecekse GitHub'da özel repo oluşturup Jenkins SCM erişimine ayrıca token/SSH credential eklemek ve Job DSL'de credential ID belirtmek gerekir. Bu sürüm, tek komutla deneyebilmek için açık repo yolunu seçer; şifreler `.env` içindedir ve Git'e eklenmez.

## 3. Jenkins job ve Credentials nasıl otomatik oluşur?

`local-lab/jenkins/jenkins.yaml` Jenkins Configuration as Code dosyasıdır. Jenkins admin kullanıcısını ve `orders-db-app` adlı Username/Password credential'ını `.env` ortam değişkenlerinden oluşturur. Job DSL bölümünde `java8-loadtest-ci` adlı Pipeline job'ı tanımlar; Git adresini `GITHUB_REPO_URL` üzerinden alır, `main` branch'ini ve `Jenkinsfile` yolunu kullanır. `H/1 * * * *` SCM trigger'ı yaklaşık her dakika uzaktaki branch'i karşılaştırır. Değişiklik yoksa uygulamayı yeniden build etmez. Yeni commit varsa `checkout scm` tam olarak repo kodunu Jenkins workspace'ine alır.

Job ilk oluşturulunca script Jenkins HTTP API üzerinden bir başlangıç build'i tetiklemeyi dener. Bu çağrı başarısızsa kullanıcı Jenkins job sayfasında yalnız bir kez **Build Now** yapar. Sonraki push'lar polling ile çalışır. Birden çok commit iki yoklama arasına girerse Jenkins yalnız son branch durumunu build edebilir. `disableConcurrentBuilds()` aynı job'ın iki deploy'unun çakışmasını önler.

`withCredentials` yalnız deploy aşamasında `DB_USER` ve `DB_PASSWORD` değişkenlerini açar. Groovy string interpolation ile parola komut metnine konmaz ve `set +x` shell trace'i kapatır. Bu laboratuvarda `docker run -e DB_PASSWORD` ortam değişkeni Docker'ın container metadata'sında görülebilir; Jenkins Credentials kullanmak bu yerel Docker erişimi olan kişilerden sır saklamak anlamına gelmez. Sunucu ortamında secret manager ve sınırlı yetkili build agent tercih edilir.

## 4. Bir push sonrası tam olarak ne olur?

`git add .; git commit -m "..."; git push origin main` işlemini yaptıktan sonra Jenkins `main` commit hash'inin değiştiğini fark eder. `Jenkinsfile` şu dört aşamayı işletir:

| Aşama | Yapılan iş | Başarısızsa incele |
| --- | --- | --- |
| Checkout GitHub main | GitHub'dan ilgili commit'i çeker, commit/author/subject loglar | Repo adresi, internet, branch, Git erişimi |
| Build and verify with Java 8 | Docker multi-stage build içinde Maven `clean verify`, image etiketi `commit-buildNo` | Maven bağımlılığı, Java derleme, Docker Desktop |
| Deploy on local Docker | Eski image'ı not eder, yeni container başlatır; DB readiness'i bekler | Jenkins credential, `postgres:5432`, port 8080, uygulama logu |
| Smoke check | `/api/orders/ping` çağırır ve çalışan image etiketini gösterir | Container ağı ve HTTP endpoint |

Deploy betiği `scripts/local-deploy.sh` önceki image adını saklar, yeni order container'ını kurar ve `/actuator/health/readiness` içinde `readinessState` ile `db` UP durumunu 90 saniyeye kadar bekler. Yeni sürüm açılmazsa son 50 uygulama logunu Jenkins Console Output'a ekler, eski image'ı yeniden çalıştırmayı dener ve build'i kırmızı yapar. **Tek container değiştiği için kısa kesinti olabilir.** DB migration eski image'la uyumsuzsa sadece image rollback yeterli değildir. Bu projedeki `ddl-auto: update` eğitim içindir; üretimde Flyway/Liquibase ve geriye uyumlu migration gerekir.

## 5. Logların Kibana'ya gidişi

`log4j2-spring.xml` console'a metin, `/var/log/loadtest/app.json` dosyasına satır başına JSON log yazar. `RequestIdFilter` gelen uygun `X-Request-ID` değerini kullanır veya UUID üretir, `ThreadContext` içine yerleştirir ve istek bitince temizler. Uygulama açıldığında `application_ready revision=<image etiketi>` kaydı düşer. JSON dosyası `loadtest-order-logs` adlı Docker volume'dadır. Filebeat aynı volume'u salt okunur açar, `filestream` ile yeni satırları izler ve Elasticsearch'e `order-service-YYYY.MM.DD` indeksi olarak yollar. Kibana Discover için `order-service-*` data view ve `@timestamp` seçilir. `order_created` mesajını arayarak POST isteğinin kaydını görürsün.

Jenkins Console Output build/deploy sürecini gösterir; Kibana uygulama çalışma loglarını gösterir. Jenkins deploy sorunu ararken önce Console Output, sonra `docker logs --tail=100 loadtest-order`, sonra Filebeat logu, `_cat/indices` ve Kibana zaman aralığı kontrol edilir. Elasticsearch/Kibana/Filebeat yerel Compose'ta aynı 8.19.22 sürümündedir. Elastic auth kapalıdır, portlar yalnız `127.0.0.1` üzerinden sunulur; üretim ayarı değildir.

## 6. Mülakatta mikroservis deploy'u nasıl genişletirsin?

Bu paket **tek Order servisini** gerçekten çalıştırır. Inventory ve Payment ikinci/üçüncü servis olarak eklendiğinde her birinin ayrı Git commit/image etiketi, container DNS adı, health endpoint'i, log kaynağı, connection pool sınırı ve tercihen bağımsız veritabanı hesabı olmalı. Order → Payment çağrısına connection/read timeout, sınırlı retry ve ödeme için idempotency key eklenir. Aynı `X-Request-ID` downstream'e iletilir; dağıtık izleme için trace/span ID kullanılır. Yeni sürüm önce geriye uyumlu migration ve kontrat testlerinden geçer, sonra canary veya rolling deploy yapılır. En az iki replica ve load balancer yoksa kesintisiz deploy beklenmez. Replica sayısı arttığında `replica × Hikari maximum-pool-size` kadar potansiyel DB bağlantısı oluşur; 10 × 20 = 200 örneğini DB kapasitesiyle kıyasla.

K6 testleri `k6/` dizinindedir; bir milyon POST sipariş/log/indeks verisi üretebilir. Önce `smoke.js`, ardından `rps.js`; gerçekleşen `http_reqs`, p95/p99, hata oranı, `dropped_iterations` ve Hikari metriklerine bak. Projede henüz otomatik test sınıfı yoktur; Maven verify derlemeyi, Pipeline smoke/readiness çalışma anını doğrular.

## 7. Sorun giderme

`docker compose --env-file .\local-lab\.env -f .\local-lab\compose.yml logs --tail=100 jenkins` Jenkins açılışını, `... logs postgres` DB'yi, `docker logs --tail=100 loadtest-order` uygulamayı gösterir. Repo polling için Jenkins job sayfasındaki **Git Polling Log** veya Console Output'a bak. GitHub'a commit edip push etmediysen Jenkins değişiklik görmez. Jenkins kapalıyken otomatik build yapılamaz. Repo URL değişirse `.env` ve Jenkins job SCM yapılandırmasını uyumlu güncelle; mevcut volume üzerinde JCasC yeniden yüklenmeden değişiklik görünmeyebilir. `.env` parolasını değiştirmek eski PostgreSQL volume'undaki hesabın parolasını değiştirmez; DB parolasını ayrıca döndürmek gerekir.

Resmî kaynaklar: [Jenkins Pipeline SCM polling](https://www.jenkins.io/doc/book/pipeline/syntax/), [Jenkins Configuration as Code](https://github.com/jenkinsci/configuration-as-code-plugin), [Job DSL ile otomatik job oluşturma](https://github.com/jenkinsci/job-dsl-plugin/wiki/JCasC), [GitHub localhost webhook sınırlaması](https://docs.github.com/en/webhooks/testing-and-troubleshooting-webhooks/troubleshooting-webhooks), [Docker Compose ağları](https://docs.docker.com/compose/how-tos/networking/).
