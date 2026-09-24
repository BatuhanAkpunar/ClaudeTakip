-- Sunucu tarafı sırlar.
--
-- IP özetinin tuzu `IP_SALT` ortam sırrından geliyor; tanımlı değilse kodda
-- yazılı, depoda herkese açık sabit bir değere düşülüyordu. Tuz bilinince
-- IPv4 uzayının tamamı dakikalar içinde özetlenip registration_log'daki
-- değerler ham IP'ye geri çevrilebiliyor. Artık sır yoksa Worker ilk
-- ihtiyaçta rastgele bir tuz üretip buraya yazıyor; değer depoda değil
-- yalnızca bu veritabanında.
CREATE TABLE IF NOT EXISTS server_secret (
    name  TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
