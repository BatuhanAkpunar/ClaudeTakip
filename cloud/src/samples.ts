import type { RequestContext } from "./env.ts";
import { error, json, readJsonObject } from "./http.ts";
import {
  DOWNLOAD_DEFAULT_LIMIT,
  DOWNLOAD_MAX_LIMIT,
  MAX_BODY_BYTES,
  MAX_PLAN_LENGTH,
  MAX_SAMPLE_TIME_MS,
  MAX_SAMPLES_PER_UPLOAD,
  PERCENT_CEILING,
} from "./limits.ts";

/** Doğrulanmış ve kırpılmış, yazılmaya hazır örnek. */
type ParsedSample = { t: number; fiveHour: number; sevenDay: number; extra: number | null };

// Yüzdeler 0-1000 arasına kırpılıyor: 100 üstü ekstra kullanımda gerçekten
// görülüyor, ama sınırsız değil. NaN ve Infinity hiç geçmiyor, çünkü D1'e
// bağlandıklarında sorgu çalışma anında patlıyor.
function clampPercent(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.min(PERCENT_CEILING, Math.max(0, Math.round(value)))
    : null;
}

/** Ham örneği doğrular; geçersizse null. */
function parseSample(raw: unknown): ParsedSample | null {
  if (typeof raw !== "object" || raw === null) return null;
  const s = raw as Record<string, unknown>;
  const t = s.t;
  if (typeof t !== "number" || !Number.isFinite(t) || !(t > 0) || !(t < MAX_SAMPLE_TIME_MS)) {
    return null;
  }
  const fiveHour = clampPercent(s.fiveHour);
  const sevenDay = clampPercent(s.sevenDay);
  if (fiveHour === null || sevenDay === null) return null;
  return { t: Math.round(t), fiveHour, sevenDay, extra: clampPercent(s.extra) };
}

/**
 * Örnek yükleme.
 *
 * `INSERT OR IGNORE` sayesinde istemci aynı aralığı kaç kez gönderirse
 * göndersin sonuç aynı: ağ koptuğunda yeniden denemek güvenli.
 */
export async function uploadSamples({ request, env, deviceId, accountKey }: RequestContext): Promise<Response> {
  const read = await readJsonObject(request, MAX_BODY_BYTES);
  if (!read.ok) return read.response;
  const body = read.body;
  // Dizi olmayan `samples` denetlenmezse 500 üretir. Buradaki her denetim, istemcinin gönderdiği hatalı bir gövdenin
  // sunucu hatasına değil açık bir 400'e dönüşmesi için.
  if (body.samples !== undefined && !Array.isArray(body.samples)) {
    return error("samples bir dizi olmalı", 400);
  }
  if (body.plan !== undefined && body.plan !== null && typeof body.plan !== "string") {
    return error("plan bir metin olmalı", 400);
  }
  const plan = typeof body.plan === "string" ? body.plan.slice(0, MAX_PLAN_LENGTH) : null;

  const samples: unknown[] = Array.isArray(body.samples) ? body.samples : [];
  // D1 ücretsiz katmanında günlük 100 bin satır yazma var. Tek istekte
  // sınırsız satır kabul etmek hem bunu hem de Worker'ın 10 ms CPU
  // bütçesini zorluyor.
  if (samples.length > MAX_SAMPLES_PER_UPLOAD) {
    return error(`tek seferde en fazla ${MAX_SAMPLES_PER_UPLOAD} örnek`, 413);
  }

  const statement = env.DB.prepare(
    `INSERT INTO sample (device_id, t, five_hour, seven_day, extra, account_key)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(device_id, t) DO UPDATE SET
       account_key = COALESCE(excluded.account_key, sample.account_key)`,
  );
  const valid = samples.map(parseSample).filter((s): s is ParsedSample => s !== null);

  // Çakışmada satır silinmiyor, yalnızca hesap anahtarı dolduruluyor: aynı
  // örnek giriş öncesi anonim yazıldıysa giriş sonrası tekrar gönderildiğinde
  // hesaba bağlanıyor. Mükerrer satır oluşmuyor, çünkü anahtar (cihaz, zaman).
  const batch = valid.map((s) =>
    statement.bind(deviceId, s.t, s.fiveHour, s.sevenDay, s.extra, accountKey),
  );

  // Gerçekten eklenen satır sayısı raporlanıyor. Gönderilen sayıyı geri
  // vermek, mükerrer gönderimde her şeyi yazılmış gibi gösterir.
  let inserted = 0;
  if (batch.length > 0) {
    const outcome = await env.DB.batch(batch);
    inserted = outcome.reduce((total, result) => total + (result.meta?.changes ?? 0), 0);
  }

  // `last_seen_at` burada yazılmıyor: hız sınırı (consumeDeviceRequest) her
  // istekte zaten yazıyor, ikinci yazım yalnızca D1 yazma kotası harcıyordu.
  // Plan yalnızca gelmişse ve değişmişse yazılıyor.
  if (plan !== null) {
    await env.DB.prepare("UPDATE device SET plan = ? WHERE id = ? AND plan IS NOT ?")
      .bind(plan, deviceId, plan)
      .run();
  }

  // Reddedilenler de raporlanıyor: sessizce yutulsa istemci "yazıldı" sanır.
  return json({ received: batch.length, rejected: samples.length - valid.length, inserted });
}

