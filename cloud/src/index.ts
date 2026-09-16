/**
 * ClaudeTakip bulut senkronu.
 *
 * Tasarım kuralları:
 *
 * 1. Kimlik bilgisi asla buraya gelmez. claude.ai oturum anahtarı kullanıcının
 *    makinesinde kalır. Burada yalnızca kullanım yüzdeleri ve zaman damgaları
 *    tutulur, yani ele geçse bile bir hesaba erişim sağlamaz.
 *
 * 2. Kimlik doğrulama cihaz bazlı: cihaz ilk açılışta rastgele bir kimlik ve
 *    gizli anahtar alır, kullanıcıdan e-posta/parola istenmez. Verinin
 *    KAPSAMI ise hesap bazlı: giriş yapan istemci `x-account-key` başlığında
 *    organizasyon kimliğinin geri döndürülemez özetini gönderir. Ham kimlik
 *    hiç gelmez, ama aynı hesap her cihazda aynı anahtarı ürettiği için
 *    geçmiş cihaz değiştirince kaybolmaz.
 *
 *    `account_key IS NULL` olan satırlar giriş öncesi anonim veridir ve
 *    /v1/claim ile hesaba devredilir.
 *
 * 3. Bulut kaynak değil kopyadır. İstemci yerel veritabanını kaynak kabul eder,
 *    buraya yazar ve gerektiğinde buradan geri yükler. Servis düşerse uygulama
 *    çalışmaya devam eder.
 */

interface Env {
  /// Hız sınırı özetinin tuzu. Yoksa sabit bir varsayılana düşülüyor.
  IP_SALT?: string;
  DB: D1Database;
}

const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });
}

function error(message: string, status: number): Response {
  return json({ error: message }, status);
}

/**
 * `x-account-key` başlığı: 64 onaltılık karakter ya da yok.
 *
 * Biçim sıkı doğrulanıyor; serbest metin kabul etmek tabloyu çöp anahtarlarla
 * doldurulabilir hâle getirirdi.
 */
function accountKeyOf(request: Request): string | null {
  const raw = request.headers.get("x-account-key");
  if (!raw) return null;
  return /^[0-9a-f]{64}$/.test(raw) ? raw : null;
}

/**
 * Hız sınırı için istemci IP'sinin özeti.
 *
 * İki düzeltme birden. (1) TUZ: tuzsuz SHA-256 IPv4 için koruma değil, çünkü
 * dört milyar adresin tamamının özeti dakikalar içinde hesaplanabiliyor ve
 * tablodaki değer ham IP'ye geri çevrilebiliyordu. Tuz sunucuda kalıyor.
 * (2) IPv6 PREFİKS: IPv6'da tek kullanıcıya /64'lük bir blok veriliyor ve her
 * istek farklı bir adresten gelebiliyor; tam adresi özetlemek sınırı IPv6
 * kullanıcıları için tümüyle etkisiz bırakıyordu. Sınır artık bloğa uygulanıyor.
 */
async function hashClientIP(request: Request, env: Env): Promise<string> {
  const raw = request.headers.get("cf-connecting-ip") ?? "bilinmiyor";
  const scoped = raw.includes(":") ? raw.split(":").slice(0, 4).join(":") : raw;
  return sha256(`${env.IP_SALT ?? "claude-limit/ip/v1"}:${scoped}`);
}

/** Gizli anahtar düz metin saklanmaz; yalnızca özeti tutulur. */
async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * `Authorization: Bearer <deviceId>.<secret>` başlığını doğrular.
 *
 * Sabit süreli karşılaştırma kullanılmıyor: karşılaştırılan şey gizli anahtarın
 * kendisi değil SHA-256 özeti ve özet üzerinden zamanlama sızıntısıyla anahtarı
 * geri çıkarmak pratik değil.
 */
