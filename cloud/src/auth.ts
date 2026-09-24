import type { Env } from "./env.ts";
import { error } from "./http.ts";
import {
  ACCOUNT_CHANGE_LIMIT,
  ACCOUNT_CHANGE_WINDOW_MS,
  ACCOUNT_KEY_PATTERN,
  ACTIVE_DEVICE_WINDOW_MS,
  BIND_LOG_RETENTION_MS,
  MAX_ACTIVE_DEVICES_PER_ACCOUNT,
  NEW_BIND_WINDOW_MS,
  NEW_BINDS_PER_ACCOUNT_PER_DAY,
  BEARER_PREFIX,
  DEVICE_RATE_WINDOW_MS,
  DEVICE_REQUESTS_PER_MINUTE,
} from "./limits.ts";

/**
 * `x-account-key` başlığı: 64 onaltılık karakter ya da yok.
 *
 * Biçim sıkı doğrulanıyor; serbest metin kabul etmek tabloyu çöp anahtarlarla
 * doldurulabilir hâle getirirdi.
 */
export function accountKeyOf(request: Request): string | null {
  const raw = request.headers.get("x-account-key");
  if (!raw) return null;
  return ACCOUNT_KEY_PATTERN.test(raw) ? raw : null;
}

/**
 * Hız sınırı için istemci IP'sinin özeti.
 *
 * Tuz: tuzsuz SHA-256 IPv4 uzayında tersine çevrilebilir (dört milyar adresin
 * özeti dakikalar içinde hesaplanır). Tuz sunucuda kalıyor.
 * IPv6: kullanıcıya /64 verilir ve her istek farklı bir adresten gelebilir;
 * sınır bloğa uygulanır.
 */
export async function hashClientIP(request: Request, env: Env): Promise<string> {
  const raw = request.headers.get("cf-connecting-ip") ?? "bilinmiyor";
  return sha256(`${await ipSalt(env)}:${ipScope(raw)}`);
}

/**
 * IP özetinin tuzu: `IP_SALT` sırrı, yoksa veritabanında saklanan rastgele
 * bir değer.
 *
 * Eskiden sır yoksa depoda yazılı sabit bir tuza düşülüyordu. Tuz herkese
 * açıkken özet koruma değil: IPv4'ün tamamı dakikalar içinde özetlenip
 * günlükteki değerler ham IP'ye çevrilebiliyordu. Rastgele tuz ilk ihtiyaçta
 * üretiliyor (INSERT OR IGNORE: eşzamanlı ilk istekler aynı değeri okuyor)
 * ve izolat ömrü boyunca bellekte tutuluyor.
 *
 * Önbellekte Promise değil çözülmüş değer duruyor: Workers bir isteğin
 * başlattığı G/Ç'nin başka bir istekte beklenmesine izin vermiyor.
 */
const saltCache = new WeakMap<D1Database, string>();

async function ipSalt(env: Env): Promise<string> {
  if (env.IP_SALT) return env.IP_SALT;
  const cached = saltCache.get(env.DB);
  if (cached) return cached;
  const random = [...crypto.getRandomValues(new Uint8Array(32))]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  const results = await env.DB.batch<{ value: string }>([
    env.DB.prepare("INSERT OR IGNORE INTO server_secret (name, value) VALUES ('ip_salt', ?)").bind(random),
    env.DB.prepare("SELECT value FROM server_secret WHERE name = 'ip_salt'"),
  ]);
  const value = results[1]?.results?.[0]?.value;
  if (!value) throw new Error("ip_salt okunamadı");
  saltCache.set(env.DB, value);
  return value;
}

/**
 * Hız sınırının uygulandığı adres birimi: IPv4'te adresin kendisi, IPv6'da
 * /64 bloğu.
 *
 * Eskiden IPv6 adresi ':' ile bölünüp ilk dört parça alınıyordu. Sıkıştırılmış
 * yazımda ('::') bu parçalar ilk dört GRUP değil: `2001:db8::1` ile
 * `2001:db8::2` farklı anahtar üretiyordu ve aynı /64 içinde adres değiştirerek
 * kayıt tavanı atlanabiliyordu. Adres önce sekiz gruba açılıyor.
 */
