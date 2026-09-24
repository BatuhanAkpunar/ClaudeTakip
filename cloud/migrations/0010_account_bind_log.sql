-- Hesap bağlama günlüğü ve hesap başına cihaz sayımı.
--
-- Cihaz → hesap bağı ilk kullanımda kuruluyor (0005) ve hesap anahtarı bir
-- sır değil. Sahipliği kanıtlamak istemci değişikliği gerektiriyor; o gelene
-- kadar sunucu, bir hesaba yeni cihaz bağlanmasını SINIRLIYOR ve KAYDEDİYOR:
-- hesap başına günlük yeni bağ sayısı ve etkin cihaz sayısı bu tablodan ve
-- aşağıdaki dizinden sayılıyor. Günlük aynı zamanda denetim izi: hangi
-- cihaz, hangi IP bloğundan, verisi olan bir hesaba ne zaman bağlandı.
CREATE TABLE IF NOT EXISTS account_bind_log (
    account_key TEXT NOT NULL,
    device_id   TEXT NOT NULL,
    -- Tuzlu IP özeti (ham IP değil), registration_log ile aynı biçim.
    ip_hash     TEXT NOT NULL,
    created_at  INTEGER NOT NULL,
    -- Bağlanma anında hesabın bulutta verisi var mıydı (1) yok muydu (0).
    had_data    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS account_bind_log_account ON account_bind_log(account_key, created_at);
CREATE INDEX IF NOT EXISTS account_bind_log_device ON account_bind_log(device_id, created_at);

-- Hesaba bağlı etkin cihaz sayımı için.
CREATE INDEX IF NOT EXISTS device_account ON device(account_key, last_seen_at);
