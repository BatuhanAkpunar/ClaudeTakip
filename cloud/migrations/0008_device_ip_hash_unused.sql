-- `device.ip_hash` ve `device_ip_hash` dizini yalnızca yazılıyordu: kayıt
-- sınırı 0003'ten beri `registration_log`'dan sayılıyor, bu sütunu okuyan
-- hiçbir sorgu yok. Dizin her kayıtta boşuna yazılıyor, sütun ise her
-- cihazın IP özetini süresiz saklıyordu (günlük bir saatte budanıyor).
--
-- Worker artık sütunu yazmıyor. Sütunun KENDİSİ düşürülmüyor: göç Worker
-- dağıtımından önce uygulandığında eski Worker'ın `INSERT ... ip_hash`
-- sorgusu arada kırılırdı. Eski özetler siliniyor, sütun boş kalıyor.
DROP INDEX IF EXISTS device_ip_hash;
UPDATE device SET ip_hash = NULL WHERE ip_hash IS NOT NULL;
