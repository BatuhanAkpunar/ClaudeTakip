-- Cihaz başına hız sınırı sayacı.
--
-- Kayıt dışındaki uçlarda hiç sınır yoktu: geçerli bir cihaz kimliğiyle
-- sınırsız istek atmak, D1'in ücretsiz katmanındaki günlük okuma kotasını
-- tüketip servisi bütün kullanıcılara kapatabiliyordu. Sayaç cihaz satırının
-- içinde tutuluyor, ayrı bir tabloya gerek yok.
ALTER TABLE device ADD COLUMN rate_window_start INTEGER;
ALTER TABLE device ADD COLUMN rate_count INTEGER NOT NULL DEFAULT 0;
