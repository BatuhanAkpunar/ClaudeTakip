# Claude Limit Takibi | Ürün Spesifikasyonu v2

**Durum:** karar verilmiş taslak, uygulanmaya hazır
**Tarih:** 21 Ağustos 2026
**Girdi:** kullanıcı spec v1 (öneri olarak alındı) + ekosistem araştırması + kullanıcı makinesinde yapılan doğrulamalar
**Değiştirir:** spec v1'in 2., 3., 8. ve 12. bölümleri

---

## 0. v1'e göre ne değişti, neden

v1 yazılırken bilinmeyen tek şey şuydu: **gerçek limit yüzdesi nereden gelecek?** Araştırma ve makine üzerinde yapılan doğrulama bu sorunun cevabını değiştirdi ve cevap, ürünün mimarisini de kararlarını da değiştiriyor.

| # | v1 varsayımı | Bulgu | v2 kararı |
|---|---|---|---|
| 1 | Veri claude.ai'den çekilecek, bir tür giriş gerekecek | Claude Desktop gerçek kota yüzdelerini zaten diske yazıyor | Sıfır auth. Giriş ekranı yok |
| 2 | Menubar'da 5 saatlik limit olmalı | Kullanıcının 25 günlük gerçek verisi: canını yakan haftalık limit | Menubar kritik olan pencereyi gösterir |
| 3 | Fable kullanımı gösterilecek | Yerel kaynakta model bazlı kota yok | Kart kalır, "tahmini" etiketiyle |
| 4 | Reset olunca otomatik "hi" gönderilecek | Anthropic üçüncü taraf inference'ı açıkça yasaklıyor | MVP'den çıkarıldı, yerine bildirim |
| 5 | Popup mockup düzeninde | Mockup 1520px genişliğinde web düzeni | Tek sütun, 380pt popover |

---

## 1. Ürün tanımı

macOS menü çubuğunda çalışan, Claude abonelik limitlerini **gerçek sunucu verisiyle** takip eden bir uygulama.

**Tek cümlelik konum:** Rakiplerin belgelenmemiş bir API'yi kimlik bilgisiyle yoklayarak elde ettiği veriyi, bu uygulama hiçbir kimlik bilgisine dokunmadan diskten okur.