function ipScope(raw: string): string {
  if (!raw.includes(":")) return raw;
  // Bölge kimliği (fe80::1%en0) adresin parçası değil.
  let address = (raw.split("%")[0] ?? raw).toLowerCase();

  // IPv4-eşlemeli adres (::ffff:1.2.3.4) gerçekte bir IPv4 istemcisi.
  const mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/.exec(address);
  if (mapped?.[1]) return mapped[1];

  // Sonda gömülü IPv4 varsa iki gruba çevir ki grup sayısı tutsun.
  const tail = /(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(address);
  if (tail) {
    const [a = 0, b = 0, c = 0, d = 0] = tail.slice(1).map(Number);
    address =
      address.slice(0, tail.index) + ((a << 8) | b).toString(16) + ":" + ((c << 8) | d).toString(16);
  }

  const halves = address.split("::");
  if (halves.length > 2) return raw;
  const compressed = halves.length === 2;
  const head = halves[0] ? halves[0].split(":") : [];
  const rest = compressed && halves[1] ? halves[1].split(":") : [];
  const missing = 8 - head.length - rest.length;
  if (compressed ? missing < 1 : missing !== 0) return raw;
  const groups = [...head, ...Array<string>(compressed ? missing : 0).fill("0"), ...rest];
  if (!groups.every((g) => /^[0-9a-f]{1,4}$/.test(g))) return raw;

  return (
    groups
      .slice(0, 4)
      .map((g) => g.padStart(4, "0"))
      .join(":") + "::/64"
  );
}

/** Metnin SHA-256 özeti, küçük harfli onaltılık. */
export async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** `Bearer <deviceId>.<secret>` başlığını parçalarına ayırır; biçim bozuksa null. */
function parseBearer(request: Request): { deviceId: string; secret: string } | null {
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith(BEARER_PREFIX) ? header.slice(BEARER_PREFIX.length) : "";
  const separator = token.indexOf(".");
  if (separator <= 0) return null;

  const deviceId = token.slice(0, separator);
  const secret = token.slice(separator + 1);
  if (!deviceId || !secret) return null;
  return { deviceId, secret };
}

/**
 * `Authorization: Bearer <deviceId>.<secret>` başlığını doğrular.
 *
 * Sabit süreli karşılaştırma kullanılmıyor: karşılaştırılan şey gizli anahtarın
 * kendisi değil SHA-256 özeti ve özet üzerinden zamanlama sızıntısıyla anahtarı
 * geri çıkarmak pratik değil.
 */
export async function authenticate(request: Request, env: Env): Promise<Device | null> {
  const credentials = parseBearer(request);
  if (!credentials) return null;
  const { deviceId, secret } = credentials;

  const row = await env.DB.prepare(
    "SELECT secret_hash, account_key, account_changes FROM device WHERE id = ?",
  )
    .bind(deviceId)
    .first<{ secret_hash: string; account_key: string | null; account_changes: number }>();
  if (!row) return null;

  const hash = await sha256(secret);
  if (hash !== row.secret_hash) return null;
  return { id: deviceId, accountKey: row.account_key, accountChanges: row.account_changes ?? 0 };
}

type BindResult = { ok: true } | { ok: false; response: Response };

/**
 * Cihazı `requested` hesaba bağlamayı dener. Karar, tavanlar ve günlük girdisi
 * tek batch'te: koşullu UPDATE yalnızca tavanların altındaysa satırı
 * değiştiriyor, günlük girdisi yalnızca UPDATE gerçekleştiyse yazılıyor.
 */
async function bindDevice(
  request: Request,
  env: Env,
  device: Readonly<Device>,
  requested: string,
): Promise<BindResult> {
  const now = Date.now();
  const ipHash = await hashClientIP(request, env);
  const [update] = await env.DB.batch([
    env.DB.prepare(
      `UPDATE device SET account_key = ?1, account_bound_at = ?2, account_changes = account_changes + 1
       WHERE id = ?3
         -- Karşılaştır-değiştir: bağ, bu isteğin gördüğü hâldeyse değişiyor.
         AND account_key IS ?8
         AND (SELECT COUNT(*) FROM account_bind_log
              WHERE device_id = ?3 AND created_at > ?9) < ?10
         AND (SELECT COUNT(*) FROM device
              WHERE account_key = ?1 AND id <> ?3 AND last_seen_at > ?4) < ?5
         AND (SELECT COUNT(*) FROM account_bind_log
              WHERE account_key = ?1 AND created_at > ?6) < ?7`,
    ).bind(
      requested,
      now,
      device.id,
      now - ACTIVE_DEVICE_WINDOW_MS,
      MAX_ACTIVE_DEVICES_PER_ACCOUNT,
      now - NEW_BIND_WINDOW_MS,
      NEW_BINDS_PER_ACCOUNT_PER_DAY,
      device.accountKey,
      now - ACCOUNT_CHANGE_WINDOW_MS,
      ACCOUNT_CHANGE_LIMIT,
    ),
    env.DB.prepare(
      `INSERT INTO account_bind_log (account_key, device_id, ip_hash, created_at, had_data)
       SELECT ?1, ?2, ?3, ?4, EXISTS (SELECT 1 FROM sample WHERE account_key = ?1)
       WHERE EXISTS (SELECT 1 FROM device WHERE id = ?2 AND account_key = ?1 AND account_bound_at = ?4)`,
    ).bind(requested, device.id, ipHash, now),
    env.DB.prepare("DELETE FROM account_bind_log WHERE created_at < ?").bind(now - BIND_LOG_RETENTION_MS),
  ]);

  if ((update?.meta?.changes ?? 0) > 0) {
    const logged = await env.DB.prepare(
      "SELECT had_data FROM account_bind_log WHERE device_id = ? AND account_key = ? AND created_at = ?",
    )
      .bind(device.id, requested, now)
      .first<{ had_data: number }>();
    if (logged?.had_data) {
      // Verisi olan bir hesaba yeni cihaz: meşru (yeni Mac) ya da ilk
      // kullanımda güvenin kötüye kullanımı. Ayırt edilemiyor; görünür olsun.
      console.warn("verisi olan hesaba yeni cihaz bağlandı", {
        account: requested.slice(0, 12),
        device: device.id,
      });
    }
    return { ok: true };
  }

  // UPDATE gerçekleşmedi: ya araya başka bir istek girip cihazı bağladı (#50)
  // ya da hesap tavanlarından biri doldu.
  const current = await env.DB.prepare("SELECT account_key FROM device WHERE id = ?")
    .bind(device.id)
    .first<{ account_key: string | null }>();
  if (current?.account_key === requested) return { ok: true };
  if ((current?.account_key ?? null) !== device.accountKey) {
    // Bu istek sürerken bağ başka bir istekle değişti; yarışı kaybeden
    // istek kapsam almıyor.
    return { ok: false, response: error("bu cihaz o hesaba bağlı değil", 403) };
  }
  const changes = await env.DB.prepare(
    "SELECT COUNT(*) AS n FROM account_bind_log WHERE device_id = ? AND created_at > ?",
  )
    .bind(device.id, now - ACCOUNT_CHANGE_WINDOW_MS)
    .first<{ n: number }>();
  if ((changes?.n ?? 0) >= ACCOUNT_CHANGE_LIMIT) {
    return { ok: false, response: error("hesap değişiklik sınırı aşıldı", 429) };
  }
  console.warn("hesaba cihaz bağlama tavanı doldu", { account: requested.slice(0, 12), device: device.id });
  return { ok: false, response: error("bu hesaba çok fazla cihaz bağlandı, daha sonra tekrar deneyin", 429) };
}

/** Kimliği doğrulanmış cihaz. */
export type Device = { id: string; accountKey: string | null; accountChanges: number };

/**
 * Bir cihazın hangi hesap kapsamında çalışabileceğine karar verir.
 *
 * Hesap anahtarı bir sır değil: istemciye gömülü bir pepper ile organizasyon
 * kimliğinin özeti, ve organizasyon kimliği claude.ai yanıtlarında görülebilen
 * bir değer. Bu yüzden başlıktaki anahtar tek başına yetki sayılamaz; sunucu
 * cihazın O hesaba bağlı olduğunu da görmek zorunda. Aksi halde geçerli bir
 * cihaz kaydı olan herkes başkasının geçmişini okuyabilir, zehirleyebilir ve
 * silebilirdi.
 *
 * Bağ ilk kullanımda kuruluyor: bağsız bir cihaz gönderdiği ilk anahtara
 * bağlanıyor. Sonrasında başka bir anahtar cihazı yeniden bağlıyor (aynı
 * tavanlarla); bağ yarışını kaybeden istek 403.
 *
 * İLK KULLANIMDA GÜVENİN SINIRI (#48): anahtarı bilen herkes yeni bir cihaz
 * kaydedip o hesaba bağlanabiliyor. Gerçek çözüm hesap sahipliğinin kanıtı
 * (istemcinin sunucunun doğrulayabileceği bir şey sunması, ya da hesaba ilk
 * bağlanan cihazın yeni cihazları onaylaması) ve yayındaki istemci bunu
 * sağlayamıyor. O gelene kadar bağlama SINIRLI ve KAYITLI:
 *  - hesaba 30 günde görülmüş en fazla MAX_ACTIVE_DEVICES_PER_ACCOUNT cihaz,
 *  - hesaba 24 saatte en fazla NEW_BINDS_PER_ACCOUNT_PER_DAY yeni bağ,
 *  - her bağ account_bind_log'a yazılıyor; verisi olan bir hesaba yeni cihaz
 *    bağlanması ayrıca günlüğe uyarı olarak düşüyor.
 * Böylece bir saldırgan bir hesabı sessizce ve sınırsız sayıda cihazla
 * dolaşamıyor; yapabildiği iz bırakıyor ve günde birkaç denemeyle sınırlı.
 */
type ScopeResult = { ok: true; accountKey: string | null } | { ok: false; response: Response };

export async function resolveScope(
  request: Request,
  env: Env,
  device: Readonly<Device>,
  requested: string | null,
): Promise<ScopeResult> {
  // Anahtar gönderilmemiş: anonim kapsam. Cihaz bir hesaba bağlı olsa bile
  // kendi anonim satırlarına erişmesi meşru (giriş öncesi veri).
  if (!requested) return { ok: true, accountKey: null };

  if (device.accountKey === requested) return { ok: true, accountKey: requested };

  // Bağsız cihaz: ilk kullanımda güven. Başka hesaba bağlı cihaz: yeniden
  // bağlama (#49). Kullanıcı aynı Mac'te başka bir Claude hesabına geçince
  // eskiden sonsuza kadar 403 alıyordu ve ACCOUNT_CHANGE_LIMIT hiç
  // erişilemiyordu. Yeniden bağlama, ilk bağlamayla AYNI kapıdan geçiyor
  // (hesap tavanları + günlük) ve cihaz başına ACCOUNT_CHANGE_WINDOW_MS
  // içinde ACCOUNT_CHANGE_LIMIT bağla sınırlı. İlk kullanımda güvenin üstüne
  // yeni bir yetki eklemiyor: aynı hesaba yeni bir cihaz kaydedip bağlamak
  // zaten mümkündü, üstelik yalnızca cihazın kendi sırrını bilen onu yeniden
  // bağlayabiliyor.
  //
  // Koşullu UPDATE hiçbir satırı değiştirmediyse araya başka bir istek
  // girip cihazı bağlamış ya da bir tavan dolmuş demektir. Eskiden sonuç
  // yok sayılıyor ve bu istek, cihaz BAŞKA bir hesaba bağlanmış olsa bile
  // istediği kapsamda çalışıyordu (#50). Karar bindDevice'ta.
  const bound = await bindDevice(request, env, device, requested);
  if (!bound.ok) return bound;
  return { ok: true, accountKey: requested };
}

/**
 * Cihazın hız sınırı kovasına bu isteği YAZAR ve sınır içindeyse true döner.
 * Yalnızca bir denetim değil: her çağrı bir istek hakkı tüketir.
 *
 * Karar ve artış TEK koşullu UPDATE'te. Eskiden önce okunup sonra yazılıyordu:
 * eşzamanlı istekler aynı sayacı okuyup aynı değeri yazdığı için artışlar
 * kayboluyor, bir patlama sınırın çok üstüne çıkabiliyordu. Artık satır
 * yalnızca sınır altındaysa (ya da pencere yenilendiyse) güncelleniyor ve
 * izin, etkilenen satır sayısından okunuyor.
 */
export async function consumeDeviceRequest(env: Env, deviceId: string): Promise<boolean> {
  const outcome = await env.DB.prepare(
    `UPDATE device SET
       last_seen_at = ?1,
       rate_count = CASE
         WHEN rate_window_start IS NULL OR ?1 - rate_window_start > ?4 THEN 1
         ELSE rate_count + 1 END,
       rate_window_start = CASE
         WHEN rate_window_start IS NULL OR ?1 - rate_window_start > ?4 THEN ?1
         ELSE rate_window_start END
     WHERE id = ?2
       AND (rate_window_start IS NULL OR ?1 - rate_window_start > ?4 OR rate_count < ?3)`,
  )
    .bind(Date.now(), deviceId, DEVICE_REQUESTS_PER_MINUTE, DEVICE_RATE_WINDOW_MS)
    .run();
  return (outcome.meta?.changes ?? 0) > 0;
}