async function authenticate(request: Request, env: Env): Promise<Device | null> {
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  const separator = token.indexOf(".");
  if (separator <= 0) return null;

  const deviceId = token.slice(0, separator);
  const secret = token.slice(separator + 1);
  if (!deviceId || !secret) return null;

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

/** Kimliği doğrulanmış cihaz. */
type Device = { id: string; accountKey: string | null; accountChanges: number };

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
 * bağlanıyor. Sonrasında eşleşmeyen anahtar 403.
 */
const ACCOUNT_CHANGE_LIMIT = 10;

async function resolveScope(
  request: Request,
  env: Env,
  device: Device,
): Promise<{ ok: true; accountKey: string | null } | { ok: false; response: Response }> {
  const requested = accountKeyOf(request);

  // Anahtar gönderilmemiş: anonim kapsam. Cihaz bir hesaba bağlı olsa bile
  // kendi anonim satırlarına erişmesi meşru (giriş öncesi veri).
  if (!requested) return { ok: true, accountKey: null };

  if (device.accountKey === requested) return { ok: true, accountKey: requested };

  if (device.accountKey === null) {
    // İlk kullanımda güven: cihazı bu hesaba bağla.
    if (device.accountChanges >= ACCOUNT_CHANGE_LIMIT) {
      return { ok: false, response: error("hesap değişiklik sınırı aşıldı", 429) };
    }
    await env.DB.prepare(
      "UPDATE device SET account_key = ?, account_bound_at = ?, account_changes = account_changes + 1 WHERE id = ? AND account_key IS NULL",
    )
      .bind(requested, Date.now(), device.id)
      .run();
    device.accountKey = requested;
    return { ok: true, accountKey: requested };
  }

  // Cihaz BAŞKA bir hesaba bağlı. Bu, kapsam sınırının tek gerçek kapısı.
  return { ok: false, response: error("bu cihaz o hesaba bağlı değil", 403) };
}

/**
 * Yeni cihaz kaydı. Kullanıcıdan hiçbir bilgi istenmez.
 *
 * Tek kimliksiz uç olduğu için IP başına saatlik bir tavan var: aksi halde bir
 * betik dakikalar içinde D1'in ücretsiz katmanındaki günlük yazma kotasını
 * tüketip servisi bütün kullanıcılara kapatabiliyordu. Tavan cihaz tablosunun
 * kendisinden sayılıyor, ayrı bir sayaç deposu gerekmiyor.
 */
/// Ofis ya da operatör NAT'ı arkasında çok sayıda gerçek kullanıcı aynı IP'yi
/// paylaşıyor ve kayıt cihaz ömründe bir kez oluyor: sınır kötüye kullanımı
/// durduracak kadar düşük, meşru bir ekibi kapıda bırakmayacak kadar yüksek.
const REGISTRATIONS_PER_IP_PER_HOUR = 20;

/** Yükleme gövdesi için sert tavan. */
const MAX_BODY_BYTES = 512 * 1024;

/**
 * Gövdeyi en fazla `limit` bayt okur, aşarsa null döner.
 *
 * `request.text()` sınır tanımıyor: bildirilen uzunluğa güvenmek yerine
 * akışı sayarak okumak, chunked gönderimde de gerçek bir tavan sağlıyor.
 */
async function readBoundedText(request: Request, limit: number): Promise<string | null> {
  const reader = request.body?.getReader();
  if (!reader) return "";
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    if (value) {
      total += value.byteLength;
      if (total > limit) {
        await reader.cancel();
        return null;
      }
      chunks.push(value);
    }
  }
  const merged = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    merged.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(merged);
}

