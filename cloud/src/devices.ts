import type { Env, RequestContext } from "./env.ts";
import { hashClientIP, sha256 } from "./auth.ts";
import { error, json } from "./http.ts";
import { REGISTRATION_WINDOW_MS, REGISTRATIONS_PER_IP_PER_HOUR } from "./limits.ts";

/**
 * Yeni cihaz kaydı. Kullanıcıdan hiçbir bilgi istenmez.
 *
 * Tek kimliksiz uç olduğu için IP başına saatlik bir tavan var: aksi halde bir
 * betik dakikalar içinde D1'in ücretsiz katmanındaki günlük yazma kotasını
 * tüketip servisi bütün kullanıcılara kapatabilir. Tavan `registration_log`
 * günlüğünden sayılıyor, cihaz tablosundan değil: böylece kaydolup hemen
 * silmek sınırı sıfırlamaz.
 *
 * Gizli anahtar düz metin saklanmaz; yalnızca özeti tutulur.
 */
export async function registerDevice(request: Request, env: Env): Promise<Response> {
  const ipHash = await hashClientIP(request, env);
  const deviceId = crypto.randomUUID();
  const secret = crypto.randomUUID().replace(/-/g, "");
  const secretHash = await sha256(secret);
  const now = Date.now();
  const registrationWindowStart = now - REGISTRATION_WINDOW_MS;

  // Sayaç cihaz tablosundan değil ayrı bir günlükten okunuyor: cihaz
  // tablosundan sayılsa kaydolup hemen silmek sınırı sıfırlar.
  //
  // Sınır denetimi, cihaz satırı ve günlük girdisi TEK batch'te (tek işlem).
  // Eskiden sayım ayrı bir SELECT'ti ve iki INSERT ayrı çağrılardı:
  // eşzamanlı istekler aynı sayımı görüp tavanı aşabiliyor, günlük yazımı
  // patlarsa cihaz günlüğe hiç düşmeden kalıyordu. Artık cihaz satırı
  // yalnızca sayım tavanın altındaysa ekleniyor, günlük girdisi yalnızca
  // cihaz eklendiyse yazılıyor ve biri düşerse hepsi geri alınıyor.
  const [inserted] = await env.DB.batch([
    // IP özeti cihaz satırına yazılmıyor: hiçbir sorgu okumuyordu, sınır
    // yalnızca registration_log'dan sayılıyor ve o günlük bir saatte budanıyor.
    env.DB.prepare(
      `INSERT INTO device (id, secret_hash, created_at, last_seen_at)
       SELECT ?, ?, ?, ?
       WHERE (SELECT COUNT(*) FROM registration_log WHERE ip_hash = ? AND created_at > ?) < ?`,
    ).bind(deviceId, secretHash, now, now, ipHash, registrationWindowStart, REGISTRATIONS_PER_IP_PER_HOUR),
    env.DB.prepare(
      `INSERT INTO registration_log (ip_hash, created_at)
       SELECT ?, ? WHERE EXISTS (SELECT 1 FROM device WHERE id = ?)`,
    ).bind(ipHash, now, deviceId),
    // Günlük kendini buduyor: sınır bir saatlik, daha eskisi yer kaplamasın.
    env.DB.prepare("DELETE FROM registration_log WHERE created_at < ?").bind(registrationWindowStart),
  ]);

  if ((inserted?.meta?.changes ?? 0) === 0) {
    return error("çok fazla kayıt denemesi, bir saat sonra tekrar deneyin", 429);
  }
  return json({ deviceId, secret });
}

/**
 * Kullanıcının gördüğü veriyi siler.
 *
 * Girişliyse hesabın tüm geçmişi (gördüğü buysa), değilse yalnızca bu cihazın
 * anonim verisi. Cihaz kaydı her hâlükârda siliniyor.
 */
export async function deleteDevice({ env, deviceId, accountKey }: RequestContext): Promise<Response> {
  // Silinen satır sayısı dönüyor ki istemci gerçek etkiyi görsün.
  //
  // Hesap kipinde (#60) eskiden hesabın bütün satırları siliniyor ama bu
  // cihazın kendi ANONİM satırları kalıyordu; cihaz satırı da silindiği için
  // o satırların artık hiçbir sahibi yoktu, ne okunabiliyor ne silinebiliyordu.
  // Artık hesap satırlarıyla birlikte bu cihazın anonim satırları da gidiyor.
  //
  // Hesaba bağlı DİĞER cihazların kayıtları bilerek silinmiyor: istemci 401
  // alınca kaydını atıp yeniden kaydoluyor ve yükleme işaretini sıfırlıyor,
  // yani o Mac'ler yerel arşivlerinin TAMAMINI yeniden yükleyip az önce
  // silinen geçmişi geri getirirdi. Kayıtları kalınca yalnızca yeni örnekleri
  // gönderiyorlar.
  const [samplesResult] = await env.DB.batch([
    accountKey
      ? env.DB.prepare(
          "DELETE FROM sample WHERE account_key = ? OR (device_id = ? AND account_key IS NULL)",
        ).bind(accountKey, deviceId)
      : env.DB.prepare("DELETE FROM sample WHERE device_id = ? AND account_key IS NULL").bind(deviceId),
    env.DB.prepare("DELETE FROM device WHERE id = ?").bind(deviceId),
  ]);
  const removed = samplesResult?.meta?.changes ?? 0;
  return json({ deleted: true, removed });
}