/** İndirilen örnek satırı; alan adları tel sözleşmesinin parçası. */
type SampleRow = { t: number; fiveHour: number; sevenDay: number; extra: number | null };

/** Özet satırı; alan adları tel sözleşmesinin parçası. */
type SampleSummaryRow = { count: number; oldest: number | null; newest: number | null };

const EMPTY_SUMMARY: SampleSummaryRow = { count: 0, oldest: null, newest: null };

/** Örnek indirme. Yeni bir makineye kurulumda geçmişi geri yüklemek için. */
export async function downloadSamples({ url, env, deviceId, accountKey }: RequestContext): Promise<Response> {
  // NaN bir bağlamada sorguyu düşürür; her iki parametre de sayıya
  // zorlanıp aralığa kırpılıyor.
  const rawSince = Number(url.searchParams.get("since") ?? "0");
  const since = Number.isFinite(rawSince) && rawSince > 0 ? Math.round(rawSince) : 0;
  const rawLimit = Number(url.searchParams.get("limit") ?? String(DOWNLOAD_DEFAULT_LIMIT));
  const limit = Number.isFinite(rawLimit)
    ? Math.min(DOWNLOAD_MAX_LIMIT, Math.max(1, Math.round(rawLimit)))
    : DOWNLOAD_DEFAULT_LIMIT;

  // Girişliyse hesabın TÜM cihazlarındaki geçmiş, değilse yalnızca bu cihazın
  // anonim verisi.
  //
  // Hesap kipinde `GROUP BY t`: iki cihaz aynı anı yazdığında satır iki kez
  // döner ve limit kontenjanını iki kez tüketir. Özet `COUNT(DISTINCT t)`
  // sayıyor; indirme de aynı birimde saymalı ki kullanıcının gördüğü
  // "N ölçüm" indirilenle tutsun.
  const { results } = accountKey
    ? await env.DB.prepare(
        `SELECT t, MAX(five_hour) AS fiveHour, MAX(seven_day) AS sevenDay, MAX(extra) AS extra
         FROM sample WHERE account_key = ? AND t >= ?
         GROUP BY t ORDER BY t ASC LIMIT ?`,
      )
        .bind(accountKey, since, limit)
        .all<SampleRow>()
    : await env.DB.prepare(
        `SELECT t, five_hour AS fiveHour, seven_day AS sevenDay, extra
         FROM sample WHERE device_id = ? AND account_key IS NULL AND t >= ?
         ORDER BY t ASC LIMIT ?`,
      )
        .bind(deviceId, since, limit)
        .all<SampleRow>();

  // Sayfalama bilgisi: istemci tek isteğin tüm geçmişi getirdiğini
  // varsayamaz. Bu alan olmadan 5000 satırlık tavan sessizce en ESKİ 5000
  // satırı döndürür, yeniler hiç gelmez.
  const rows = results ?? [];
  const hasMore = rows.length >= limit;
  const last = rows.at(-1);
  const nextSince = hasMore && last ? last.t + 1 : null;

  return json({ samples: rows, hasMore, nextSince });
}

export async function sampleSummary({ env, deviceId, accountKey }: RequestContext): Promise<Response> {
  // DISTINCT t: iki cihaz aynı anı yazmışsa kullanıcıya iki ölçüm gibi
  // görünmemeli, yerel arşive de tek satır olarak inecek.
  const row = accountKey
    ? await env.DB.prepare(
        `SELECT COUNT(DISTINCT t) AS count, MIN(t) AS oldest, MAX(t) AS newest
         FROM sample WHERE account_key = ?`,
      )
        .bind(accountKey)
        .first<SampleSummaryRow>()
    : await env.DB.prepare(
        `SELECT COUNT(*) AS count, MIN(t) AS oldest, MAX(t) AS newest
         FROM sample WHERE device_id = ? AND account_key IS NULL`,
      )
        .bind(deviceId)
        .first<SampleSummaryRow>();

  return json(row ?? EMPTY_SUMMARY);
}

/**
 * Bu cihazın anonim satırlarını hesaba devreder.
 *
 * Giriş öncesi biriken geçmişin kaybolmamasını sağlayan adım. Yalnızca
 * `account_key IS NULL` satırlara dokunuyor: başka bir hesabın verisi
 * devralınamaz.
 */
export async function claimSamples({ env, deviceId, accountKey }: RequestContext): Promise<Response> {
  if (!accountKey) return error("hesap anahtarı gerekli", 400);
  const outcome = await env.DB.prepare(
    "UPDATE sample SET account_key = ? WHERE device_id = ? AND account_key IS NULL",
  )
    .bind(accountKey, deviceId)
    .run();
  return json({ claimed: outcome.meta?.changes ?? 0 });
}
