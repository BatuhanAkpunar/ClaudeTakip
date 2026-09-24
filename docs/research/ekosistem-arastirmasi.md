# Claude Limit Takibi: Ekosistem ve Mimari Kararı Araştırması

Tarih: 2026-08-21 | Kapsam: macOS masaüstü uygulaması, Claude abonelik limitleri (5 saatlik + haftalık pencere)
Amaç: Hangi veri kaynağı ve hangi auth mimarisi seçilecek sorusunu karara bağlamak.

Bu belgedeki her iddia ya birinci el kaynak koduna, resmi Anthropic dokümanına, canlı `gh api` sorgusuna ya da bu makinede yapılan doğrudan kontrole dayanır. Doğrulanmamış olanlar açıkça "doğrulanmadı" diye işaretlidir.

---

## 1. Özet: ekosistemde ne var, hangi boşluk duruyor

Kategori kalabalık ve olgun. GitHub'da tek başına 15'ten fazla ciddi macOS menü bar uygulaması, buna ek olarak kapalı kaynak ticari ürünler (Usagebar, AgentPeek), bir App Store uygulaması, üç SwiftBar/xbar eklentisi ve 11.748 kurulumlu bir Raycast eklentisi var. Lider CodexBar 20.436 yıldızda ve bugün hâlâ push alıyor. Hacker News'te kategoriye verilen tepki net: "at least a dozen same/similar (better?) solutions" ([HN 46544524](https://news.ycombinator.com/item?id=46544524)).

Buna rağmen üç yapısal boşluk duruyor:

**Boşluk 1: Herkes aynı belgelenmemiş endpoint'e bağımlı.** Sunucu doğrusu limit yüzdesi gösteren her araç `GET https://api.anthropic.com/api/oauth/usage` çağırıyor. Bu endpoint dokümante değil, agresif 429 dönüyor ve Anthropic konuyla ilgili iki hata raporunu da yanıtsız kapattı ([#31021](https://github.com/anthropics/claude-code/issues/31021), [#31637](https://github.com/anthropics/claude-code/issues/31637)). Kategorinin tek arıza noktası bu.

