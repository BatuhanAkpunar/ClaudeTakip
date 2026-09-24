-- SIFIR bir veritabanının tam şeması (`npm run schema:local`, `wrangler dev`).
-- Var olan veritabanları yalnızca migrations/ ile yükseltilir. İkisi aynı
-- veritabanına birlikte uygulanmaz: 0002 ve 0004'ün eklediği sütunlar bu
-- dosyada zaten var ve ALTER TABLE var olan sütunda hata verir.

-- Cihaz kaydı. Kullanıcıdan hiçbir kişisel bilgi alınmıyor.
CREATE TABLE IF NOT EXISTS device (
    id                TEXT PRIMARY KEY,
    -- Gizli anahtarın kendisi değil SHA-256 özeti saklanıyor.
    secret_hash       TEXT NOT NULL,
    created_at        INTEGER NOT NULL,
    last_seen_at      INTEGER,
    plan              TEXT,
    -- KULLANILMIYOR (0008): kayıt sınırı registration_log'dan sayılıyor.
    -- Worker yazmıyor; sütun yalnızca eski Worker ile uyum için duruyor.
    ip_hash           TEXT,
    -- Cihaz → hesap bağı. Hesap anahtarı sır değil (istemciye gömülü pepper +
    -- organizasyon kimliği), bu yüzden `x-account-key` başlığı tek başına yetki
    -- sayılmaz; yoksa geçerli bir cihaz kaydı olan herkes başka bir hesabın
    -- verisini okuyabilir ya da silebilir. Bu sütun anahtarı SAHİPLİĞE
    -- çeviriyor: cihaz bir hesaba bağlanıyor ve sonraki isteklerde başlığın o
    -- bağla eşleşmesi şart. NULL ise cihaz henüz bağlı değil ve gönderdiği ilk
    -- anahtara bağlanıyor (ilk kullanımda güven).
    account_key       TEXT,
    -- Hesap değişikliği meşru bir eylem (kullanıcı başka hesaba girebilir) ama
    -- sınırsız olmamalı: sayaç, bir cihazın hesaptan hesaba gezinerek tarama
    -- yapmasını görünür ve sınırlanabilir kılıyor.
    account_bound_at  INTEGER,
    account_changes   INTEGER NOT NULL DEFAULT 0,
    -- Cihaz başına hız sınırı sayacı. Kayıt dışındaki uçların sınırı bu:
    -- olmasa geçerli bir cihaz kimliğiyle sınırsız istek atmak, D1'in ücretsiz
    -- katmanındaki günlük okuma kotasını tüketip servisi bütün kullanıcılara
    -- kapatabilir. Sayaç cihaz satırının içinde tutuluyor, ayrı bir tabloya
    -- gerek yok.
    rate_window_start INTEGER,
    rate_count        INTEGER NOT NULL DEFAULT 0
);

-- Kota ölçümleri. Birincil anahtar (cihaz, zaman) olduğu için aynı örnek
-- iki kez yazılmıyor: istemci ağ hatasında güvenle yeniden gönderebiliyor.
CREATE TABLE IF NOT EXISTS sample (
    device_id  TEXT NOT NULL,
    t          INTEGER NOT NULL,
    five_hour  INTEGER NOT NULL,
    seven_day  INTEGER NOT NULL,
    extra      INTEGER,
    -- Verinin kanonik sahibi: organizasyon kimliğinin geri döndürülemez
    -- özeti. NULL ise giriş öncesi anonim veri, /v1/claim ile devredilir.
    account_key TEXT,
    PRIMARY KEY (device_id, t)
);

CREATE INDEX IF NOT EXISTS sample_account_time ON sample(account_key, t);

-- Kayıt hız sınırı günlüğü. Cihaz silinse de kayıt izi bir saat kalıyor,
-- yoksa kaydol-sil döngüsüyle sınır aşılabiliyordu.
CREATE TABLE IF NOT EXISTS registration_log (
    ip_hash    TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS registration_log_ip ON registration_log(ip_hash, created_at);

-- Sunucu tarafı sırlar (0009). `IP_SALT` tanımlı değilse IP özetinin tuzu
-- ilk ihtiyaçta rastgele üretilip burada saklanıyor.
CREATE TABLE IF NOT EXISTS server_secret (
    name  TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Hesaba bağlı etkin cihaz sayımı için (0010).
CREATE INDEX IF NOT EXISTS device_account ON device(account_key, last_seen_at);

-- Hesap bağlama günlüğü (0010). Bir hesaba yeni cihaz bağlanması hem
-- sınırlanıyor hem de burada iz bırakıyor. Bkz. auth.ts resolveScope.
CREATE TABLE IF NOT EXISTS account_bind_log (
    account_key TEXT NOT NULL,
    device_id   TEXT NOT NULL,
    ip_hash     TEXT NOT NULL,
    created_at  INTEGER NOT NULL,
    had_data    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS account_bind_log_account ON account_bind_log(account_key, created_at);
CREATE INDEX IF NOT EXISTS account_bind_log_device ON account_bind_log(device_id, created_at);