async function registerDevice(request: Request, env: Env): Promise<Response> {
  const ipHash = await hashClientIP(request, env);
  const hourAgo = Date.now() - 3600_000;

  // Sayaç cihaz tablosundan değil ayrı bir günlükten okunuyor: cihaz
  // tablosundan sayıldığında kaydolup hemen silmek sınırı sıfırlıyordu.
  const recent = await env.DB.prepare(
    "SELECT COUNT(*) AS count FROM registration_log WHERE ip_hash = ? AND created_at > ?",
  )
    .bind(ipHash, hourAgo)
    .first<{ count: number }>();

  if ((recent?.count ?? 0) >= REGISTRATIONS_PER_IP_PER_HOUR) {
    return error("çok fazla kayıt denemesi, bir saat sonra tekrar deneyin", 429);
  }

  const deviceId = crypto.randomUUID();
  const secret = crypto.randomUUID().replace(/-/g, "");
  const now = Date.now();

  await env.DB.prepare(
    "INSERT INTO device (id, secret_hash, created_at, last_seen_at, ip_hash) VALUES (?, ?, ?, ?, ?)",
  )
    .bind(deviceId, await sha256(secret), now, now, ipHash)
    .run();

  await env.DB.batch([
    env.DB.prepare("INSERT INTO registration_log (ip_hash, created_at) VALUES (?, ?)")
      .bind(ipHash, now),
    // Günlük kendini buduyor: sınır bir saatlik, daha eskisi yer kaplamasın.
    env.DB.prepare("DELETE FROM registration_log WHERE created_at < ?").bind(hourAgo),
  ]);

  return json({ deviceId, secret });
}

interface SamplePayload {
  t: number;
  fiveHour: number;
  sevenDay: number;
  extra?: number | null;
}

/**
 * Örnek yükleme.
 *
 * `INSERT OR IGNORE` sayesinde istemci aynı aralığı kaç kez gönderirse
 * göndersin sonuç aynı: ağ koptuğunda yeniden denemek güvenli.
 */
