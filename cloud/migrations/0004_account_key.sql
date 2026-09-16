-- Kullanım geçmişini cihaz bazlıdan hesap bazlına taşır.
-- Mevcut satırlar NULL kalır (anonim); istemci giriş yapınca /v1/claim ile
-- kendi anonim satırlarını hesabına devreder.
ALTER TABLE sample ADD COLUMN account_key TEXT;
CREATE INDEX IF NOT EXISTS sample_account_time ON sample(account_key, t);
