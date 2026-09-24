# İstatistik incelemesi: "En Aktif Saatler" ve "pace"

Kapsam: `UsageProfile`, `Projection`, `WindowDeriver`, `UsageStore` profil besleme
zinciri, `HourDial`, bulut şeması. Soru "kod temiz mi" değil, "bu sayı iddia
ettiği şeyi ölçüyor mu".

Yöntem: kod okuma + sayısal karşı-örnek (Python ile `UsageProfile.build`,
`baselineRate`, `currentRate`, `expectedRemaining` birebir port edilip
çalıştırıldı). Spekülasyon olan yerler açıkça "SPEKÜLASYON" diye işaretli.

---

## 1. Özet: en kritik üç bulgu

**1. Haftalık pencerenin tahmini boyut hatası içeriyor (birim uyuşmazlığı).**
`UsageProfile` yalnızca 5 SAATLİK pencerenin yüzde deltalarından kuruluyor
(`UsageProfile.swift:69`), ama aynı profil haftalık pencerenin tahmininde de
kullanılıyor (`UsageStore.swift:411` → `Projection.swift:63-66`). 5 saatlik
yüzde ile 7 günlük yüzde aynı ölçek değil. Sayısal örnek: aktif saatlerinde
12 puan/saat harcayan bir kullanıcıda 4 gün kalan haftalık pencere için
`expectedRemaining` **384 puan** üretiyor ve bu doğrudan haftalık yüzdeye
ekleniyor. Sonuç: profili güvenilir olan hemen her kullanıcıda haftalık kart
kalıcı olarak "Tahmini Aşım" gösteriyor.

**2. `baselineRate` kullanıcının hızını değil, ÖRNEKLEME ARALIĞINI ölçüyor.**
`Projection.swift:188-198`, yalnızca delta>0 olan aralıkları hem paya hem
paydaya alıyor. Yüzde tam sayı olduğu için (`QuotaSample.swift:11`) yavaş bir
kullanıcıda çoğu 5 dakikalık aralık 0 delta, arada bir 1 puanlık tik geliyor.
Aynı gerçek hız (6 puan/saat) için ölçülen taban:

| örnek aralığı | baselineRate |
|---|---|
| 1 dk | 60,00 %/saat |
| 5 dk | 12,00 %/saat |
| 10 dk | 5,76 %/saat |

Taban ≈ `1 puan / örnek_aralığı`. Kullanıcının hızıyla neredeyse ilgisiz.
Bulut senkronu iki cihazın örneklerini tek arşivde birleştirdiği için
(`UsageStore.swift:214-228`) efektif aralık yarıya iniyor ve taban iki katına
çıkıyor, yani ikinci cihazı bağlayan kullanıcının pace'i sebepsiz yarıya
düşüyor.