async function uploadSamples(
  request: Request,
  env: Env,
  deviceId: string,
  accountKey: string | null,
): Promise<Response> {
  // Gövde SINIRLI okunuyor: `request.json()` boyuta bakmadan tamamını belleğe
  // alıyordu, dolayısıyla chunked bir istek content-length denetimini atlayıp
  // Worker'ın bellek ve CPU bütçesini tüketebiliyordu.
  const text = await readBoundedText(request, MAX_BODY_BYTES);
  if (text === null) return error("gövde çok büyük", 413);
  let payload: unknown;
  try {
    payload = JSON.parse(text);
  } catch {
    return error("gövde okunamadı", 400);
  }
  if (typeof payload !== "object" || payload === null) {
    return error("gövde bir nesne olmalı", 400);
  }

  const body = payload as { samples?: unknown; plan?: unknown };
  // Dizi olmayan `samples` doğrudan 500 üretiyordu: `.filter` bir nesnede
  // yok. Buradaki her denetim, istemcinin gönderdiği hatalı bir gövdenin
  // sunucu hatasına değil açık bir 400'e dönüşmesi için.
  if (body.samples !== undefined && !Array.isArray(body.samples)) {
    return error("samples bir dizi olmalı", 400);
  }
  if (body.plan !== undefined && body.plan !== null && typeof body.plan !== "string") {
    return error("plan bir metin olmalı", 400);
  }
  const plan = typeof body.plan === "string" ? body.plan.slice(0, 64) : null;

  const samples = (body.samples ?? []) as unknown[];
  // D1 ücretsiz katmanında günlük 100 bin satır yazma var. Tek istekte
  // sınırsız satır kabul etmek hem bunu hem de Worker'ın 10 ms CPU
  // bütçesini zorluyor.
  if (samples.length > 1000) {
    return error("tek seferde en fazla 1000 örnek", 413);
  }

  const statement = env.DB.prepare(
    `INSERT INTO sample (device_id, t, five_hour, seven_day, extra, account_key)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(device_id, t) DO UPDATE SET
       account_key = COALESCE(excluded.account_key, sample.account_key)`,
  );
  // Yüzdeler 0-1000 arasına kırpılıyor: 100 üstü ekstra kullanımda gerçekten
  // görülüyor, ama sınırsız değil. NaN ve Infinity hiç geçmiyor, çünkü D1'e
  // bağlandıklarında sorgu çalışma anında patlıyor.
  const percent = (value: unknown): number | null =>
    typeof value === "number" && Number.isFinite(value)
      ? Math.min(1000, Math.max(0, Math.round(value)))
      : null;

  const valid = samples.filter((raw): raw is SamplePayload => {
    if (typeof raw !== "object" || raw === null) return false;
    const s = raw as SamplePayload;
    return (
      typeof s.t === "number" &&
      Number.isFinite(s.t) &&
      s.t > 0 &&
      s.t < 4102444800000 && // 2100'den sonrası saçma bir zaman damgası
      percent(s.fiveHour) !== null &&
      percent(s.sevenDay) !== null
    );
  });

  // Çakışmada satır silinmiyor, yalnızca hesap anahtarı dolduruluyor: aynı
  // örnek giriş öncesi anonim yazıldıysa giriş sonrası tekrar gönderildiğinde
  // hesaba bağlanıyor. Mükerrer satır oluşmuyor, çünkü anahtar (cihaz, zaman).
  const batch = valid.map((s) =>
    statement.bind(
      deviceId,
      Math.round(s.t),
      percent(s.fiveHour),
      percent(s.sevenDay),
      percent(s.extra),
      accountKey,
    ),
  );

  // Gerçekten eklenen satır sayısı raporlanıyor. Gönderilen sayıyı geri
  // vermek, mükerrer gönderimde her şey yazılmış gibi görünmesine yol açıyordu.
  let inserted = 0;
  if (batch.length > 0) {
    const outcome = await env.DB.batch(batch);
    inserted = outcome.reduce((total, result) => total + (result.meta?.changes ?? 0), 0);
  }

  await env.DB.prepare(
    "UPDATE device SET last_seen_at = ?, plan = COALESCE(?, plan) WHERE id = ?",
  )
    .bind(Date.now(), plan, deviceId)
    .run();

  // Reddedilenler de raporlanıyor: sessizce yutmak istemcide "yazıldı"
  // sanılmasına yol açıyordu.
  return json({ received: batch.length, rejected: samples.length - valid.length, inserted });
}

/** Örnek indirme. Yeni bir makineye kurulumda geçmişi geri yüklemek için. */
async function downloadSamples(
  url: URL,
  env: Env,
  deviceId: string,
  accountKey: string | null,
): Promise<Response> {
  // NaN bir bağlamada sorguyu düşürüyordu; her iki parametre de sayıya
  // zorlanıp aralığa kırpılıyor.
  const rawSince = Number(url.searchParams.get("since") ?? "0");
  const since = Number.isFinite(rawSince) && rawSince > 0 ? Math.round(rawSince) : 0;
  const rawLimit = Number(url.searchParams.get("limit") ?? "5000");
  const limit = Number.isFinite(rawLimit)
    ? Math.min(10000, Math.max(1, Math.round(rawLimit)))
    : 5000;

  // Girişliyse hesabın TÜM cihazlarındaki geçmiş, değilse yalnızca bu cihazın
  // anonim verisi.
  //
  // Hesap kipinde `GROUP BY t`: iki cihaz aynı anı yazdığında satır iki kez
  // dönüyor ve limit kontenjanını iki kez tüketiyordu. Özet ise
  // `COUNT(DISTINCT t)` sayıyor, yani ikisi farklı birimdeydi ve kullanıcı
  // "N ölçüm" görürken indirme çok daha azını getiriyordu.
  const { results } = accountKey
    ? await env.DB.prepare(
        `SELECT t, MAX(five_hour) AS fiveHour, MAX(seven_day) AS sevenDay, MAX(extra) AS extra
         FROM sample WHERE account_key = ? AND t >= ?
         GROUP BY t ORDER BY t ASC LIMIT ?`,
      )
        .bind(accountKey, since, limit)
        .all()
    : await env.DB.prepare(
        `SELECT t, five_hour AS fiveHour, seven_day AS sevenDay, extra
         FROM sample WHERE device_id = ? AND account_key IS NULL AND t >= ?
         ORDER BY t ASC LIMIT ?`,
      )
        .bind(deviceId, since, limit)
        .all();

  // Sayfalama bilgisi: istemci tek isteğin tüm geçmişi getirdiğini
  // varsayamaz. Bu alan olmadan 5000 satırlık tavan sessizce en ESKİ 5000
  // satırı döndürüyor, yenileri hiç gelmiyordu.
  const rows = (results ?? []) as { t: number }[];
  const hasMore = rows.length >= limit;
  const nextSince = hasMore && rows.length > 0 ? rows[rows.length - 1].t + 1 : null;

  return json({ samples: rows, hasMore, nextSince });
}

