-- Cihaz kaydı. Kullanıcıdan hiçbir kişisel bilgi alınmıyor.
CREATE TABLE IF NOT EXISTS device (
    id           TEXT PRIMARY KEY,
    -- Gizli anahtarın kendisi değil SHA-256 özeti saklanıyor.
    secret_hash  TEXT NOT NULL,
    created_at   INTEGER NOT NULL,
    last_seen_at INTEGER,
    plan         TEXT,
    -- Kayıt hız sınırı için. Ham IP saklanmıyor, yalnızca özeti: sınır
    -- uygulanabiliyor ama IP geri elde edilemiyor.
    ip_hash      TEXT
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

CREATE INDEX IF NOT EXISTS sample_device_time ON sample(device_id, t);

CREATE INDEX IF NOT EXISTS device_ip_hash ON device(ip_hash, created_at);

-- Kayıt hız sınırı günlüğü. Cihaz silinse de kayıt izi bir saat kalıyor,
-- yoksa kaydol-sil döngüsüyle sınır aşılabiliyordu.
CREATE TABLE IF NOT EXISTS registration_log (
    ip_hash    TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS registration_log_ip ON registration_log(ip_hash, created_at);