**3. "En yoğun saat" nadir patlama yapılan saati seçiyor.** Payda, o saatin
gözlendiği gün değil, o saatte TÜKETİM OLDUĞU gün sayısı
(`UsageProfile.swift:71` guard'ından sonra `:84` insert). Yani hourly[h] =
E[tüketim | o saatte tüketim var]. Karşı-örnek: 20 gün boyunca her gün 14:00'te
20 puan, buna karşılık tek bir gecede 03:00'te 40 puan.

```
hourly[3]  = 36,0  (n = 1 gün)
hourly[14] = 18,0  (n = 20 gün)
peakHour   = 3          <-- kadranın merkezinde "03:00 en yoğun" yazıyor
gerçek 20 günlük toplam: saat 3 = 36 puan, saat 14 = 360 puan
```

Gerçekte 14:00 saati 10 kat baskın, kadran 03:00 diyor.

---

## 2. Bulgular

### A. "En Aktif Saatler" (saatlik profil)

---

#### A1. [KRİTİK] Profil 5 saatlik pencereden kuruluyor, haftalık pencerede kullanılıyor

**Kanıt.**
- `Sources/LimitCore/UsageProfile.swift:69` — `let delta = Double(current.fiveHour - previous.fiveHour)`. Profil SADECE `fiveHour` deltalarından. `WindowKind` parametresi yok.
- `App/UsageStore.swift:397` — tek bir `profile` kuruluyor.
- `App/UsageStore.swift:411` — haftalık pencerenin projeksiyonuna aynı `profile` veriliyor.
- `Sources/LimitCore/Projection.swift:63-66` — `historic = expectedRemaining(...)`, `projected = current + historic`. `kind` hiç sorulmuyor.
- `Sources/LimitCore/Projection.swift:110` — `total += profile.hourly[hour] * fraction`.
- `Sources/LimitCore/Projection.swift:120-147` — `historicFillTime` aynı ölçekle 100'e sayıyor.

**Neden yanlış.** 5 saatlik pencerenin %1'i ile 7 günlük pencerenin %1'i farklı
büyüklükte kotadır. Birini diğerine eklemek, santimetreyi kilograma eklemek.

**Sayısal karşı-örnek** (`hourly[10..17] = 12`, `now = 15:00`):

```
5 saatlik pencere,  2 saat kaldı  -> beklenen ek tüketim =  24,0 puan   (makul)
7 günlük pencere,   4 gün kaldı   -> beklenen ek tüketim = 384,0 puan   (saçma)
```

384 puan haftalık yüzdeye ekleniyor, `projectedUtilization` daima >100 çıkıyor,
`historicFillTime` birkaç aktif saat içinde 100'e varıyor, `willOverrun` true
oluyor ve `Presentation.swift:309` "Tahmini Aşım" rozetini basıyor. Yani
haftalık karttaki aşım uyarısı, profil güvenilir olur olmaz kalıcı bir yanlış
alarma dönüşüyor.

**Öneri.** İki seçenekten biri:
1. `UsageProfile`'ı `WindowKind` başına kurmak (`build(from:kind:)`), 5 saatlik
   ve haftalık için iki ayrı profil tutmak. Doğru olan bu. Haftalık deltaların
   çözünürlüğü kaba, ama profil 60 günlük arşivden kuruluyor, yeterli kütle var.
2. Kısa yol: `Projector.project` içinde `guard kind == .fiveHour` koyup haftalık
   pencerede doğrusal uzatmaya (`rate * hoursLeft`) düşmek. Yanlış cevap
   vermektense zayıf cevap vermek.

`UsageProfile`'ın doc yorumu (`:50-55`) haftalık deltayı bilinçli olarak
dışladığını söylüyor; hata, o kararın ardından profilin haftalık pencereye de
uygulanmasında.

---

#### A2. [KRİTİK] Payda "gözlenen gün" değil "tüketim olan gün": koşullu ortalama, seçim yanlılığı

**Kanıt.** `UsageProfile.swift:71` `guard delta > 0 else { continue }` →
`:84` `hourDays[hour].insert(day)` yalnızca bu guard'dan geçen aralıklarda
çalışıyor → `:91-94` `hourlyTotal[hour] / Double(days)`.

**Neden yanlış.** Elde edilen büyüklük "saat h'de günlük ortalama tüketim"
değil, "saat h'de tüketim yaptığın günlerdeki ortalama tüketimin", yani
E[X | X > 0]. Bu iki şeyi birden bozuyor:

- **Kadran (`HourDial`, `Gauges.swift:204`)**: nadir kullanılan saatler,
  sürekli kullanılan saatlerin önüne geçiyor. Yukarıdaki karşı-örnekte
  peakHour = 3, gerçek yoğun saat 14.
- **Tahmin (`Projection.swift:110`)**: `expectedRemaining` her kalan saati
  "bu saatte kesin aktif olacaksın" varsayımıyla topluyor. Kullanıcı saat
  03:00'te 20 günde 1 kez çalışıyorsa bile o saate tam ağırlık veriliyor.
  Sistematik yukarı yönlü sapma, "Tahmini Aşım" erken tetikleniyor.

**Öneri.** Payda "o saatin ÖRNEKLE KAPSANDIĞI gün sayısı" olmalı, tüketim olsun
olmasın. Yani ikinci bir sayaç: aralık geçerliyse (`gap <= 3600`) delta 0 bile
olsa `coverageDays[hour].insert(day)`. Sonra:

```
hourly[h] = hourlyTotal[h] / max(1, coverageDays[h].count)
```

Bu hem gerçek "günlük ortalama"yı verir hem A3'teki kısmi gün korkusunu
yaratmaz (payda 24 değil, o saate özel kapsam sayısı).

Ayrıca `hourSampleDays` alanı ZATEN VAR ama hiçbir yerde kullanılmıyor
(grep: `UsageProfile.swift` dışında tek tüketici yok). Saat başına gözlem
sayısı elde varken `Projection` her saati eşit güvenle kullanıyor. Öneri:
küçültme (shrinkage) uygula, n_h düşük saatler genel ortalamaya çekilsin:

```
hourly_kullanılan[h] = (n_h / (n_h + k)) * hourly[h] + (k / (n_h + k)) * genelSaatlikOrtalama
```

k ≈ 3 makul bir başlangıç. Bu klasik empirik Bayes küçültmesi ve tam olarak
"tek bir yoğun gece bütün profili o saate kaydırıyor" probleminin standart
çözümü. `UsageProfile.swift:38-41`'deki yorum sorunu doğru teşhis etmiş ama
çözüm olarak global bir eşik koymuş; sorun saat bazlı, çözüm de saat bazlı olmalı.

---

#### A3. [ÖNEMLİ] Boşluk filtresi missing-not-at-random kütle kaybı yaratıyor

**Kanıt.** `UsageProfile.swift:75-76`:
```swift
let gap = current.date.timeIntervalSince(previous.date)
guard gap > 0, gap <= 3600 else { continue }
```
Aynı mantık `Projection.swift:193`'te de var.

**Neden yanlış (ve neden kısmen doğru).** Filtrenin gerekçesi doğru: 6 saatlik
bir boşluğa düşen 40 puanlık artışı tek bir saate yazmak profili bozar. Ama
uygulanan çözüm veriyi ATMAK, ve atılan veri rastgele değil:

- Boşluklar Claude Desktop / uygulamanın kapalı olduğu anlarda oluşuyor.
- Kullanıcı tarayıcıdan veya telefondan çalıştığında kota yine tükeniyor ama
  bu tüketim profile hiç girmiyor.
- Sonuç: profil "Claude Desktop açıkken çalıştığım saatler" profili, ama
  arayüzde "En Aktif Saatler" diye sunuluyor. Bu bir MNAR (missing not at
  random) durumu, klasik anlamda düzeltilemez ama gizlenmemeli.

**Öneri.**
1. Boşluğu atmak yerine deltayı boşluğun kapsadığı saatlere ORANTILI dağıt
   (aşağıda A4). En azından 1-3 saatlik boşluklar için. 3 saatten uzun boşluk
   hâlâ atılabilir.
2. Kapsam oranını kullanıcıya söyle: "son 14 günün %62'si gözlendi". Şu an
   `observedDays` var ama kapsam yok, kullanıcı profilin ne kadarının kör
   olduğunu bilmiyor.

---

#### A4. [ÖNEMLİ] Delta tamamen bitiş örneğinin saatine yazılıyor

**Kanıt.** `UsageProfile.swift:78-82` — `hour` ve `day`, `current.date`'ten
alınıyor; delta ise `[previous, current]` aralığında oluşmuş.

**Neden yanlış.** Filtre 1 saate kadar boşluğa izin verdiği için, 23:20 →
00:10 arası oluşmuş bir artışın TAMAMI saat 00'a ve ERTESİ GÜNE yazılıyor.
5 dakikalık normal örneklemede sapma küçük (en fazla 5 dk), ama boşluk
sonrası ilk örnekte 59 dakikaya kadar yanlış saate yazılabiliyor. Gün sınırı
geçildiğinde `allDays` ve `hourDays` sayımı da kayıyor.

**Öneri.** Aralığı saat sınırlarında böl, deltayı süreyle orantılı dağıt.
`Projector.nextHourBoundary` (`Projection.swift:159`) zaten bu işi doğru yapan
yardımcıyı içeriyor, aynı desen `build` içinde tekrar kullanılabilir.

---

#### A5. [ÖNEMLİ] Pencere sıfırlanmasındaki tüketim tamamen kayboluyor

**Kanıt.** `UsageProfile.swift:69-71`. 5 saatlik pencere sıfırlandığında
delta negatif oluyor (78 → 3), `guard delta > 0` bu aralığı komple atıyor.

**Neden yanlış.** O aralıkta gerçek tüketim VAR: sıfırlanma öncesi kalan
kullanım artı sıfırlanma sonrası 3 puan. Hepsi siliniyor. 5 saatlik pencere
günde ~4-5 kez sıfırlandığı için bu, günde 4-5 aralığın kaybı. Kütle kaybı
küçük (aralık başına ~5 dk) ama sistematik ve HER ZAMAN aşağı yönlü. Ayrıca
sıfırlanma anları kullanıcının yoğun çalıştığı saatlere denk gelme
eğiliminde (pencere ancak kullanım başlayınca başlıyor), yani kayıp da
yoğun saatlerde yoğunlaşıyor.

**Öneri.** `delta < 0` durumunda deltayı atmak yerine alt sınırı kullan:
sıfırlanma sonrası değer (`current.fiveHour`) o aralıkta kesinlikle harcanmış
miktarın alt sınırıdır.

```swift
let raw = current.fiveHour - previous.fiveHour
let delta = raw > 0 ? Double(raw) : (raw < 0 ? Double(current.fiveHour) : 0)
guard delta > 0 else { continue }
```

Bu tam doğru değil (sıfırlanma öncesi son dilimi hâlâ kaçırıyor) ama
"hepsini at"tan belirgin şekilde daha az yanlı.

---

#### A6. [ÖNEMLİ] `WindowDeriver` sıfırlanma tespiti çok gevşek, bulut birleşimi hayalet sıfırlanma üretebilir

**Kanıt.**
- `WindowDeriver.swift:79` — `for i in 1..<max(samples.count, 1) where values[i] < values[i - 1]` — HERHANGİ bir düşüş sıfırlanma sayılıyor.
- `UsageStore.swift:518-532` `archived(merging:)` — arşivden okunuyor.
- `UsageStore.swift:214-228` `restoreFromCloud()` — BAŞKA CİHAZLARIN örnekleri aynı arşive karışıyor.
- `UsageStore.swift:581-596` `recordServerReading` — sunucudan gelen `Double` yüzde `Int(rounded())` ile yuvarlanıp aynı seriye yazılıyor.

**Neden yanlış.** Artık tek bir kaynak yok: Claude Desktop dosyası, sunucu
okuması ve N cihazın buluttan gelen örnekleri tek zaman serisinde iç içe.
Bunlar aynı sunucu değerini okusa bile önbellek gecikmesi, farklı yuvarlama
(`recordServerReading` `rounded()`, dosya ham int) ve saat farkı yüzünden
seri MONOTON OLMAYABİLİR: `41, 40, 42` gibi bir dizi tek puanlık bir düşüşle
"sıfırlanma" ilan ettiriyor. Sonucu zincirleme:

`windowStart` yanlış yere kayıyor → `Projection.swift:52-53`'te
`since: max(windowStart, lookback)` çok dar bir aralığa iniyor →
`currentRate` iki örnek üzerinden hesaplanıyor → B2'deki patlama.

Bu bulgu SPEKÜLASYON değil mekanizma olarak kanıtlı, ama gerçek veride ne
sıklıkla olduğu ölçülmedi. Ölçmek kolay: arşivde `five_hour` düşüşlerinin
büyüklük dağılımına bakmak yeterli (1-2 puanlık düşüşler varsa hayalet).

**Öneri.** Sıfırlanmayı anlamlı düşüşle tanımla:

```swift
where values[i] < values[i-1] - 5 || (values[i] <= 2 && values[i-1] >= 10)
```

Ek olarak, arşivde kaynak ayrımı yok (`org` alanı `"server"` yazıyor ama
cihaz kimliği yok). Aynı `t` anahtarına farklı cihazların yazması yerine,
en azından ayrı kaynakları ayırt edip tek kaynağı kanonik seçmek daha
sağlam olurdu.

---

#### A7. [KÜÇÜK] DST: 25 saatlik günde saat 02 iki kez, payda bir kez

**Kanıt.** `UsageProfile.swift:78-80`, `Calendar.current` ile `.hour` ve
`[.year,.month,.day]`.

**Neden yanlış.** Sonbahar DST geçişinde yerel saat 02 aynı takvim gününde iki
kez yaşanıyor. `hourlyTotal[2]` iki saatlik tüketimi topluyor, `hourDays[2]`
ise günü bir kez sayıyor → o saatin ortalaması yılda bir kez ~2 katına
çıkıyor. İlkbaharda saat 03 hiç oluşmuyor, bu zararsız (payda da düşüyor).

Etki yılda bir gün, 60 günlük pencerede ~%1,7 ağırlık. Düzeltmeye değmez ama
bilinçli bir karar olarak yazılı olsun.

**Öneri.** Yok. Kayda geçsin yeter. (Düzeltilecekse payda `hourDays` yerine
"o saatin kaç kez yaşandığı" sayacı olmalı, bu zaten A2'nin kapsam sayacıyla
aynı çözüm.)

---

#### A8. [KÜÇÜK] `isReliable >= 3 gün` eşiği savunulabilir değil

**Kanıt.** `UsageProfile.swift:41` `observedDays >= 3`; `observedDays`
`:86`'da, HERHANGİ bir saatte tek bir pozitif delta olan her günü sayıyor.

**Neden zayıf.**
1. Eşik gün sayısına bakıyor, gözlem yoğunluğuna bakmıyor. Üç günde üçer
   tik atmış bir kullanıcı "güvenilir" oluyor ve 24 saatlik bir dağılım
   iddia ediliyor.
2. Eşik GLOBAL, kullanım SAAT BAZLI (`Projection.swift:110,137`). Profil
   güvenilir ilan edildiği anda, tek gün gözlenmiş bir saat de tam ağırlıkla
   tahmine giriyor. `hourSampleDays` bu bilgiyi taşıyor ama kimse okumuyor.
3. 3 gün haftanın günü desenini hiç kapsamıyor. `weekday` dizisi zaten
   hesaplanıyor ama hiçbir yerde kullanılmıyor (bkz. A9), yani hafta içi /
   hafta sonu farkı tahmine hiç girmiyor.

**Öneri.** İki kapılı eşik:
- Global: `observedDays >= 5` VE toplam pozitif aralık sayısı >= ~50.
- Yerel: A2'deki küçültmeyle birlikte, `hourSampleDays[h] < 2` olan saatler
  genel ortalamaya çekilsin.

Eşik değerleri keyfi; ama şu anki tek kapılı `>= 3` gerekçesiz olduğu için
en azından gerekçesi yazılabilir bir kurala geçmek gerekiyor.

---

#### A9. [KÜÇÜK] `weekday` ve `hourSampleDays` ölü hesap

**Kanıt.** grep sonucu: `weekday` alanı `UsageProfile.swift` dışında hiçbir
yerde okunmuyor; `hourSampleDays` yalnızca testlerde kuruluyor, üretimde
tüketilmiyor. Ayrıca `weekday` dizisi 8 uzunluğunda ve index 0 hiç
kullanılmıyor (`Calendar` weekday 1-7).

**Öneri.** Ya kullan (A8'deki küçültme `hourSampleDays`'i kullanır; haftalık
tahmin `weekday`'i kullanabilir) ya sil. Şu an hem hesap maliyeti hem de
"bu bilgi zaten var" yanılsaması var.

---

### B. "pace" (multiplier)

---

#### B1. [KRİTİK] Pay ve payda aynı şeyin ölçüsü değil: koşulsuz hız / koşullu hız

**Kanıt.**
- Pay: `Projection.swift:168-176` `currentRate`. Son 30 dakikanın (5 saatlik
  pencere için `max(30*60, 5h/10)` = 30 dk, `:38-40`) ilk ve son örneği
  arasındaki delta / geçen süre. **Duraklamalar paydada var.**
- Payda: `Projection.swift:181-199` `baselineRate`. `guard delta > 0 else
  { continue }` (`:190`) sonra `activeHours += hours` (`:195`).
  **Duraklamalar paydadan atılmış.**
- Oran: `Projection.swift:83` `rate / base`.

**Neden yanlış.** `currentRate` = E[hız], `baselineRate` = E[hız | hız > 0].
İkincisi birincisinden her zaman büyük. Oran, kullanıcı tam olarak alışkanlığı
kadar çalışırken bile 1'in altında çıkıyor. Oranın sabit çarpanı yaklaşık
"doluluk oranı" (duty cycle).

**Sayısal karşı-örnek.** 14 gün boyunca her gün 10:00-12:00 arası tam olarak
6 puan/saat harcayan kullanıcı, 5 dakikalık örneklemede (tam sayı yüzde
nedeniyle aralıkların yarısı +1, yarısı 0):

```
baselineRate    = 11,08 %/saat     (gerçek fiziksel hız 6,00 %/saat)
currentRate     =  6,00 %/saat
görünen pace    =  0,54 x
```

Kullanıcı 14 gündür yaptığının BİREBİR AYNISINI yapıyor, arayüz "yarı hızdasın"
diyor. `baselineRate`'in doc yorumu (`:178-180`) bu filtreyi bilinçli koymuş
("boş saatleri de sayan bir ortalama, her aktif anı yapay olarak yüksek
gösterirdi") ama düzeltmeyi yalnızca paydaya uygulamış, paya uygulamamış.

**Öneri.** İkisini de aynı koşullamaya getir. En temizi paydayı da yeniden
tanımlamak yerine, karşılaştırmayı doğru referansa taşımak:

```
pace = currentRate / profile.hourly[şu anki saat]
```

Yani "şu anki hızın, senin BU SAATTEKİ alışkanlığına oranı". Bu hem doğru
koşullama (aynı saat dilimi) hem de zaten hesaplanan bir büyüklük. A2'deki
kapsam-tabanlı payda düzeltmesiyle birlikte pay ile payda gerçekten aynı
şeyin ölçüsü olur.

Ara çözüm: `baselineRate`'i "toplam delta / toplam KAPSANAN süre" yap
(delta=0 aralıklar da paydaya girsin, yalnızca >1 saatlik boşluklar dışlansın).
Tek satırlık değişiklik: `:190`'daki `continue` yerine `delta = max(0, delta)`
ve `activeHours += hours` guard dışına.

---

#### B2. [KRİTİK] `baselineRate` örnekleme sıklığının fonksiyonu

**Kanıt.** `Projection.swift:188-198` + `QuotaSample.swift:11` (yüzde `Int`).

**Neden yanlış.** Tam sayı yüzde kuantalaması yüzünden, gerçek hız
"1 puan / örnek_aralığı"ndan yavaşsa aralıkların çoğu 0 delta oluyor.
Sıfırlar paydadan atıldığı için payda "1 puanlık tikin gerçekleştiği
aralıkların toplam süresi"ne düşüyor, pay ise toplam tik sayısı. Sonuç:

```
baselineRate ≈ 1 puan / örnek_aralığı_saat
```

Kullanıcının gerçek hızından bağımsız. Ölçüm (aynı gerçek hız 6 %/saat):

```
örnek aralığı  1 dk -> baselineRate = 60,00 %/saat   (10x şişme)
örnek aralığı  5 dk -> baselineRate = 12,00 %/saat   ( 2x şişme)
örnek aralığı 10 dk -> baselineRate =  5,76 %/saat   (~doğru, tesadüfen)
```

**Pratikteki sonucu:** bulut senkronu ikinci bir cihazın örneklerini aynı
arşive karıştırdığı anda (`UsageStore.swift:214-228`) efektif örnekleme
aralığı yarıya iniyor, `baselineRate` iki katına çıkıyor, kullanıcının
pace'i hiçbir davranış değişikliği olmadan yarıya düşüyor. Bu, cloud
özelliğinin doğrudan istatistiği bozduğu nokta.

Not: saatlik profil bu hatadan MUAF, çünkü orada payda sabit bir takvim saati
ve pay bir TOPLAM; toplam, örnekleme sıklığından bağımsız. Fark tam olarak
`baselineRate`'in paydasının veriye bağımlı olmasından geliyor.

**Öneri.** B1'deki düzeltme bunu da çözüyor: payda kapsanan süre olduğunda
örnekleme sıklığından bağımsız hale geliyor. Ek olarak `baselineRate` hiçbir
zaman "tek örnek aralığından" türetilmemeli; en az ~1 saatlik toplulaştırma
üzerinden hesaplanmalı (saatlik kovalar kurup kova ortalaması almak, tikleri
tek tek saymaktan çok daha kararlı).

---

#### B3. [KRİTİK] `currentRate`'te asgari ölçüm süresi yok, pace patlıyor

**Kanıt.** `Projection.swift:168-176`:
```swift
guard let first = window.first, let last = window.last, first.date < last.date else { return 0 }
...
let hours = last.date.timeIntervalSince(first.date) / 3600
```
Tek şart `first.date < last.date`, yani 1 saniye bile yeterli.

**Neden yanlış.** Pencerede kaç örnek olduğu garanti değil. Uygulama yeni
açıldıysa, `windowStart` yeni oluştuysa (`:52-53` `max(windowStart, lookback)`),
ya da A6'daki hayalet sıfırlanma tetiklendiyse, pencerede 2 örnek kalıyor.

```
28 dakikada 1 puanlık tik  -> rate =  2,14 %/saat
1 dakika arayla 2 örnek, 1 puanlık tik -> rate = 60,00 %/saat
```

Aynı davranış, 28 kat farklı hız. `baselineRate` ~12 ise pace 0,18x ile 5,0x
arasında salınıyor. Arayüz bunu "1,3×" gibi iki anlamlı haneli bir sayı olarak
sunuyor (`Presentation.swift:214-216`), sahip olmadığı bir kesinlik iddia
ediyor.

**Öneri.**
1. Asgari süre şartı: `guard hours >= rateWindow(for: kind) * 0.5`. Kısa
   veriyle pace GÖSTERİLMESİN (nil dön), tahmin edilmesin.
2. Paydada `last - first` yerine ölçüm penceresinin tamamını kullan
   (`min(now, resetAt) - since`). Şu anki hali "hızın olduğu aralığa"
   daraltıyor, B1'deki koşullama hatasının aynısı payda da var.
3. Kuantalama gerçeğini kabul et: 5 saatlik pencerede 30 dakikalık ölçüm,
   1 puanlık kuantayla en az 2 %/saat çözünürlük demek. Pace'i tam sayı
   hassasiyetinde göstermek (`1,3×`) yerine ya bant göster ("normalin
   üstünde") ya da ölçüm penceresini uzat (60-90 dk).

---

#### B4. [ÖNEMLİ] `activeHours > 0.5` eşiği bölmeyi korumaya yetmiyor

**Kanıt.** `Projection.swift:197` `guard activeHours > 0.5 else { return nil }`,
`:83` `base.map { $0 > 0 ? rate / $0 : nil }`.

**Neden yetersiz.** Bölme sıfıra karşı korunuyor ama KÜÇÜKLÜĞE karşı
korunmuyor. 14 günde toplam 0,6 aktif saat (yaklaşık 7 adet 5 dakikalık
aralık) bir tabanı meşru kılıyor. Bu 7 aralık:
- hepsi 1 puanlıksa base ≈ 11,7 %/saat,
- biri 10 puanlıksa base ≈ 27 %/saat,
- toplamda 1 puan varsa base ≈ 1,7 %/saat ve normal bir 10 %/saat hız
  **6,0×** olarak gösteriliyor.

Yani yeni kullanıcıda pace, ilk günlerde tamamen gürültü ve büyük ihtimalle
şişkin. `recent.count > 2` (`:184`) de aynı şekilde çok gevşek.

**Öneri.** Örneklem büyüklüğü eşiği koy: `activeHours >= 5` VE pozitif aralık
sayısı >= 30. Altında `multiplier = nil`. Ayrıca gösterimde makul bir tavan
(örn. 0,2x - 5,0x kırpma) ve tavan/tabana değince "yeterli veri yok" diline
düşme mantıklı olur.

---

#### B5. [KÜÇÜK] Pay yalnızca rate>0 iken gösteriliyor, dağılım tek yandan kırpılıyor

**Kanıt.** `Presentation.swift:335-338` — `guard let multiplier = p.multiplier,
p.ratePerHour > 0`.

**Neden önemli.** Bu davranış tek başına doğru (0×'i göstermek anlamsız) ama
B1 ile birleşince gösterilen pace dağılımının alt ucu kesiliyor. Kullanıcı
pace'i sadece aktifken görüyor, yani "0,54×" gibi sistematik olarak düşük
değerler görünür kalıyor, "0×" gizleniyor. Yanlılık düzeltilmiş gibi
görünmüyor, sadece daha az fark ediliyor.

**Öneri.** B1 düzeltilince bu satır olduğu gibi kalabilir.

---

### C. Pace bulutta tutulmalı mı

---

#### Şu an ne gidiyor

`cloud/schema.sql` `sample` tablosu: `device_id, t, five_hour, seven_day,
extra, account_key`. `cloud/src/index.ts:186-189` bu altı alanı yazıyor,
`:266-275` aynı alanları geri veriyor. **Pace veya profil buluta GİTMİYOR.**
Doğru olan bu.

#### Kesin tavsiye: SAKLAMA

Gerekçeler, güçlüden zayıfa:

**1. Pace ve profil türetilmiş büyüklükler, gizli durumları yok.**
`UsageProfile.build(from:)` (`UsageProfile.swift:56`) ve
`Projector.baselineRate/currentRate` (`Projection.swift:168,181`) saf
fonksiyonlar: girdileri yalnızca `[QuotaSample]` ve `Calendar`. Ham örnekler
zaten hesap bazlı senkronlanıyor (`index.ts:266-268`, `account_key` ile),
dolayısıyla yeni cihaz `restoreFromCloud()` (`UsageStore.swift:214`) ile
arşivi doldurduğu anda profil ve pace BİREBİR yeniden üretiliyor.
Ayrıca saklamak denormalizasyon olur: aynı bilginin ikinci kopyası,
tutarsızlaşma riskiyle.

**2. Türetilmiş değerin raf ömrü çok kısa.** `currentRate` 30 dakikalık bir
ölçüm; buluta yazıldığı an bayatlıyor. `syncCloud` 15 dakikada bir çalışıyor
(`UsageStore.swift:682`), yani buluttaki pace her zaman gerçeğin gerisinde.
Bayat türetilmiş değeri saklamak, taze ham veriden hesaplamaya göre kesin
kayıp.

**3. Profil YEREL SAAT DİLİMİNE bağlı, pace değil.** `UsageProfile.build`
`Calendar.current` kullanıyor (`:78-80`). Aynı ham veri, İstanbul'daki
cihazda ve Berlin'deki cihazda FARKLI profil üretir, ve bu doğru davranış:
"benim aktif saatlerim" sorusunun cevabı bulunduğun saat dilimine göre
değişir. Profili buluta yazmak bu doğru davranışı bozar, çünkü hangi cihazın
saat dilimiyle hesaplandığı kaybolur. Ham veri saklamak saat diliminden
bağımsız, bu yüzden daha sağlam.

**4. Mahremiyet bütçesi.** Ham örnek zaten "şu anda yüzde kaç"; pace ve
saatlik profil ise daha yorumlanmış, daha kişisel davranış verisi ("bu
kullanıcı sabah 3'te çalışıyor"). Sunucuda tutulan bilgi miktarını
artırmanın karşılığında hiçbir bilgi kazancı yok. Kötü takas.

**5. Şema borcu.** `pace` sütunu eklemek, migration, geriye dönük doldurma,
ve algoritma değiştiğinde (ki bu incelemenin çıktısı tam olarak algoritmayı
değiştirmek) buluttaki eski değerlerin yanlış olması demek. Ham veri
sakladığın sürece algoritmayı istediğin gün değiştirip TÜM GEÇMİŞİ yeniden
hesaplayabilirsin. Bu, ham-veri-sakla ilkesinin en somut faydası ve
bu proje için özellikle geçerli: yukarıdaki A ve B bulguları uygulandığında
geçmiş pace değerleri toptan geçersiz olur.

#### Ama bir şey EKSİK: saat dilimi

Ham örnek `t` (epoch ms) ve yüzdeden ibaret. Kullanıcı seyahat ederse veya
cihazlar farklı saat dilimindeyse, geçmiş örneklerin hangi YEREL saatte
alındığı geri getirilemiyor. Bugün profil "şu anki saat dilimine göre" yeniden
yorumlanıyor, bu kabul edilebilir bir tercih ama bilinçli olmalı.

Saklanacak bir şey aranıyorsa, saklanması gereken PACE DEĞİL, örnek başına
UTC ofseti (`tz_offset INTEGER`). Bu ham veri, türetilmiş değil, ve
kaybolduğunda geri getirilemeyen tek bilgi o.

#### İkinci uyarı: bulut birleşimi mevcut istatistiği bozuyor

B2'de gösterildi: iki cihazın örneklerini tek seride birleştirmek örnekleme
aralığını değiştirdiği için `baselineRate`'i, dolayısıyla pace'i doğrudan
kaydırıyor. A6'da gösterildi: kaynaklar arası yuvarlama/gecikme farkı hayalet
sıfırlanma üretebiliyor. Yani "pace'i saklamalı mıyız" sorusunun cevabı hayır
ama "bulut senkronu pace'i etkiler mi" sorusunun cevabı EVET, olumsuz yönde.
Bulut açılmadan önce B1/B2 ve A6 düzeltilmeli.

---

## 3. Yanlış alarm olmadığını doğruladığım şeyler

Bunlara dokunma, doğru çalışıyorlar:

**1. Kısmi gün 24'e bölünmüyor.** Endişe yersiz: `UsageProfile.swift:91-94`
paydası 24 değil, o saate özel gözlem günü sayısı. Bugünün 3 saati 24 saatlik
bir ortalamayı sulandırmıyor. (Not: bu tasarım A2'deki koşullu-ortalama
hatasının da kaynağı; A2'deki düzeltme bu iyi özelliği KORUYARAK yapılmalı,
payda 24'e çevrilmemeli.)

**2. Saatlik toplam örnekleme sıklığından bağımsız.** `hourlyTotal[hour] +=
delta` bir TOPLAM; 1 dakikalık da örneklesen 10 dakikalık da örneklesen aynı
toplama yakınsıyor. `baselineRate`'in aksine burada kuantalama sistematik
sapma yaratmıyor. Sayısal olarak da doğrulandı.

**3. Saat dilimi dönüşümü tutarlı.** Profil kurulurken (`UsageProfile.swift:
78-80`) ve tüketilirken (`Projection.swift:107,134`) aynı `Calendar` örneği
zincirden geçiyor (`UsageStore` varsayılanı `.current`). UTC-yerel karışması
YOK. Testlerde de aynı takvim enjekte edilebiliyor.

**4. `nextHourBoundary` doğru.** `Projection.swift:159-165`. `nextDate(after:
matching: minute:0 second:0, matchingPolicy: .nextTime)` kesinlikle ileri
gidiyor, tam saatte sonsuz döngü yok, ve doc'ta anlatılan eski hata (`bySetting`
+ 1 saat) gerçekten düzeltilmiş. Bir saatlik ağırlığın komşuya yazılması
sorunu yok.

**5. Kesirli saat ele alışı doğru.** `expectedRemaining` (`:96-114`) ve
`historicFillTime` (`:120-147`) saat sınırlarında bölüp `fraction` ile
ağırlıklandırıyor. Birimler tutarlı (%/saat × saat = %). `historicFillTime`
içindeki interpolasyon (`:141` `needed * fraction * 3600`) de doğru:
`needed` `gain`in kesri, `gain` `fraction` saat sürüyor, çarpım doğru zamanı
veriyor. Boyut hatası yok. (Hata, A1'de anlatıldığı gibi, bu doğru
matematiğe YANLIŞ ÖLÇEKTE profil beslenmesi.)

**6. Boş profilde peakHour gösterilmiyor.** `UsageProfile.swift:22-25` ve
`Gauges.swift:180-183` aynı guard'ı taşıyor (`maximum > 0`). `firstIndex(of: 0)`
tuzağı iki yerde de kapatılmış, tutarlılar. `PopoverRootView.swift:364`
ayrıca `observedDays > 0` şartıyla kadranı gizliyor.

**7. Sıfırlanmalar saatlik profile NEGATİF olarak sızmıyor.** `delta > 0`
guard'ı işaret olarak doğru: eksi delta hiçbir zaman tüketimden düşülmüyor.
Kusur (A5) eksik sayım, yanlış işaret değil.

**8. Pace, hız sıfırken gizleniyor.** `Presentation.swift:336`
`p.ratePerHour > 0` şartı doğru: "0,0×" göstermek yanlış bilgi olurdu.

**9. Bulut yalnızca ham veri tutuyor.** `schema.sql` ve `index.ts:186`
doğrulandı. Türetilmiş hiçbir büyüklük sunucuya gitmiyor. Tasarım kararı
doğru, C bölümündeki tavsiye bunu değiştirmemek yönünde.

**10. Arşiv/dosya kıyası aynı aralıkta yapılıyor.** `UsageStore.swift:530`
`freshInWindow` filtresi; 9 günlük arşiv dilimini 29 günlük dosyanın tamamıyla
karşılaştırma hatası düzeltilmiş. Doğru.

---

## 4. Önerilen düzeltme sırası

Etki/maliyet oranına göre:

1. **A1** (haftalık birim hatası). Tek satırlık `guard` ile bile kapatılabilir,
   en görünür yanlış çıktıyı yok eder.
2. **B3** (asgari ölçüm süresi) + **B4** (örneklem eşiği). Küçük, savunmacı,
   pace'in uçmasını engeller.
3. **B1/B2** (pay-payda koşullamasını eşitle). Pace'i anlamlı hale getiren
   asıl düzeltme. Bulut çok cihazlı senkron açılmadan ÖNCE yapılmalı.
4. **A2** (kapsam tabanlı payda + `hourSampleDays` ile küçültme). Kadranı ve
   tahmini birlikte düzeltir.
5. **A6** (sıfırlanma eşiği). Bulut birleşimi yaygınlaşınca kritikleşir.
6. **A4/A5** (orantılı dağıtım, sıfırlanma alt sınırı). İnce düzeltmeler.
7. **A3** kapsam göstergesi, **A8** eşik gerekçesi, **A9** ölü kod.

---

## Ek: doğrulama betikleri

Karşı-örnekler `UsageProfile.build`, `baselineRate`, `currentRate` ve
`expectedRemaining` fonksiyonlarının Python portuyla üretildi. Betikler
oturum scratchpad'inde (`sim.py`, `sim2.py`); projeye eklenmedi. Aynı
senaryolar Swift tarafında `Tests/LimitCoreTests/` altına regresyon testi
olarak taşınabilir, özellikle:

- CE1: 20 gün 14:00 + 1 gün 03:00 → `peakHour == 14` beklentisi
- CE2: sabit hız, sabit desen → `pace ≈ 1.0` beklentisi
- CE3: aynı davranış farklı örnekleme aralığı → `baselineRate` sabit kalmalı
- CE4: 1 dakikalık aralıktan hız türetilmemeli → `multiplier == nil`

Bu dört test, yukarıdaki düzeltmelerin doğru yapıldığının kanıtı olur.