**Boşluk 2: Resmi ve temiz olan yol kullanılmıyor.** Claude Code 2.1.80 ile statusline komutlarına stdin üzerinden `rate_limits.five_hour` ve `rate_limits.seven_day` resmi olarak veriliyor ([resmi doküman](https://code.claude.com/docs/en/statusline)). Sıfır network, sıfır 429, sıfır credential okuma, sıfır ToS riski. Ama bu veri yalnızca Claude Code oturumu içinde akıyor ve hiçbir menü bar uygulamasının bunu birincil kaynak yaptığı doğrulanamadı. Köprüyü kuran tek desen Maciek-roboblog'un `--write-state` protokolü ve README'si bu boşluğu açıkça teslim ediyor: "Native menu bar and system tray apps are welcome as separate companion projects" ([CCUM](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor)).

**Boşluk 3: "Ne zaman devam edebilirim" sorusu cevapsız.** Neredeyse tüm araçlar yüzde gösteriyor. Kullanıcı limite yaklaşırken yüzde eylem üretmiyor, geri sayım üretiyor. Bunu ürün kararına dönüştüren tek araç Usagebar (limite yaklaşınca yüzde yerine "next window opens in" gösteriyor) ve en popüler rakipte bu hâlâ bir açık talep (hamed-elfayome #311, "Standalone menu bar segment for reset countdown", 2026-08-20).

**Bu makineye özel kritik bulgu.** Bu Mac'te standalone `claude` CLI kurulu değil (`which claude` boş), Keychain'de `Claude Code-credentials` kaydı yok, `~/.claude/.credentials.json` yok. Buna karşılık `~/.claude/projects` altında 788 JSONL dosyası ve 1.8 GB veri var, `entrypoint: claude-desktop`. Yani ekosistemin "sıfır kurulum" diye pazarladığı Keychain okuma yolu, bu kullanıcının kendi makinesinde hiç çalışmıyor. Mimari kararın merkezinde bu durmalı.

---

## 2. Mevcut araçlar tablosu

Yıldız ve son push değerleri 2026-08-21'de `gh api` ile doğrulandı.

| Ad | Platform | Veri kaynağı | Auth | Gösterdiği limit | Durum | Zayıflığı |
|---|---|---|---|---|---|---|
| [CodexBar](https://github.com/steipete/CodexBar/) | macOS menü bar, Swift/SwiftUI, macOS 14+ | OAuth API → CLI PTY scraping → claude.ai Web API; ayrıca lokal JSONL maliyet, Admin API | Sıfır ek adım hedefli: Keychain `Claude Code-credentials`; opsiyonel cookie yakalama, ANTHROPIC_ADMIN_KEY | five_hour, seven_day, model bazlı haftalık, `limits[].weekly_scoped`, routines/cowork, extra_usage, reset geri sayımı | Aktif, 20.436 ★, push 2026-08-21 | 130 açık issue; 20+ sağlayıcı kapsamı ağır bakım yükü; çoklu hesap görünürlüğü kırık (#2954) |
| [Claude Usage Tracker (hamed-elfayome)](https://github.com/hamed-elfayome/Claude-Usage-Tracker) | macOS menü bar, Swift/SwiftUI, macOS 14+ | claude.ai `/organizations/{id}/usage` + Console `/v1/organization/{id}/usage`; lokal JSONL yok | Üç yol: Claude Code OAuth devralma, gömülü tarayıcı login, DevTools'tan session key | 5 saat, 7 gün, model bazlı (Opus/Sonnet/Fable/Design), API maliyeti | Aktif, 3.305 ★, push 2026-07-12 | Keychain migrasyonu Developer ID build'lerde sessizce çalışmıyor, credential düz metinde kalıyor (#292, açık, GHSA-mfxh-xpwm-23c7); Enterprise'da çalışmıyor (#274) |
| [ClaudeBar (tddworks)](https://github.com/tddworks/ClaudeBar) | macOS menü bar, Swift 6.2, macOS 15+ | Sağlayıcı başına kurulu CLI'ların lokal dosyaları; Kimi için tarayıcı cookie; Grok için OAuth | Çoğunlukla ek auth yok; Kimi için Full Disk Access | Session, weekly, model bazlı yüzdeler; bazı sağlayıcılarda aylık | Aktif, 1.429 ★, push 2026-08-21 | Full Disk Access talebi agresif; macOS 15+ zorunlu; 55 açık issue |
| [CCSeva](https://github.com/Iamshankhadeep/ccseva) | macOS menü bar, Electron'dan Swift 6.1'e geçişte | OAuth usage endpoint birincil (güncel Swift sürümü), lokal JSONL detay + fallback | Claude Code kurulu olmalı; ek auth yok | 5 saatlik blok, burn rate, projeksiyon, haftalık toplamlar | Orta aktif, 801 ★, push 2026-08-03 | Üç açık doğruluk bug'ı: #23 yanlış %100, #27 yanlış yüzde, #38 dedup çıktıyı ~%5 eksik sayıyor; Electron→Swift geçişi repo'da yarım duruyor |
| [claude-usage-bar (Blimp-Labs)](https://github.com/Blimp-Labs/claude-usage-bar) | macOS menü bar, Swift 5.9+, Swift Charts | Anthropic usage endpoint | Tarayıcı OAuth akışı; token `~/.config/claude-usage-bar/token` | 5 saat + 7 gün çift çubuk, model bazlı, extra usage, geçmiş grafiği | Aktif, 472 ★, push 2026-08-20 | Token'ı Keychain yerine düz dosyada tutuyor; varsayılan polling 30 dk, "canlı" değil |
| [Usage4Claude (f-is-h)](https://github.com/f-is-h/Usage4Claude) | macOS menü bar, Swift, macOS 13+ | Claude usage API (endpoint README'de yazmıyor, doğrulanmadı) | Session key elle giriş; Keychain'de şifreli | Beş limit türü ayrı ayrı: 5 saat, 7 gün, extra usage, 7g Opus, 7g Sonnet | Aktif, 366 ★, push 2026-07-17 | Session key periyodik olarak sürüyor doluyor (FAQ kabul ediyor); DevTools adımı teknik olmayan kullanıcıyı dışlıyor |
| [claudecodeusage (richhickson)](https://github.com/richhickson/claudecodeusage) | macOS menü bar, Swift, yalnızca Apple Silicon | `/api/oauth/usage` | Ek login yok, tek Keychain kaydı okuma | Session, weekly, per-model, overage | Aktif, 334 ★, push 2026-08-17 | HN'de özgünlük eleştirisi; kullanıcılar "Authentication expired. Run claude to re-auth" hatası bildirdi; Intel desteği yok |
| [ClaudeUsageBar (Artzainnn)](https://github.com/Artzainnn/ClaudeUsageBar) | macOS menü bar, <5MB | claude.ai dahili API | DevTools'tan tam Cookie değerini elle kopyalama | 5 saat, 7 gün, Sonnet haftalık, extra usage tier'ı | Aktif ama yığılmış, 308 ★, 61 açık issue | README'nin kendisi uyarıyor: claude.ai iç endpoint'leri habersiz değişebilir; cookie akışı kırılgan |
| [usage (aqua5230)](https://github.com/aqua5230/usage) | macOS + Windows, Python 3.13 | Yalnızca lokal loglar, sıfır LLM API çağrısı | Claude/Codex için hiçbir şey | 5 saatlik ve haftalık tavanlar, token, tahmini maliyet, burn rate | Çok aktif, 293 ★, push 2026-08-21 | Yüzdeler sunucu doğrusu değil, log'dan türetilmiş TAHMİN; çoklu cihazda eksik sayar; AGPL-3.0 |
| [ClaudeMeter (eddmann)](https://github.com/eddmann/ClaudeMeter) | macOS menü bar, Homebrew | claude.ai session key | Session key girişi, Keychain'de şifreli | 5 saat, 7 gün, Sonnet | Yavaşlamış, 135 ★, push 2026-05-19 | Opus limiti yok; 3 aydır push yok, şema kaymalarını kaçırıyor |
| [Usagebar](https://usagebar.com/) | macOS menü bar, kapalı kaynak | Keychain'deki Claude Code OAuth credential + Anthropic usage endpoint | Kullanıcıdan hiçbir şey | 5 saat + haftalık, reset timer | Ticari, 2026 lansmanı, $9 tek seferlik | Kapalı kaynak, veri akışı doğrulanamıyor; stack açıklanmamış (doğrulanmadı); tek sağlayıcı |
| [AgentPeek](https://agentpeek.app/menu-bar/) | macOS menü bar, kapalı kaynak | Lokal ajan kayıtları + opsiyonel Cursor/Aider entegrasyonu | Claude için lokal dosyalar | "Token kullanım pencereleri", saatlik/günlük/haftalık | Ticari, 3 günlük deneme | Sunucu doğrusu yüzde verip vermediği belirsiz (doğrulanmadı); fiyat sayfada yok |
| [Usage for Claude (App Store)](https://apps.apple.com/us/app/usage-for-claude/id6755173244) | Mac + iPhone + iPad + Watch + Vision Pro | Claude hesabıyla giriş + companion Mac app | Uygulama içi login (mekanizma açıklanmamış, doğrulanmadı) | Session, haftalık, Opus; 5s/24s/7g/30g/90g grafikler | Yayında, 4.0/5 ama yalnızca 5 değerlendirme | Yorum: "doesn't do a good job at keeping itself up to date"; elle yenileme gerekiyor; Mac app açık olmalı |
| [claude-quota (SwiftBar)](https://github.com/grzegorz-raczek-unit8/claude-quota) | SwiftBar eklentisi, Python | Keychain OAuth token + `/api/oauth/usage` | Ek auth yok | 5 saat, haftalık (sert tavanda siyah), model bazlı `limits[]`, extra usage | Aktif, 72 ★, push 2026-07-30 | README "read-only" diyor ama kod token yeniliyor ve Keychain'e geri yazıyor (bkz. bölüm 6); SwiftBar ön koşul |
| [AI Usage Barometer](https://github.com/taka-avantgarde/ai-usage-barometer) | SwiftBar/xbar, saf Bash | Keychain OAuth + usage endpoint | Ek auth yok | İki pil çubuğu: 5 saat + 7 gün; menü bar en kısıtlı pencereyi yansıtıyor | Çok yeni, 1 ★, push 2026-08-21 | Kullanıcı tabanı yok, güvenilirlik doğrulanmamış; Homebrew + jq + curl + SwiftBar zinciri |
| [Claude Code Usage Monitor (CCUM)](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor) | Terminal TUI + statusline modu, Python | Üç katman: resmi statusline yakalaması → OAuth endpoint (opt-in) → lokal JSONL + P90 | Katman 1 statusline kurulumu, katman 2 token, katman 3 hiçbir şey | five_hour + seven_day gerçek yüzde; yoksa 19k/88k/220k tahmini | Aktif, 8.649 ★ | Menü bar uygulaması değil, kasten yapmıyor; hardcoded limitler eskiyebilir |
| [ccusage](https://github.com/ryoppippi/ccusage) | CLI, Rust | Yalnızca lokal JSONL, 15+ ajan adapter'ı | Yok, tamamen offline | Limit YÜZDESİ yok; blok token/maliyet, burn rate, `--token-limit` ile elle kota | Aktif, fiili lokal veri katmanı | Plan bilgisi yok; `max` seçeneği dairesel (kendi geçmişini limit sayıyor) |
| [claude-powerline](https://github.com/Owloops/claude-powerline) | Claude Code statusline, TypeScript | Yalnızca stdin `rate_limits` | Yok | 5 saatlik gerçek yüzde + kalan dakika; veri yoksa segmenti gizliyor | Aktif, 1.152 ★, push 2026-08-16 | Yalnızca Claude Code oturumu içinde çalışıyor |
| [ccflare](https://github.com/snipeship/ccflare) | Yerel proxy + dashboard + TUI, Bun | Ağ trafiği, JSONL değil | Çoklu hesap, API key veya OAuth | Rate-limit state + otomatik failover (format doğrulanmadı) | Yavaşlamış, 1.039 ★, push 2026-04-19 | Tüm trafiği üçüncü taraf proxy'den geçirme zorunluluğu; çoklu hesap ToS açısından ayrı sorun |
| [opcode (eski Claudia)](https://github.com/winfunc/opcode) | Tam masaüstü GUI, Tauri 2 + Rust | Claude Code lokal verileri | Belgelenmemiş | Yalnızca token/maliyet analitiği; **5 saatlik veya haftalık limit yüzdesi YOK** | Ölü, 22.383 ★ ama push 2025-10-16 | Limit takibi için yanlış araç; 10 aydır güncellenmemiş |
| [sniffly](https://github.com/chiphuyen/sniffly) | Yerel web dashboard, Python | Lokal JSONL | Yok | Limit yüzdesi yok; hata analizi ve istatistik odaklı | Durgun, 1.261 ★, push 2025-08-08 | ~12 aydır durgun; JSONL şeması o tarihten beri değişti |
| [ccowl](https://github.com/sivchari/ccowl) | Cross-platform status bar, Go | Lokal | Belgelenmemiş | Belgelenmemiş | Terk edilmiş, push 2025-07-14 | Kullanılmamalı |

---

## 3. Veri kaynakları karşılaştırması

### (a) Yerel JSONL parse

**Ne veriyor.** `~/.claude/projects/**/*.jsonl`, satır başına bir olay. Token kullanımı yalnızca `type: "assistant"` satırlarında `message.usage` altında. Bu makinede doğrulandı: 96 MB'lık tek bir oturum dosyasında 8.071 assistant satırının tamamı `message.usage` taşıyor, diğer tiplerin (user, ai-title, mode, last-prompt, custom-title, attachment, queue-operation, system) hiçbirinde yok. Alanlar: `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `cache_creation.{ephemeral_1h,ephemeral_5m}_input_tokens`, `server_tool_use`, `service_tier`, `speed`, `iterations[]`, ayrıca `model`, `version`, `entrypoint`, `sessionId`, `timestamp`.

**Ne vermiyor.** Gerçek plan yüzdesi. Sunucu penceresinin sınırını bilmediğiniz için yalnızca token sayabilir, yüzdeyi tahmin edebilirsiniz. Başka cihazdaki kullanım, claude.ai sohbetleri ve Cowork kullanımı hiç görünmüyor, ama resmi dokümana göre aynı 5 saatlik pencereyi tüketiyorlar ([costs](https://code.claude.com/docs/en/costs)). `costUSD` alanı güncel Claude Code sürümlerinde artık yazılmıyor (96 MB dosyada 0 eşleşme), maliyet araç tarafında fiyat tablosundan hesaplanmak zorunda.

**Auth maliyeti.** Sıfır. Hiçbir credential, hiçbir izin, hiçbir network çağrısı.

**Kırılganlığı.** Orta-yüksek, ama tahmin doğruluğunda yüksek. Somut kanıt: CCUM issue #202'de "ccm counts local tokens only. Activity on another device is invisible. ccm showed 1.4% while the server showed 12% for the same window." CCSeva'da üç açık doğruluk bug'ı var (#23 yanlış %100, #27 yanlış yüzde, #38 dedup çıktı token'ını ~%5 eksik sayıyor). Ayrıca `cleanupPeriodDays` varsayılanı 30, yani veri 30 gün sonra siliniyor ([settings](https://code.claude.com/docs/en/settings)). Şema kayıyor: `costUSD` kalktı, `cache_creation` kırılımı ve `speed` eklendi.

**Blok algoritması notu.** ccusage'ın 5 saatlik bloğu sabit UTC penceresi değil: ilk mesajın timestamp'i `floor_to_hour` ile saat başına yuvarlanıyor ve oradan 5 saat sayılıyor; ayrıca 5 saatten uzun sessizlik de bloğu kapatıp bir "gap block" ekliyor ([blocks.rs](https://github.com/ryoppippi/ccusage)). Bu, Anthropic'in gerçek penceresiyle yapısal olarak farklı bir şey. İkisi arasındaki sapmayı ölçen bir karşılaştırma bulunamadı.

### (b) OAuth `/api/oauth/usage` endpoint'i

**Ne veriyor.** Sunucu doğrusu, cihazdan bağımsız gerçek yüzdeler. Üst seviye alanlar: `five_hour`, `seven_day`, `extra_usage`, ve model bazlı kotalar. Her pencere `utilization` (0-100) ve `resets_at` (ISO 8601 UTC) taşıyor.

**Ne vermiyor.** Token cinsinden ham sayı, proje/model kırılımı, maliyet. Bunlar için yine lokal JSONL gerekli.

**Auth maliyeti.** `Authorization: Bearer <oauth_access_token>` + `anthropic-beta: oauth-2025-04-20`. Token macOS'ta Keychain `Claude Code-credentials` kaydından, Linux/Windows'ta `~/.claude/.credentials.json` dosyasından, veya `CLAUDE_CODE_OAUTH_TOKEN` ortam değişkeninden okunuyor. Belirleyici scope `user:profile`; yalnızca `user:inference` taşıyan CLI token'ları endpoint'i çağıramıyor (CodexBar docs/claude.md:69).

**Kırılganlığı: kategorinin en büyük riski.** Beş ayrı kırılma noktası:

1. **Belgelenmemiş.** claude-quota README'si açıkça yazıyor: "that endpoint is internal to Claude Code and undocumented, so a future Claude Code change may require a small fix here."
2. **Şema zaten kaydı.** claude-quota kaynak kodu (`scoped_limits`): "The API moved per-model weekly quotas out of the top-level seven_day_opus/seven_day_sonnet fields (now always null) into a 'limits' array." Yani toplulukta dolaşan `seven_day_opus` / `seven_day_sonnet` şeması 2026 ortası itibarıyla eskimiş.
3. **Agresif 429.** Issue #31637: 30-60 saniyelik aralıklarda bile rate limit, `Retry-After` başlığı yok, backoff 30s→60s→120s→240s→300s'te takılıp 30+ dakika kalıcı kalıyor. Anthropic yanıtsız kapattı ("closed as not planned", etiketler `invalid` + `stale`). Issue #31021 ise `bug` + `has repro` etiketli olmasına rağmen yine yanıtsız kapatıldı.
4. **Token depolaması garanti değil.** CodexBar: "On Claude Code 2.1.x, `Claude Code-credentials` may contain only MCP server OAuth state (`mcpOAuth`) with no `claudeAiOauth`" ve Claude Code kaydı periyodik rotasyona sokup okuma ACL'ini düşürüyor. Servis adı da sabit değil: `~/.claude` dışında bir `CLAUDE_CONFIG_DIR` kullanılırsa ad `Claude Code-credentials-<sha256'nın ilk 8 hex'i>` oluyor.
5. **Hukuki risk.** Aşağıda bölüm 4'te.

**Piyasa 429'a nasıl cevap veriyor.** Cache ve uzun polling artık ürün tasarımının parçası: CCUM `API_TTL_SECONDS = 180`, jtbr gist 180 sn, ohugonnot `REFRESH_INTERVAL = 300` ("do not set to 0, causes rate limiting"), claude-quota `CACHE_TTL = 240` + 429'da 300 sn backoff, Blimp-Labs varsayılan 30 dakika (5/15/30/60 seçenekli), AI Usage Barometer 1/3/5 dakika. Yani "gerçek zamanlı" iddiası pratikte 1 ila 30 dakikalık gecikme demek.

### (c) Admin API (`/v1/organizations/...`)

**Ne veriyor.** Otoriter, faturayla uyumlu, belgelenmiş, stabil token ve maliyet raporları. `usage_report/messages` (bucket 1m/1h/1d, group_by model/workspace/api_key/service_tier/context_window/inference_geo/speed), `cost_report` (yalnızca 1d, USD cent), `usage_report/claude_code` (kullanıcı başına, `customer_type` alanı abonelik kullanıcılarını da kapsıyor).

**Ne vermiyor.** Abonelik penceresini. 5 saatlik ve haftalık limit yüzdesi bu endpoint'lerde hiç yok. Ayrıca resmi doküman en üstte uyarıyor: **"The Admin API is unavailable for individual accounts"** ([usage-cost-api](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)).

**Auth maliyeti.** `x-api-key` başlığında `sk-ant-admin01-` önekli Admin key, yalnızca Console org'unda admin rolündeki üye üretebiliyor. Bireysel Pro/Max kullanıcısı bu anahtarı üretemez.

**Kırılganlığı.** Düşük ama alakasız. Bu ürün için **kullanılamaz**.

### (d) Messages API rate-limit header'ları

**Ne veriyor.** `anthropic-ratelimit-requests-limit/-remaining/-reset`, `anthropic-ratelimit-tokens-*`, `-input-tokens-*`, `-output-tokens-*`, `retry-after` ([rate-limits](https://platform.claude.com/docs/en/api/rate-limits)).

**Ne vermiyor.** Abonelik penceresi hakkında hiçbir şey. Bu başlıklar organizasyon düzeyindeki RPM/ITPM/OTPM kotalarını ve "usage tier" (Start/Build/Scale/Custom) sistemini ölçer; doküman Pro/Max planlarından hiç bahsetmiyor.

**Auth maliyeti.** API key gerekli, ve zaten kendi isteğinizi atmanız gerekiyor. Bir izleme uygulaması istek atmaz.

**Kırılganlığı.** Alakasız. Bu ürün için **kullanılamaz**. Bunu okuyabilen tek mimari ccflare gibi bir proxy, ki o da kullanıcının tüm trafiğini yönlendirmesini gerektiriyor.

### (e) OpenTelemetry export

**Ne veriyor.** `CLAUDE_CODE_ENABLE_TELEMETRY=1` ile gerçek zamanlı push: `claude_code.token.usage`, `claude_code.cost.usage`, `claude_code.session.count`, `claude_code.active_time.total`, ayrıca `api_request` / `api_error` / `tool_decision` gibi eventler ([monitoring-usage](https://code.claude.com/docs/en/monitoring-usage)).

**Ne vermiyor.** Kota veya limit metriği. `five_hour`, `seven_day`, `utilization`, `resets_at` karşılığı hiçbir metrik yok. Token tüketimi ancak bir proxy sinyal olarak kullanılabilir.

**Auth maliyeti.** Anthropic tarafında sıfır, ama kullanıcının ortam değişkeni ayarlaması ve bir OTLP collector çalıştırması gerekiyor. Menü bar uygulaması için bu ağır bir kurulum.

**Kırılganlığı.** Düşük (resmi ve belgelenmiş), ama yetersiz. Tek başına ürünü kurmaz.

### (f) Bonus: statusline stdin `rate_limits` (kategoride en çok gözden kaçan)

**Ne veriyor.** Resmi, belgelenmiş, sunucu doğrusu: `rate_limits.five_hour.used_percentage` (0-100), `rate_limits.five_hour.resets_at` (Unix epoch), aynısı `seven_day` için. Claude Code 2.1.80 CHANGELOG'unda birebir: "Added `rate_limits` field to statusline scripts for displaying Claude.ai rate limit usage (5-hour and 7-day windows with `used_percentage` and `resets_at`)." Aynı payload'da `model`, `cost.total_cost_usd`, `context_window.used_percentage`, `workspace`, `session_id`, ve daha yeni sürümlerde `fast_mode`, `effort.level`, `session_name`, `worktree.*` da var.

**Ne vermiyor.** Model bazlı haftalık pencereleri (Opus/Sonnet/Fable), `extra_usage` kredilerini. Ayrıca doküman kısıtı net: "appears only for Claude.ai subscribers (Pro/Max) after the first API response in the session. Each window may be independently absent."

**Auth maliyeti.** Sıfır. Hiçbir token okunmuyor, hiçbir istek atılmıyor, hiçbir Keychain'e dokunulmuyor. Kullanıcının tek adımı `settings.json`'a bir `statusLine` komutu eklemek, ki bunu uygulama kendisi yapabilir.

**Kırılganlığı.** Düşük ama zamansal: veri yalnızca Claude Code çalışırken ve ilk API yanıtından sonra akıyor. Uygulama son değeri cache'leyip "X dakika önce" damgasıyla göstermek zorunda. Bağımsız bir menü bar uygulamasının bu stdin'e erişmesinin bilinen tek yolu, statusline komutunu bir dosyaya yazdırıp okumak (CCUM'un `--write-state` deseni).

### Karşılaştırma özeti

| Kaynak | Sunucu doğrusu? | Auth adımı | 429 riski | ToS riski | Kırılganlık | Bu ürün için |
|---|---|---|---|---|---|---|
| Yerel JSONL | Hayır, tahmin | Yok | Yok | Yok | Şema kayması, tek cihaz, 30 gün | Detay ve fallback için gerekli |
| OAuth `/api/oauth/usage` | Evet | Keychain okuma (bu makinede yok) | Yüksek | Yüksek | Belgelenmemiş, şema kaydı | Opsiyonel ikincil |
| Admin API | Hayır (abonelik yok) | Admin key, bireyselde imkânsız | Düşük | Yok | Düşük | Kullanılamaz |
| Rate-limit header'ları | Hayır | API key + kendi isteğin | Yok | Yok | Düşük | Kullanılamaz |
| OpenTelemetry | Hayır (kota metriği yok) | Env + collector | Yok | Yok | Düşük | Yetersiz |
| statusline `rate_limits` | Evet | Bir kerelik settings.json | Yok | Yok | Claude Code açıkken akar | **Birincil olmalı** |

---

## 4. Auth seçenekleri: en kolaydan en zora

| # | Seçenek | Kullanıcı adım sayısı | Ne alıyorsun | Risk |
|---|---|---|---|---|
| 1 | **Lokal JSONL parse** | 0 | Token, maliyet, blok tahmini | Yok. Ama gerçek yüzde yok |
| 2 | **statusline hook, uygulama kendisi kuruyor** | 0 görünür adım (uygulama `~/.claude/settings.json`'a `statusLine` yazıyor, kullanıcı bir kez onaylıyor) | Resmi `five_hour` + `seven_day` yüzde ve reset | Düşük. Kullanıcının mevcut statusline'ını ezme riski var, sarmalamak gerekir. Claude Desktop'ın statusline hook çalıştırıp çalıştırmadığı **doğrulanmadı** |
| 3 | **Keychain OAuth token okuma** | 0 ile 2 arası: kayıt varsa yalnızca bir macOS izin dialogu ("Always Allow"), yoksa kullanıcının `claude` CLI kurup login olması gerekiyor | Sunucu doğrusu tüm pencereler, model bazlı kotalar, extra_usage | Yüksek. İzin kalıcı değil (Claude Code ACL'i rotasyonda düşürüyor), 429, belgelenmemiş endpoint, ToS |
| 4 | **`CLAUDE_CODE_OAUTH_TOKEN` env veya `claude setup-token`** | 2-3 (terminal komutu + kopyala-yapıştır) | Aynısı | Aynı riskler, üstüne terminal bariyeri |
| 5 | **Tarayıcı OAuth akışı (Blimp-Labs deseni)** | 3-4 (tarayıcı açılır, giriş, izin, geri dönüş) | Aynısı | Aynı riskler; ayrıca token'ı kendin saklamak zorundasın |
| 6 | **claude.ai session cookie, DevTools'tan elle** | 6+ (siteye git, DevTools aç, Network sekmesi, yenile, isteği bul, Cookie başlığını kopyala) | claude.ai sohbet kullanımı dahil | Çok yüksek. Cookie hesabın tamamına erişim veriyor, periyodik olarak sürüyor doluyor, iç endpoint habersiz değişiyor |
| 7 | **Admin API key** | 4+ ve bireysel hesapta **imkânsız** | Abonelik penceresi yok | Bu ürün için geçersiz |

**Hukuki uyarı, seçenek 3-6 için geçerli.** Anthropic'in resmi hukuk sayfası ([legal-and-compliance](https://code.claude.com/docs/en/legal-and-compliance)) net: "OAuth authentication is intended exclusively for purchasers of Claude Free, Pro, Max, Team, and Enterprise subscription plans and is designed to support ordinary use of Claude Code and other native Anthropic applications" ve "Anthropic does not permit third-party developers to offer Claude.ai login or to route requests through Free, Pro, or Max plan credentials on behalf of their users." Consumer ToS ayrıca API key dışında script ile erişimi yasaklıyor ([consumer-terms](https://www.anthropic.com/legal/consumer-terms)).

Nüans: 2026'daki fiili yaptırımların tamamı (Ocak 2026 harness spoofing korumaları, 4 Nisan 2026'da OpenClaw/OpenCode/NanoClaw'un abonelik kapsamından çıkarılması) **inference çalıştıran** araçlarla ilgili. Salt okunur bir kullanım monitörüne uygulanmış bir yaptırım örneği bulunamadı. Yine de "User-Agent: claude-code/x.y.z gönder" tavsiyesi lafzen harness spoofing görünümü yaratıyor ve bu tavsiyenin gerekli olduğu da doğrulanmadı (bölüm 6).

---

## 5. Limit mekaniği

### Pencere yapısı

Resmi dokümana göre iki pencere var ve ikisi de yuvarlanan: 5 saatlik pencere ve haftalık pencere. Kota tüm modeller arasında paylaşılıyor, `/model` ile model değiştirmek erişimi geri getirmiyor. Team/Enterprise'da doküman birebir şöyle: "each member's Claude Code usage draws from a per-seat allowance that resets on a rolling five-hour window and a weekly window. The allowance is shared with Claude chat and Cowork" ([costs](https://code.claude.com/docs/en/costs)).

Bu son cümle mimari açıdan kritik: aynı hesabın claude.ai ve Cowork kullanımı aynı 5 saatlik pencereyi tüketiyor ama yerel JSONL'lerde hiç iz bırakmıyor. Yani salt lokal bir mimari **yapısal olarak** eksik ölçüyor.

### Bilinen pencere adları (OAuth endpoint şeması)

| Alan | İçerik | Durum |
|---|---|---|
| `five_hour` | `utilization` 0-100, `resets_at` ISO 8601 UTC | Aktif, statusline'da da var |
| `seven_day` | Aynı | Aktif, statusline'da da var |
| `seven_day_opus` | Eskiden model bazlı haftalık | **Artık daima null**, `limits[]` dizisine taşındı |
| `seven_day_sonnet` | Aynı | **Artık daima null** |
| `limits[]` | `scope.model.display_name` + `percent` + `resets_at` | Güncel model bazlı kota yolu |
| `seven_day_routines`, `seven_day_cowork` | Daily Routines / Cowork pencereleri | CodexBar parse ediyor |
| `extra_usage` | `is_enabled`, `monthly_limit`, `used_credits`, `utilization` | **`resets_at` YOK**, pencere değil |

### Plan bazlı bilinen değerler

Anthropic resmi dokümanlarda limitleri **token cinsinden yayınlamıyor**, yalnızca yüzde veriyor. Dolaşımdaki token rakamları topluluk tahminidir:

| Plan | Token / 5 saat | Maliyet limiti | Mesaj limiti | Kaynak ve güven |
|---|---|---|---|---|
| Pro | 19.000 | $18 | 250 | CCUM `plans.py`, `confidence: "local_estimate"` |
| Max5 | 88.000 | $35 | 1.000 | Aynı |
| Max20 | 220.000 | $140 | 2.000 | Aynı |
| Team | 19.000 | $18 | 250 | Aynı, ayrıca `unverified: True` ve kodda uyarı: "Team limits are unverified estimates" |
| Custom | 44.000 | $50 | 250 | Aynı |

Ayrıca `COMMON_TOKEN_LIMITS = [19_000, 88_000, 220_000, 880_000]` ve `LIMIT_DETECTION_THRESHOLD = 0.95`. 880k rakamı bir plana bağlanmamış.

**Bu rakamlara mimari kararda yaslanmayın.** Kaynağı Anthropic değil, topluluk gözlemi. CCUM'un kendi kodu bunları `local_estimate` diye etiketliyor ve resmi statusline verisi geldiğinde asla kullanmıyor.

Kullanıcı elle limit girmediğinde iki tahmin stratejisi var:
- **P90 (CCUM)**: geçmişte bilinen bir limitin %95'ini geçmiş blokların 90. yüzdebirliği; hiç toslanmamışsa tüm blokların P90'ı; taban 19.000. Dairesel bir varsayım: kullanıcının daha önce duvara toslamış olmasını gerektiriyor.
- **`max` (ccusage)**: geçmişteki en yoğun tamamlanmış blok. Daha da dairesel; hiç limite dayanmamış kullanıcı için anlamsız.

### Belirsizlikler

- Pro/Max planlarının gerçek token tavanı bilinmiyor ve muhtemelen sabit de değil (Anthropic yüzde yayınlıyor olması bunu ima ediyor).
- Anthropic 2026-05-06'da "peak-hour limit reduction" uygulamasını kaldırdı (hamed-elfayome #308). Yeni pencereler ekleniyor: Fable talebi iki ayrı repoda açık (#281, CodexBar #3092).
- `resets_at` semantiği: statusline'da Unix epoch saniye, OAuth endpoint'inde ISO 8601 string. İki kaynağı birleştiren kod ikisini de parse etmek zorunda.
- Claude Code'da bilinen bir sızıntı hatası var (#52326): `used_percentage` alanı bazen gerçek yüzde yerine `resets_at` epoch'unu taşıyabiliyor. CCUM buna karşı savunma yazmış: 101'in üstü epoch büyüklüğündeyse sahte %100 göstermek yerine `None`'a düşürülüyor. Bu savunma kopyalanmalı.

---

## 6. Doğrulama notları

Aşağısı doğrulama çıktısının birebir yansımasıdır. 25 iddianın 24'ü birinci el kaynakla doğrulandı, 1'i çürütüldü; ikinci doğrulama turunda iki iddia daha kısmen çürütüldü.

### CONFIRMED

| İddia | Kanıt |
|---|---|
| Kategori tek bir belgelenmemiş endpoint etrafında dönüyor: `GET https://api.anthropic.com/api/oauth/usage` | Dört bağımsız kaynak kodunda birebir: CCUM `api_usage.py:25`, `claude-quota.5m.py:45`, `claude-codex.60s.sh:24`, claudecodeusage README:83 |
| Endpoint agresif 429 dönüyor ve Anthropic iki issue'yu da yanıtsız kapattı | #31021 (2026-03-05, closed as not planned) ve #31637 (2026-03-06, `invalid` + `stale`, "No Retry-After header", "30+ minutes continuously") |
| Piyasa cevabı agresif cache + uzun polling | CCUM 180s, jtbr 180s, ohugonnot 300s, claude-quota 240s, Blimp varsayılan 30 dk |
| Claude Code ≥2.1.x statusline'a stdin'den `rate_limits` veriyor, menü bar bu stdin'e erişemez | CHANGELOG `## 2.1.80` birebir; resmi statusline dokümanı; CCUM README:1204-1229 `--write-state` protokolü |
| Beş farklı veri kaynağı mimarisi var (JSONL, OAuth, cookie, Admin API, CLI PTY scraping) | CodexBar `docs/claude.md` beşini de belgeliyor; Artzainnn README cookie akışını adım adım tarif ediyor |
| Lokal JSONL yüzdeleri sistematik olarak yanlış | CCSeva #23, #27, #38 (üçü de 2026-08-21 itibarıyla AÇIK); CCUM #202: "ccm showed 1.4% while the server showed 12% for the same window" |
| Native Swift kategoride galip, Electron terk ediliyor | `gh api` dilleri: en popüler 11 aracın tamamı Swift; CCSeva README:13 "The original Electron app is now legacy and being phased out" |
| Pazar kalabalık, 15+ ciddi uygulama | Tüm yıldız ve son push değerleri `gh api` ile birebir eşleşti |
| İkinci büyük şikâyet kümesi auth kırılganlığı | hamed-elfayome #292, #277, #274 hepsi hâlâ AÇIK |
| Limit modeli hızla değişiyor, bakımsız projeler işe yaramaz hale geliyor | #308 (peak-hour kaldırıldı 2026-05-06), #281 ve CodexBar #3092 (Fable talebi); ClaudeMeter/masorange/adntgv/opcode push tarihleri |
| opcode limit takibi için yanlış araç ve terk edilmiş | 22.383 ★ ama `pushed_at 2025-10-16`; README'de yalnızca token/maliyet analitiği, pencere yüzdesi yok |
| En temiz mimari desen: birincil sıfır-network stdin, ikincil cache'lenmiş OAuth | ohugonnot README:43-49 akış şeması birebir |
| SwiftBar/xbar yolu geçerli bir alternatif | claude-quota, AI Usage Barometer, joewongjc doğrulandı |
| CCUM kasten menü bar yapmıyor, boşluğu bırakıyor | README:1229 "Native menu bar and system tray apps are welcome as separate companion projects" |
| JSONL şeması: token yalnızca `type: "assistant"` + `message.usage` | Yerel 96 MB dosya tarandı: 8071/8071 assistant satırı usage taşıyor, diğer tiplerde 0 |
| `costUSD` artık yazılmıyor | Yerel dosyada 0 eşleşme |
| ccusage blok algoritması `floor_to_hour` + 5 saat, sessizlik gap block açıyor | `blocks.rs:73-92` birebir |
| statusline `rate_limits` Claude Code 2.1.80'de eklendi | CHANGELOG birebir |
| CCUM OAuth entegrasyon detayları (URL, TTL 180, beta header, token arama sırası, Retry-After) | `api_usage.py` birebir |
| CCUM plan limitleri hardcoded 19k/88k/220k | `plans.py` birebir |
| P90 algoritması | `p90_calculator.py` birebir |
| ccusage'ın plan bilgisi yok, `--token-limit` veya `max` | `blocks.rs:603-608` + `commands/mod.rs:291-296` |
| Dedup anahtarı `hash(message.id + requestId)` + sidechain için ikinci indeks | `adapters/claude/src/lib.rs:126-200` birebir |
| Keychain servis adı `Claude Code-credentials` ve komutu doğru | jtbr gist, barometer README:64, CCUM #202, resmi IAM dokümanı |

### REFUTED

| İddia | Gerçek |
|---|---|
| **claude-quota "read-only, it never refreshes or rewrites tokens"** | Kod bunu çürütüyor: `claude-quota.5m.py` başlık yorumu satır 10-16 "the plugin runs the standard OAuth refresh-token flow itself and writes the refreshed credentials back to the Keychain"; kodda `OAUTH_TOKEN_URL`, `OAUTH_CLIENT_ID` ve `write_creds()` var. Yalnızca README bayat kalmış. **Güvenlik değerlendirmesinde README'ye değil koda bakın.** |
| **OAuth şeması: `five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet`, `extra_usage`, her biri `utilization` + `resets_at`** | Üç hata: (1) `extra_usage` bir pencere değil, `resets_at` içermiyor, alanları `is_enabled`/`monthly_limit`/`used_credits`/`utilization`. (2) Model bazlı kotalar `limits[]` dizisine taşındı, `seven_day_opus`/`seven_day_sonnet` artık daima null. (3) Scope koşulu yanlış: belirleyici olan `user:profile`, yalnızca `user:inference` taşıyan token endpoint'i çağıramıyor |
| **macOS'ta Keychain okuma = sıfır sürtünme** | Dört karşı kanıt: (1) `~/.claude/.credentials.json` resmi dokümanda yalnızca Linux/Windows için listeleniyor, macOS'ta yok. (2) macOS ilk okumada izin dialogu çıkarıyor ("choose Always Allow"), yani kullanıcıdan bir şey isteniyor. (3) Claude Code kaydı rotasyona sokup ACL'i düşürüyor, izin kalıcı değil. (4) 2.1.x'te kayıt yalnızca `mcpOAuth` içerebiliyor. **Ayrıca bu makinede kayıt hiç yok** |
| **getAsterisk/claudia adresi 404 dönüyor** | `301 → https://github.com/winfunc/opcode`. Normal repo transfer yönlendirmesi, silinmemiş |

### UNVERIFIABLE / doğrulanmadı

| İddia | Durum |
|---|---|
| **`User-Agent: claude-code/<version>` başlığı 429 yememek için kritik** | Birinci el değil. Yalnızca CCUM #202'de bir topluluk gözlemi. Çalışan üç araç (claude-quota, jtbr gist, AI Usage Barometer'ın Claude yolu) bu başlığı hiç göndermiyor; CCUM'un gönderdiği değer çoğu kurulumda `claude-code/unknown`. Optimizasyon olabilir, zorunluluk olduğu doğrulanmadı |
| Claude Code'un kendi `/usage` ekranının aynı endpoint'i kullandığı | Yalnızca dolaylı kanıt: #31021'in `area:statusline` etiketi ve CHANGELOG'daki "Fixed /usage returning 'rate limited' after a stale OAuth token". Anthropic dokümanında yazmıyor. Doküman "the usage endpoint is rate limited" diyerek ayrı bir sunucu çağrısı olduğunu kabul ediyor ama endpoint'i adlandırmıyor |
| Usagebar ve AgentPeek'in teknoloji stack'i | Kapalı kaynak, sitelerde belirtilmemiş |
| AgentPeek Claude için sunucu doğrusu yüzde veriyor mu | Belirsiz, açıklaması "token kullanım pencereleri" dilinde |
| "Usage for Claude" App Store uygulamasının auth mekanizması | Cookie mi OAuth mu belirsiz; App Store sandbox altında Keychain'e erişip erişemediği açık soru |
| Usage4Claude'un çağırdığı endpoint | README'de yazmıyor |
| CCSeva'nın Swift geçişinin tamamlanıp tamamlanmadığı | Repo'da Electron ve `swift/` dosyaları yan yana, GitHub birincil dili hâlâ TypeScript |
| ccflare'in rate-limit state'i header'dan mı 429'dan mı okuduğu | Yalnızca README iddiası, kaynak kod okunmadı |
| ccowl'un "terk edilmiş" durumu | İkinci turda doğrulanmadı |
| ccusage fiyat tablosunda olmayan modelde ne yapıyor | `enable_embedded_models_dev_fallback` bayrağı var ama fallback zinciri izlenmedi |

**Not.** Doğrulama çıktısının ikinci turu iletimde kesildi; yukarıdaki tablo kesintiye kadar aktarılan verdict'leri kapsıyor. Kesilen kısımda kalan iddialar bu raporda kullanılmadı.

---

## 7. Açık sorular ve makinede test edilmesi gerekenler

**Karar öncesi mutlaka test edilmeli:**

1. **Claude Desktop statusline hook çalıştırıyor mu?** Bu ürün için hayati soru. Bu kullanıcıda `claude` CLI yok, tüm kullanım `entrypoint: claude-desktop`. `settings.json`'a bir `statusLine` komutu yazıp `/tmp`'ye timestamp düşürerek 10 dakikada test edilebilir. Cevap hayırsa Tavsiye bölümündeki mimarinin birincil katmanı bu makinede boş kalır.
2. **Claude Desktop kullanıcısında OAuth token nerede duruyor?** Keychain'de yalnızca `Claude Safe Storage` (Electron safeStorage) ve `Claude Key` var. Bu kayıtların Anthropic OAuth access token'ı içerip içermediği ve programatik okunabilirliği test edilmeli. Uyarı: Electron safeStorage'ı deşifre etmek başka bir uygulamanın credential'ını açmak demek, hem teknik hem etik olarak ayrı bir eşik.
3. **`/api/oauth/usage` gerçek rate limit bütçesi nedir?** Anthropic dokümante etmedi, `Retry-After` yok, iki issue yanıtsız kapandı. Topluluğun ampirik uzlaşısı 3-5 dakika ama gerçek eşik bilinmiyor. Kendi token'ınızla 60s / 180s / 300s aralıklarında ölçülebilir.
4. **`User-Agent` başlığı gerçekten fark yaratıyor mu?** Aynı token ile başlıklı ve başlıksız iki seri istek. Sonuç "hayır" ise, harness spoofing görünümü veren bu başlığı hiç göndermemek ToS riskini düşürür.
5. **statusline `rate_limits` ile lokal JSONL bloğu ne kadar sapıyor?** İkisi yapısal olarak farklı şey ölçüyor (Anthropic'in penceresi vs `floor_to_hour` ile kayan pencere). Sapmayı ölçen bir karşılaştırma literatürde bulunamadı. "Lokal tahmin ne kadar güvenilir" sorusunun tek gerçek cevabı bu.

**Ürün kararını etkileyen açık sorular:**

6. Salt okunur bir kullanım monitörü Anthropic'in ToS'una aykırı mı? Yaptırım örnekleri yalnızca inference çalıştıran harness'lara ait. Ne izin ne yasak açıklaması var.
7. Anthropic'in güncel resmi pencere listesi nedir? Peak Hours kaldırıldı, Fable eklendi, `limits[]` şeması değişti. Kanonik bir liste yok.
8. `usage_limit_reset_time` alanı JSONL'de hangi ham alandan geliyor? ccusage `SessionBlock`'ta taşıyor ama adapter parse kodu izlenmedi. Limit hatası anında reset zamanını lokal olarak yakalayabilmek fallback için değerli olurdu.
9. CodexBar'ın 429 handling stratejisi nedir? 20.4k yıldızlı lider aracın polling aralığı ve backoff davranışı belgelenmemiş, kaynak koda bakmak gerekiyor.
10. Kullanıcının mevcut `statusLine` ayarı varsa nasıl sarmalanır? Şu an bu makinede `settings.json` 39 byte ve `statusLine` yok, yani temiz kurulum mümkün. Ama genel kullanıcı için ezmeme stratejisi tasarlanmalı.

---

## 8. Tavsiye

### Hangi mimari

**Üç katmanlı, güven etiketli, statusline birincil.** Sıra kategorideki herkesten farklı olmalı:

**Katman 1, birincil: statusline köprüsü.** Uygulama kurulumda `~/.claude/settings.json`'a kendi `statusLine` komutunu yazar (mevcut komut varsa onu sarmalayıp çıktısını aynen geçirir). Bu komut stdin JSON'undan `rate_limits`'i alıp atomik olarak `~/Library/Application Support/<app>/ratelimits.json` dosyasına yazar ve orijinal statusline çıktısını basar. Menü bar uygulaması bu dosyayı izler.

Neden birincil: resmi ve belgelenmiş, sunucu doğrusu, sıfır network, sıfır 429, sıfır credential okuma, sıfır ToS riski, kullanıcı için sıfır görünür adım.

**Katman 2, ikincil ve opsiyonel: OAuth usage endpoint.** Varsayılan KAPALI. Ayarlarda "model bazlı haftalık kotalar ve ekstra kullanım kredileri için gelişmiş mod" olarak sunulur, açıklamasında endpoint'in belgelenmemiş olduğu ve Anthropic'in bunu desteklemediği yazılır. Açıldığında: minimum 300 saniye polling, `Retry-After` desteği, 429'da agresif backoff, salt okunur token erişimi, token yenileme veya geri yazma YOK.

Neden ikincil: `limits[]` model bazlı kotalar ve `extra_usage` yalnızca burada var, ama 429, belgelenmemişlik ve ToS riski birincil olmasını engelliyor.

**Katman 3, taban: lokal JSONL.** Her zaman açık. İki iş yapar: (a) hiçbir sunucu verisi yokken kaba bir tahmin, (b) sunucu verisi varken bile onun sağlayamadığı kırılımı verir: model, proje, burn rate, maliyet, blok geçmişi.

**Her sayı kaynağına göre etiketlenir.** CCUM'un `official` / `experimental` / `local_estimate` deseni kopyalanır ve UI'da görünür olur. Taze resmi veri asla tahminle ezilmez. Bayat veri "3 dakika önce" damgasıyla gösterilir, sessizce eski değer servis edilmez.

**Ürün kararı: yüzde değil geri sayım.** %70'in altında yüzde göster, üstünde birincil metriği "sonraki pencere N dakika sonra açılıyor"a çevir. Usagebar'ın bunu yaptığı, en popüler rakipte ise bunun hâlâ açık bir talep olduğu doğrulandı.

**Stack: Swift 6 + SwiftUI + AppKit (`NSStatusItem` / `NSPopover`), Swift Charts.** Kategorideki en popüler 11 aracın tamamı Swift, CCSeva Electron'dan aktif olarak kaçıyor ("~3 MB installed with zero runtime dependencies"). Bu tartışmalı bir seçim değil.

### Neden bu, alternatifleri neden değil

| Alternatif | Neden değil |
|---|---|
| Salt OAuth (Usagebar, claudecodeusage deseni) | Bu kullanıcının makinesinde Keychain kaydı YOK, uygulama açılışta boş ekran verir. Üstüne 429, belgelenmemiş şema, ToS |
| Salt lokal (aqua5230, penicillin0 deseni) | claude.ai ve Cowork kullanımı aynı pencereyi tüketiyor ama JSONL'de görünmüyor. Resmi doküman bunu açıkça yazıyor. Yapısal olarak yanlış sayar |
| Cookie tabanlı (Artzainnn, ClaudeMeter deseni) | 6+ adımlık DevTools akışı, "auth mümkün olduğunca kolay" hedefinin tam zıddı. Cookie hesabın tamamına erişim veriyor |
| Admin API | Bireysel hesaplarda kullanılamaz, üstelik abonelik penceresini hiç göstermiyor |
| Proxy (ccflare deseni) | Kullanıcının tüm trafiğini yönlendirmesi gerekiyor, kabul edilemez kurulum maliyeti |

### Hangi risk

**Risk 1, en yüksek: Katman 1 bu makinede çalışmayabilir.** Claude Desktop'ın statusline hook çalıştırıp çalıştırmadığı doğrulanmadı. Kod yazmadan önce bölüm 7'deki 1 numaralı test yapılmalı. Cevap hayırsa mimari yeniden düşünülür: bu durumda Katman 2 ile Katman 3 yer değiştirir ve ürün "gerçek yüzde" iddiasını yumuşatmak zorunda kalır.

**Risk 2: statusline ayarını ezme.** Kullanıcının mevcut `statusLine` yapılandırmasını bozmak kabul edilemez bir yan etki. Sarmalayıcı yaklaşımı zorunlu, ve kurulum geri alınabilir olmalı.

**Risk 3: Katman 2'nin ToS durumu belirsiz.** Varsayılan kapalı olması ve açıklamasında riskin yazılı olması bunu kullanıcının bilinçli tercihine dönüştürür. Uygulama asla token yenilemez, yeniden yazmaz, üçüncü bir sunucuya hiçbir şey göndermez. Bu ayrım claude-quota'nın README ile kodu arasındaki tutarsızlıktan öğrenilen derstir.

**Risk 4: Pazar doygun.** 15+ açık kaynak rakip ve iki ticari ürün var. Bu ürünün farkı özellik sayısı olamaz, doğruluk ve dürüstlük olmalı: kaynağı etiketlenmiş sayılar, veri yokken sahte yüzde üretmeme, ve "ne zaman devam edebilirim" sorusunu doğrudan cevaplama.

**Risk 5: Şema kayması.** 2026'da `seven_day_opus` null'landı, `limits[]` geldi, Peak Hours kaldırıldı, Fable eklendi. Bilinmeyen alan geldiğinde çökmemek ve bilinen alan kaybolduğunda o göstergeyi gizlemek (claude-powerline'ın yaptığı gibi) tasarım gereği olmalı, sonradan eklenen bir yama değil.
