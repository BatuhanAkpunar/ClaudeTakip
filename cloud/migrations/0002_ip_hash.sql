-- Kayıt hız sınırı için IP özeti sütunu. Mevcut cihazlarda NULL kalıyor;
-- sınır yalnızca yeni kayıtlar üzerinden sayıldığı için bu bir sorun değil.
ALTER TABLE device ADD COLUMN ip_hash TEXT;
CREATE INDEX IF NOT EXISTS device_ip_hash ON device(ip_hash, created_at);
