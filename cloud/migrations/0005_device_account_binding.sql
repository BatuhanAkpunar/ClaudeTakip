-- Cihaz → hesap bağı.
--
-- Hesap anahtarı şimdiye kadar yalnızca bir ADRES'ti: istemci `x-account-key`
-- başlığında ne gönderirse sunucu o kapsamda okuyor, yazıyor ve siliyordu.
-- Anahtar sır değil (istemciye gömülü pepper + organizasyon kimliği), yani
-- geçerli bir cihaz kaydı olan herkes başka bir hesabın verisini okuyabilir ya
-- da silebilirdi. Bu sütunlar anahtarı SAHİPLİĞE çeviriyor: cihaz bir hesaba
-- bağlanıyor ve sonraki isteklerde başlığın o bağla eşleşmesi şart.
--
-- Mevcut cihazlar NULL ile geliyor: ilk istekte bağlanıyorlar (ilk kullanımda
-- güven). Bu, çalışan kurulumları bozmadan korumayı devreye alıyor.
ALTER TABLE device ADD COLUMN account_key TEXT;

-- Hesap değişikliği meşru bir eylem (kullanıcı başka hesaba girebilir) ama
-- sınırsız olmamalı: sayaç, bir cihazın hesaptan hesaba gezinerek tarama
-- yapmasını görünür ve sınırlanabilir kılıyor.
ALTER TABLE device ADD COLUMN account_bound_at INTEGER;
ALTER TABLE device ADD COLUMN account_changes INTEGER NOT NULL DEFAULT 0;
