-- 0002'den önceki ilk şema (c641122'deki schema.sql'den ip_hash ve
-- account_key çıkarılmış hâli). Depoda 0001 göçü yok; testler göç zincirini
-- bu tabandan başlatıyor. Bu dosya bir göç DEĞİL, yalnızca test fikstürü.
CREATE TABLE IF NOT EXISTS device (
    id           TEXT PRIMARY KEY,
    secret_hash  TEXT NOT NULL,
    created_at   INTEGER NOT NULL,
    last_seen_at INTEGER,
    plan         TEXT
);
CREATE TABLE IF NOT EXISTS sample (
    device_id  TEXT NOT NULL,
    t          INTEGER NOT NULL,
    five_hour  INTEGER NOT NULL,
    seven_day  INTEGER NOT NULL,
    extra      INTEGER,
    PRIMARY KEY (device_id, t)
);
CREATE INDEX IF NOT EXISTS sample_device_time ON sample(device_id, t);