**Ana prensip (v1'den korundu):** Minimum bilgi, maksimum kullanım farkındalığı.

---

## 2. Mimari kararı: üç katmanlı veri

### Katman A: gerçek kota yüzdesi (birincil)

**Kaynak:** `~/Library/Application Support/Claude/plan-usage-history.json`

Claude Desktop bu dosyayı kendi kotasını takip etmek için yazıyor. Kullanıcının makinesinde doğrulandı:

```
{
  "version": 2,
  "samples": [
    { "t": 1787344332573, "org": "00000000-...", "u": { "fh": 48, "sd": 97, "xu": 100 } }
  ]
}
```

| Alan | Anlamı | Doğrulama |
|---|---|---|
| `t` | epoch ms | doğrulandı |
| `org` | organizasyon kimliği | doğrulandı, tek org |
| `u.fh` | 5 saatlik pencere kullanımı, 0-100 | doğrulandı: 0'a düşüşler tam 5 saatlik döngüyle örtüşüyor |
| `u.sd` | 7 günlük pencere kullanımı, 0-100 | doğrulandı: 3 hafta üst üste cumartesi ~10:00'da sıfırlanmış |
| `u.xu` | ek kullanım (extra usage) | kısmen: 3466 örneğin sadece 321'inde var ve hep 100. Anlamı netleşmeden **gösterilmeyecek** |

**Ölçülen davranış:** 3466 örnek, 25,4 gün geçmiş, medyan örnekleme aralığı **300 saniye** (p90 900 sn).

**Neden birincil:**
- Auth yok, ağ isteği yok, kimlik bilgisi okunmuyor, 429 riski yok, kullanım şartları riski yok.
- Rakiplerin tamamının bağlı olduğu `GET /api/oauth/usage` endpoint'i belgelenmemiş, agresif 429 dönüyor ve Anthropic ilgili iki hata kaydını da yanıtsız kapatmış.
- Bu makinede OAuth yolu zaten **çalışmıyor**: `claude` CLI kurulu değil, Keychain'de `Claude Code-credentials` kaydı yok, `.credentials.json` yok.

**Bilinen zayıflığı:** dosya yalnızca Claude Desktop açıkken güncelleniyor. Desktop kapalıyken veri yaşlanır. Ürün bunu gizlemeyecek, açıkça gösterecek (bkz. §7).

### Katman B: aktivite detayı

**Kaynak:** `~/.claude/projects/**/*.jsonl`

Makinede doğrulandı: 785 dosya, 42.668 benzersiz istek, 1,8 GB, tam parse **2 saniye**.

Her `type: "assistant"` satırında `message.usage` altında: `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens_details.thinking_tokens`, ayrıca `model`, `timestamp`, `requestId`, `sessionId`.

**Ne için kullanılır:** En Aktif Saatler, model dağılımı, oturum yoğunluğu, Fable payı tahmini.
**Ne için kullanılmaz:** limit yüzdesi. Bu dosyalar claude.ai sohbetlerini ve Cowork kullanımını görmez, dolayısıyla yapısal olarak eksik ölçer. Araştırmada somut örnek: yerel hesap %1,4 gösterirken sunucu %12 diyordu.

### Katman C: OAuth endpoint (opsiyonel, varsayılan kapalı)

**Kaynak:** `GET https://api.anthropic.com/api/oauth/usage`

Yalnızca Katman A'nın veremediği tek şey için: `limits[]` dizisindeki **model bazlı haftalık kotalar** (Fable, Opus).

Varsayılan **kapalı**. Ayarlarda açılırsa ne yapacağı ve riski açıkça yazılır. Bu makinede gerekli token bulunmadığı için MVP'de zaten devre dışı kalacak.

### Katman kararı özeti

| Katman | Auth | Ne verir | Tazelik | MVP |
|---|---|---|---|---|
| A: plan-usage-history | yok | gerçek 5s + haftalık % | 5 dk | evet, birincil |
| B: JSONL | yok | aktivite, model, saat dağılımı | anlık | evet |
| C: OAuth | token gerekir | model bazlı kotalar | anlık | hayır, faz 3 |

---

## 3. Menü çubuğu

v1: "menubar'da yalnızca 5 saatlik limit olmalı, haftalık gösterilmemeli."

**Değişiklik gerekçesi.** Kullanıcının kendi 25 günlük verisi bunun tersini söylüyor:

- 5 saatlik pencere 25 günde yalnızca 1 kez %100'e ulaşmış.
- Haftalık pencere **art arda iki hafta %100'e** çarpmış (8 ve 15 Ağustos) ve şu an %97'de.
- Yani kullanıcıyı gerçekten durduran şey haftalık limit, ama v1 tasarımında haftalık limit menü çubuğunda hiç görünmüyor.

**Karar: menü çubuğu iki pencereden kritik olanı gösterir.**

```
◔ 48%          normal durum, 5 saatlik pencere
◕ 97% H        haftalık kritik, "H" rozeti
◕ 1s 12d       %85 üstünde yüzde yerine geri sayım
```

Kural:
1. Varsayılan gösterim: yüzdesi yüksek olan pencere.
2. Haftalık gösteriliyorsa yanına ince bir `H` rozeti gelir, hangi pencereye baktığın belirsiz kalmaz.
3. Kullanım %85'i geçtiğinde yüzde yerine **resetlenmeye kalan süre** gösterilir. Bu noktada kullanıcının sorusu "ne kadar kullandım" değil, "ne zaman devam edebilirim" olur.
4. Ayarlardan sabitlenebilir: her zaman 5 saatlik, her zaman haftalık, veya otomatik (varsayılan).

Gösterge, metin genişliği zıplamasın diye monospaced rakamla çizilir.

---

## 4. Popover

Mockup'ın bilgi mimarisi doğru, düzeni bu ürün için yanlış: 1520px genişliğinde iki sütunlu web düzeni. Menü çubuğu popover'ı **380pt** genişliğinde, tek sütun olmalı.

```
┌─ 380pt ──────────────────────────────┐
│ Claude Limit      ● 2 dk önce    ⚙︎  │  header
├──────────────────────────────────────┤
│ 5 SAATLİK          2s 12d sonra sıfır│
│  ◔ 48%    1,3×     ▁▂▃▅▆▇┊╌╌╌        │  donut + hız + sparkline
├──────────────────────────────────────┤
│ HAFTALIK            Cmt 10:00        │
│  ◕ 97%    1,1×     ▁▂▄▅▆▇█┊╌╌ ⚠︎     │  aşım uyarısı
├──────────────────────────────────────┤
│ EN AKTİF SAATLER                     │
│  ▁▁▂▃▅▇█▇▅▃▂▁▁                       │
│  00      12      24                  │
├──────────────────────────────────────┤
│ Fable  tahmini            %72  0,9×  │  ince satır
└──────────────────────────────────────┘
```

### Kart yapısı

Her limit kartı dört bilgiyi tek satırda taşır: **yüzde** (donut), **hız** (ortalamaya göre kaç kat), **eğri** (geçmiş + kesikli projeksiyon), **reset** (başlıkta).

- Donut 56pt. Mockup'taki 120pt+ halkalar popover'da yer israfı.
- Projeksiyon ayrı bir alan değil, eğrinin kesikli devamı. v1 bunu doğru söylüyor, korunuyor.
- Limit bu hızla aşılacaksa eğrinin kesişim noktasında `⚠︎` ve altında tek satır: `Bu hızla 01:40'ta dolar`.

### Fable satırı

Model bazlı gerçek kota yalnızca Katman C'de var, o da kapalı. Ama Fable payı **yerel token verisinden hesaplanabiliyor**: kullanıcının 42.668 isteğinin 5.493'ü `claude-fable-5`.

Karar: kart kalır, değer `Fable token payı × haftalık kullanım` ile tahmin edilir ve yanında **"tahmini"** etiketi durur. Katman C açılırsa etiket kalkar, gerçek değer gelir. Uydurma sayıyı kesin gibi göstermek yok.

### Header

Logo, "Claude Limit", son güncelleme, servis durumu ikonu, ayarlar. v1 ile aynı, tek fark: **son güncelleme sadece bir zaman değil, bir sağlık göstergesi** (bkz. §7).

---

## 5. Tahminleme

Rakiplerin çoğu token sayılarından limit tahmin ediyor, çünkü ellerinde gerçek yüzde yok. Bizde 5 dakikalık çözünürlükte **gerçek yüzde serisi** var, dolayısıyla doğrudan onun üzerinden projeksiyon yapılır.

- **Hız:** son 30 dakikadaki yüzde artışı / saat.
- **Karşılaştırma katsayısı:** bu hız, aynı pencere türündeki geçmiş ortalamanın kaç katı. Mockup'taki `1,3×` bu.
- **Projeksiyon:** mevcut hız pencerenin sonuna kadar sürerse ulaşılacak yüzde. Üstel ağırlıklı ortalama kullanılır, tek bir yoğun dakika tüm tahmini bozmasın.
- **Aşım:** projeksiyon 100'ü geçiyorsa 100'e ulaşılacak saat hesaplanır.

Sıfırlanma zamanları dosyada yok, türetiliyor:
- **5 saatlik:** `fh` 0'a düştükten sonra ilk `fh > 0` örneği pencerenin başlangıcıdır, reset = başlangıç + 5 saat. Kullanıcının verisiyle doğrulandı: 20 Ağustos 11:10 → 16:10 tam 5 saat.
- **Haftalık:** `sd` düşüşlerinden öğrenilir. Kullanıcıda üç hafta üst üste cumartesi ~10:00. Sabit varsayılmaz, her hafta gözlemden güncellenir.

---

## 6. Geçmiş ve kalıcılık

**SQLite (GRDB.swift).** Ücretsiz, yerel, tek dosya, bulut yok.

Neden gerekli: `plan-usage-history.json` Claude Desktop'a ait, ne kadar geriye tuttuğu bizim kontrolümüzde değil ve bir gün budanabilir. Uygulama her okumada yeni örnekleri kendi veritabanına aktarır, böylece geçmiş kalıcı olur.

Saklanan: kota örnekleri, türetilen pencere sınırları, saatlik aktivite kovaları, ayarlar. İlk açılışta mevcut 25 günlük geçmiş toplu olarak içe aktarılır, yani uygulama **ilk saniyeden dolu grafiklerle** açılır.

v1 §6'daki gibi bu ekran MVP'de birinci sınıf değil, veri modeli hazır tutulur.

---

## 7. Tazelik ve güvenilirlik

Katman A'nın tek zayıflığı: Claude Desktop kapalıyken dosya güncellenmez. Ürün bunu gizlemez.

| Yaş | Gösterim |
|---|---|
| < 10 dk | `● 2 dk önce`, yeşil nokta |
| 10-45 dk | `● 22 dk önce`, sarı nokta |
| > 45 dk | `● eski veri`, gri nokta, yüzdeler soluk çizilir |

Yüzdeler asla silinmez, asla sıfırlanmış gibi gösterilmez. Eskiyse eski olduğu söylenir. Bu, "gerçek zamanlı" iddia edip 30 dakikalık önbellek gösteren rakiplerden ayrıştığımız yer.

Dosya `FSEvents` ile izlenir, değişince okunur. Yoklama yok.

---

## 8. Otomatik "hi" mesajı: MVP'den çıkarıldı

v1 §8, 5 saatlik pencere sıfırlandığında hesabından otomatik `hi` mesajı gönderilmesini istiyor. Bunu MVP'ye koymuyorum, üç gerekçeyle:

1. **Anthropic bunu açıkça yasaklamış.** Araştırmada doğrulandı: hukuki uyum sayfası üçüncü taraf ürünlerin kullanıcı adına Free/Pro/Max kimlik bilgileriyle istek yönlendirmesini yasaklıyor. Salt okunur izleme gri bölgede, ama hesap üzerinden mesaj göndermek doğrudan yasağın hedefi.
2. **Senin adına mesaj gönderiyor.** Sen başlatmadan, sen görmeden. Bunu bir ürünün arka planda yapmasının doğru yolu yok.
3. **Kotanı harcıyor.** Pencereyi erken açmak, o pencereyi gerçekten kullanacağın saatten koparır.

**Yerine:** pencere sıfırlandığında bildirim gönderilir, üstünde tek aksiyon: **Claude'u aç**. Sen tıklarsın, pencere senin ilk mesajınla başlar. Aynı sonuç, karar sende.

Bunu yine de otomatik istersen, ayrı bir konuşmada ele alalım. Kapalı kapı değil, ama MVP'ye varsayılan olarak girmemeli.

---

## 9. Ayarlar

Rakiplerden alınan, işe yarayanlar:

| Ayar | Varsayılan |
|---|---|
| Menü çubuğu gösterimi: otomatik / 5 saatlik / haftalık | otomatik |
| %85 üstünde geri sayıma geç | açık |
| Girişte başlat | kapalı |
| Bildirim: pencere sıfırlandı | açık |
| Bildirim: %80 ve %95 eşikleri | açık |
| Veri yaşlandı uyarısı | açık |
| OAuth ile model bazlı kotalar (deneysel) | kapalı |
| Görünüm: sistem / açık / koyu | sistem |

Dil: MVP Türkçe ve İngilizce. v1'de 14 dil vardı, MVP için gereksiz yük.

---

## 10. Teknoloji

| Katman | Seçim |
|---|---|
| Dil | Swift 6.3, strict concurrency |
| UI | SwiftUI, AppKit `NSStatusItem` |
| Menü çubuğu | `LSUIElement`, Dock ikonu yok |
| Grafik | Swift Charts + projeksiyon için özel çizim |
| Veri | GRDB.swift (SQLite) |
| Dosya izleme | `DispatchSource` / FSEvents |
| Proje | XcodeGen, macOS 15+ |
| İmza | geliştirme için ad-hoc, dağıtımda notarize |

Sandbox **kapalı**. Sandboxed bir uygulama `~/.claude` ve başka bir uygulamanın Application Support klasörünü okuyamaz. Mac App Store hedefi yok, DMG dağıtımı var.

Doğrulandı: hedef dosya `0600`, dizin `0700`, kullanıcının kendi sahipliğinde. Sandbox dışı bir uygulama Full Disk Access istemeden okuyabilir. Build sonrası gerçek uygulamayla teyit edilecek.

---

## 11. Başarı ölçütü

v1 §13 korundu, üstüne bir madde eklendi:

Kullanıcı 3 saniyede: ne kadar kullandım, ne hızla kullanıyorum, ne zaman sıfırlanır, bu hızla aşar mıyım.
Menü çubuğuna bakarak popover açmadan: şu an hangi limit beni gerçekten sıkıştırıyor ve ne kadar kaldı.

**Eklenen:** Kullanıcı uygulamayı ilk açtığında **hiçbir giriş ekranı görmez** ve ekran boş değil, 25 günlük geçmişle dolu gelir.

---

## 12. Fazlar

| Faz | İçerik | Çıktı |
|---|---|---|
| 1 | Veri çekirdeği: iki okuyucu, türetme, SQLite, CLI doğrulama | Sayıların doğruluğu kanıtlanır |
| 2 | Menü çubuğu + popover, iki limit kartı, tazelik durumları | Kullanılabilir uygulama |
| 3 | En Aktif Saatler, Fable satırı, projeksiyon eğrisi, bildirimler | Spec tamamlanır |
| 4 | Ayarlar, Türkçe/İngilizce, ikon, DMG | Dağıtılabilir |

Faz 1 önce geliyor çünkü bu üründe en büyük risk arayüz değil: **türetilen reset zamanlarının ve projeksiyonun gerçekten doğru olması.** Arayüzü doğru sayının üstüne kurmak, yanlış sayıyı güzel göstermekten kolay.

---

## 13. Açık riskler

| Risk | Etki | Karşılık |
|---|---|---|
| Claude Desktop dosya formatını değiştirir | Birincil kaynak kırılır | `version` alanı okunur, tanınmayan sürümde Katman B'ye düşülür ve kullanıcıya söylenir |
| Desktop kapalıyken veri yaşlanır | Yüzde eskir | Tazelik durumu açıkça gösterilir, gizlenmez |
| `xu` alanının anlamı bilinmiyor | Yanlış bilgi riski | MVP'de gösterilmiyor |
| Fable tahmini sapabilir | Güven kaybı | "tahmini" etiketi kalıcı, Katman C açılınca kalkar |
| Haftalık %50 Fable bonusu 31 Ağustos'ta bitebilir | Limit varsayımları bayatlar | Sabit limit varsayımı yok, her şey sunucudan gelen yüzdeye dayanıyor |