async function summary(
  env: Env,
  deviceId: string,
  accountKey: string | null,
): Promise<Response> {
  // DISTINCT t: iki cihaz aynı anı yazmışsa kullanıcıya iki ölçüm gibi
  // görünmemeli, yerel arşive de tek satır olarak inecek.
  const row = accountKey
    ? await env.DB.prepare(
        `SELECT COUNT(DISTINCT t) AS count, MIN(t) AS oldest, MAX(t) AS newest
         FROM sample WHERE account_key = ?`,
      )
        .bind(accountKey)
        .first<{ count: number; oldest: number | null; newest: number | null }>()
    : await env.DB.prepare(
        `SELECT COUNT(*) AS count, MIN(t) AS oldest, MAX(t) AS newest
         FROM sample WHERE device_id = ? AND account_key IS NULL`,
      )
        .bind(deviceId)
        .first<{ count: number; oldest: number | null; newest: number | null }>();

  return json(row ?? { count: 0, oldest: null, newest: null });
}

/**
 * Bu cihazın anonim satırlarını hesaba devreder.
 *
 * Giriş öncesi biriken geçmişin kaybolmamasını sağlayan adım. Yalnızca
 * `account_key IS NULL` satırlara dokunuyor: başka bir hesabın verisi
 * devralınamaz.
 */
async function claimSamples(
  env: Env,
  deviceId: string,
  accountKey: string | null,
): Promise<Response> {
  if (!accountKey) return error("hesap anahtarı gerekli", 400);
  const outcome = await env.DB.prepare(
    "UPDATE sample SET account_key = ? WHERE device_id = ? AND account_key IS NULL",
  )
    .bind(accountKey, deviceId)
    .run();
  return json({ claimed: outcome.meta?.changes ?? 0 });
}

/**
 * Kullanıcının gördüğü veriyi siler.
 *
 * Girişliyse hesabın tüm geçmişi (gördüğü buysa), değilse yalnızca bu cihazın
 * anonim verisi. Cihaz kaydı her hâlükârda siliniyor.
 */
async function deleteDevice(
  env: Env,
  deviceId: string,
  accountKey: string | null,
): Promise<Response> {
  // Silme sayısı gerçek etkiyi taşıyor: istemci "silindi" demeden önce
  // sunucunun gerçekten bir şey sildiğini görebilsin. Eskiden yanıt her
  // durumda `{deleted:true}` idi ve hiçbir satır silinmemiş olsa bile
  // kullanıcıya başarı gösteriliyordu.
  const [samplesResult] = await env.DB.batch([
    accountKey
      ? env.DB.prepare("DELETE FROM sample WHERE account_key = ?").bind(accountKey)
      : env.DB.prepare("DELETE FROM sample WHERE device_id = ? AND account_key IS NULL").bind(deviceId),
    env.DB.prepare("DELETE FROM device WHERE id = ?").bind(deviceId),
  ]);
  const removed = samplesResult?.meta?.changes ?? 0;
  return json({ deleted: true, removed });
}

