// ---------------------------------------------------------------------------
// Servis sınırları. Hepsi tek yerde; bir sayıyı değiştirmek tel sözleşmesini
// değiştirir, istemcideki eşini de gözden geçir.
// ---------------------------------------------------------------------------

/**
 * Ofis ya da operatör NAT'ı arkasında çok sayıda gerçek kullanıcı aynı IP'yi
 * paylaşıyor ve kayıt cihaz ömründe bir kez oluyor: sınır kötüye kullanımı
 * durduracak kadar düşük, meşru bir ekibi kapıda bırakmayacak kadar yüksek.
 */
export const REGISTRATIONS_PER_IP_PER_HOUR = 20;

/** Kayıt sınırının sayıldığı pencere: bir saat. */
export const REGISTRATION_WINDOW_MS = 60 * 60 * 1000;

/**
 * Cihaz başına kayan pencere sınırı: dakikada en fazla `DEVICE_REQUESTS_PER_MINUTE`.
 *
 * Sayaç `device` satırının kendisinde tutuluyor, ayrı bir depoya gerek yok:
 * cihaz satırı zaten her istekte güncelleniyor (`last_seen_at`).
 */
export const DEVICE_REQUESTS_PER_MINUTE = 30;

/** Cihaz hız sınırının penceresi: bir dakika. */
export const DEVICE_RATE_WINDOW_MS = 60_000;

/** Yükleme gövdesi için sert tavan. */
export const MAX_BODY_BYTES = 512 * 1024;

/**
 * Tek yüklemede kabul edilen en fazla örnek. İstemcinin eşi
 * `CloudSync.batchLimit` (500); bu tavanın altında kalmalı.
 */
export const MAX_SAMPLES_PER_UPLOAD = 1000;

/** Yüzdelerin kırpıldığı üst sınır (örnek sayısı tavanıyla ilgisi yok). */
export const PERCENT_CEILING = 1000;

/** `device.plan` için en fazla karakter. */
export const MAX_PLAN_LENGTH = 64;

/** 2100'den sonrası saçma bir zaman damgası. */
export const MAX_SAMPLE_TIME_MS = Date.UTC(2100, 0, 1);

/** İndirmede `limit` verilmezse kullanılan satır sayısı. */
export const DOWNLOAD_DEFAULT_LIMIT = 5000;

/**
 * İndirmede `limit` için tavan. İstemcinin eşi `CloudSync.downloadPageSize`
 * (10_000); bu tavanı aşmamalı.
 */
export const DOWNLOAD_MAX_LIMIT = 10000;

/**
 * Hesap anahtarının tek kabul edilen biçimi: 64 küçük onaltılık karakter.
 * İstemcinin eşi `AccountKey.isValid`.
 */
export const ACCOUNT_KEY_PATTERN = /^[0-9a-f]{64}$/;

/** `Authorization` başlığının öneki. */
export const BEARER_PREFIX = "Bearer ";

/**
 * Cihaz başına `ACCOUNT_CHANGE_WINDOW_MS` içinde en fazla bu kadar bağ (ilk bağ
 * + hesap değişiklikleri). Eskiden sayaç ömür boyuydu ve yeniden bağlama yolu
 * olmadığı için hiç erişilemiyordu; pencere, meşru bir hesap değiştiricinin
 * kalıcı kilitlenmesini önlüyor, hesaptan hesaba tarama yapan bir cihazı ise
 * yavaşlatıyor.
 */
export const ACCOUNT_CHANGE_LIMIT = 10;
export const ACCOUNT_CHANGE_WINDOW_MS = 30 * 86_400_000;

/**
 * Hesaba bağlı etkin cihaz tavanı (#48). Tek kişinin bir hesapta aynı anda
 * kullandığı Mac sayısı gerçekte birkaç; yeniden kurulumlarda eski cihaz
 * `ACTIVE_DEVICE_WINDOW_MS` içinde görülmezse sayımdan düşüyor.
 */
export const MAX_ACTIVE_DEVICES_PER_ACCOUNT = 8;
export const ACTIVE_DEVICE_WINDOW_MS = 30 * 86_400_000;

/**
 * Hesaba günlük yeni bağ tavanı (#48). Meşru kullanıcı günde en fazla bir iki
 * kez yeni cihaz bağlar (yeni Mac, "buluttaki veriyi sil" sonrası yeniden
 * kayıt); bir hesabın cihaz cihaz taranması ise günde birkaça iniyor.
 */
export const NEW_BINDS_PER_ACCOUNT_PER_DAY = 5;
export const NEW_BIND_WINDOW_MS = 86_400_000;

/** `account_bind_log` denetim izinin saklama süresi. */
export const BIND_LOG_RETENTION_MS = 90 * 86_400_000;
