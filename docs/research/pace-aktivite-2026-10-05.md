# Pace ve aktivite denetimi — 0.2.8

## Haftalık tahmin

Eski formül `tüketim / geçen takvim süresi` idi. Geçmiş uyku ve limit
beklemelerini zaten içeriyordu; sorun, özellikle ilk birkaç saatten sonra,
geçmiş ortalamayı bütün geleceğe düz çizgiyle uzatmasıydı.

5 saatlik model aynı kaldı. Haftalıkta en az 24 saat geçmeden tahmin yok.
Son 60 günlük arşivde en az 7 gözlem günü ve 3 ayrı günde haftalık tüketim
varsa saatlik tüketim deseni kullanılır. Desen, 5 saatlik kota ya da aktiflik
skoru yerine **haftalık kota artışlarından** çıkarılır. Son günler 21 günlük
yarı ömürle ağır basar. Haftanın bir gününden en az 3 gözlem varsa o günün
deseni, yoksa bütün günlerin ortak saatlik deseni kullanılır.

Ölçek = bu haftaki tüketim / pencere başından şimdiye kadar desenin integrali.
Gelecek eğrisi, bu ölçekle saat saat biriktirilir. Gece/düşük kullanım saatleri
kendiliğinden yavaşlar. Şu an 5 saatlik limit doluysa bilinen sıfırlanma anına
kadar eğri sabittir. Pace = pencere sonunda tahmini kullanım / 100; dolma
anıyla aynı modelden gelir. Yeterli desen yoksa en az bir günlük takvim
ortalamasına dönülür; bilinen bekleme buna da uygulanır. Haftalık sıfırlanma
sonrasına dolma tarihi verilmez.

Bu bir davranış tahmini: sonraki oturumların başlayacağı zaman veya başka
cihazdaki gelecekteki kullanım bilinmez. Gelecekteki bütün 5 saatlik limitleri
kesin olarak simüle etmez; geçmiş beklemelerin etkisi öğrenilen dağılımdadır.
Kayıt olmayan saatler uyku olduğunun kanıtı değildir. Eksik kayıt, değişen
alışkanlık veya seyahat doğruluğu azaltabilir. Yüzdeler tam sayı olduğu için
çok küçük tüketimin kayda geçtiği saat gerçek iş saatinden kayabilir.

## Most Active Hours / Weekday × Hour / Hour by Hour

Üç görünüm aynı UsageProfile nesnesinden beslenir. Aktivite skoru, saatin
gözlendiği günlerde tüketim görülme sıklığıdır; yakınlık ağırlığı ve az veride
payda tabanı (saat için 3, hafta günü hücresi için 2) kullanılır. Bu nedenle
ham “günlerin yüzde kaçı” değildir; arayüz etiketi aktiflik olarak düzeltildi.
Tüketim sütunu, ölçülebilen aktif günlerdeki ortalama 5 saatlik kota puanıdır;
token, çalışma süresi veya haftalık kota yüzdesi değildir. Gözlem sütunu o
saate dokunan örnek çiftleri bulunan ayrı günlerin sayısıdır, tam saat sayısı
değildir. Isı haritaları kendi tepe değerlerine göre renklenir.

Pazartesi=0 hafta günü ve yerel saat hesapları doğru. Kayıtlı UTC farkı
kullanılır; eski kayıtlarda mevcut takvime dönülür. Artış örnek çiftinin orta
noktasına yazılır; bir saatten uzun boşluklar atlanır. Örnekler arasında saat
farkı değişiyorsa belirsiz aralık artık atlanır.

Düzeltmeler:
- Yalnız sunucuyla çalışan yolda profil artık yenilenir (Desktop gerekmez).
- 40→39→40 gibi geri gelen okumalar hayalet tüketim oluşturmaz; her kuruluş
  için pencerenin en yüksek değeri tutulur, gerçek sıfırlanmada yeniden başlar.
- Sıfırlanma aralığı yanlışlıkla hareketsiz gözlem sayılmaz. Aynı aralıkta
  haftalık artış varsa aktivite kanıtı olarak kullanılır; bilinmeyen 5 saatlik
  tüketim miktarı uydurulmaz.
- Elle yenileme profil önbelleğini ve taze sunucu yanıtı gelince tekrar sonucu
  yeniler. Hour by Hour altındaki açıklama kaldırıldı.

## Yenileme sıklığı

- Sunucu: başarılı bağlantıda 60 saniyede bir; ağ/oturum hatasında geri çekilme.
- Yerel kota dosyası: dosya değişince; ayrıca 30 saniyelik arayüz turu.
- Aktivite profili: 5 dakika önbellek; sonraki yenileme turunda yeniden hesap.
- Elle yenileme ve buluttan geri yükleme: önbelleği beklemeden.
- Geçmiş: 60 gün; arşiv saklama: 90 gün.

## Doğrulama

Regresyonlar: gece boyunca düz eğri, mevcut limit beklemesi (desenli ve
ortalama modelde), hafta sonu, ilk gün/yetersiz geçmiş, pace–aşım tutarlılığı,
geçmiş sıfırlanma, DST, yedi hafta günü/UTC farkı/gece yarısı, gecikmiş
okumalar ve reset sonrası aktivite. Paket testleri UTC ortamında çalıştırılır.