/**
 * Cihaz başına kayan pencere sınırı: dakikada en fazla `DEVICE_REQUESTS_PER_MINUTE`.
 *
 * Sayaç `device` satırının kendisinde tutuluyor, ayrı bir depoya gerek yok:
 * `last_seen_at` zaten her istekte güncelleniyordu.
 */
const DEVICE_REQUESTS_PER_MINUTE = 30;

async function withinDeviceRate(env: Env, deviceId: string): Promise<boolean> {
  const now = Date.now();
  const row = await env.DB.prepare(
    "SELECT rate_window_start, rate_count FROM device WHERE id = ?",
  )
    .bind(deviceId)
    .first<{ rate_window_start: number | null; rate_count: number | null }>();

  const start = row?.rate_window_start ?? 0;
  const count = row?.rate_count ?? 0;
  const fresh = now - start > 60_000;

  if (!fresh && count >= DEVICE_REQUESTS_PER_MINUTE) return false;

  await env.DB.prepare(
    "UPDATE device SET last_seen_at = ?, rate_window_start = ?, rate_count = ? WHERE id = ?",
  )
    .bind(now, fresh ? now : start, fresh ? 1 : count + 1, deviceId)
    .run();
  return true;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/v1/health") {
      return json({ ok: true });
    }

    // Kayıt tek kimliksiz uç. Diğer her şey cihaz kimliği ister.
    if (path === "/v1/devices" && request.method === "POST") {
      return registerDevice(request, env);
    }

    const device = await authenticate(request, env);
    if (!device) return error("kimlik doğrulanamadı", 401);
    const deviceId = device.id;

    // Hesap kapsamı, cihazın gerçekten o hesaba bağlı olmasına dayanıyor.
    // `/v1/claim` bu kapıdan geçen tek istisna değil: o da aynı bağı kuruyor,
    // yalnızca bağ yokken.
    const scope = await resolveScope(request, env, device);
    if (!scope.ok) return scope.response;
    const accountKey = scope.accountKey;

    // Cihaz başına hız sınırı. Kayıt dışındaki uçlar şimdiye kadar tümüyle
    // korumasızdı: tek bir cihaz kimliğiyle sınırsız istek atıp D1'in günlük
    // okuma kotasını tüketmek ve servisi herkese kapatmak mümkündü. İstemci
    // dakikada bir istek atıyor; bu tavan onun çok üstünde, kötüye kullanımın
    // çok altında.
    if (!(await withinDeviceRate(env, deviceId))) {
      return error("çok fazla istek", 429);
    }

    if (path === "/v1/samples" && request.method === "POST") {
      // Devasa bir gövdeyi ayrıştırmaya hiç başlamamak, ayrıştırdıktan sonra
      // reddetmekten ucuz: Worker'ın CPU bütçesi 10 ms.
      // content-length yalnızca UCUZ bir ön eleme: chunked gönderimde başlık
      // hiç gelmiyor ve sınır atlatılabiliyordu. Gerçek sınır gövde okunurken
      // uygulanıyor (readBoundedText).
      const declared = Number(request.headers.get("content-length") ?? "0");
      if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
        return error("gövde çok büyük", 413);
      }
      return uploadSamples(request, env, deviceId, accountKey);
    }
    if (path === "/v1/samples" && request.method === "GET") {
      return downloadSamples(url, env, deviceId, accountKey);
    }
    if (path === "/v1/summary" && request.method === "GET") {
      return summary(env, deviceId, accountKey);
    }
    if (path === "/v1/claim" && request.method === "POST") {
      return claimSamples(env, deviceId, accountKey);
    }
    if (path === "/v1/device" && request.method === "DELETE") {
      return deleteDevice(env, deviceId, accountKey);
    }

    return error("bulunamadı", 404);
  },
} satisfies ExportedHandler<Env>;
