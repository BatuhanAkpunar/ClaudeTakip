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

import { accountKeyOf, authenticate, consumeDeviceRequest, resolveScope } from "./auth.ts";
import { deleteDevice, registerDevice } from "./devices.ts";
import type { Env, RequestContext } from "./env.ts";
import { error, json } from "./http.ts";
import { claimSamples, downloadSamples, sampleSummary, uploadSamples } from "./samples.ts";

/**
 * Kimlik doğrulaması isteyen uçların TAM listesi. Buradaki her uç kimlik,
 * kapsam ve hız sınırı kapısından geçtikten sonra çağrılır; kapıdan önce
 * bir uç eklemek için fetch'i açıkça düzenlemek gerekir.
 */
const AUTHENTICATED_ROUTES = new Map<string, (ctx: RequestContext) => Promise<Response>>([
  ["POST /v1/samples", uploadSamples],
  ["GET /v1/samples", downloadSamples],
  ["GET /v1/summary", sampleSummary],
  ["POST /v1/claim", claimSamples],
  ["DELETE /v1/device", deleteDevice],
]);

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Yakalanmayan bir D1 hatası (kota, geçici kesinti, kısıt ihlali)
    // Cloudflare'in HTML 500 sayfasına düşüyordu. Yanıt her zaman aynı JSON
    // biçiminde olmalı; ayrıntı yalnızca günlüğe gidiyor, istemciye değil.
    try {
      return await handle(request, env);
    } catch (err) {
      console.error("yakalanmayan hata", err);
      return error("sunucu hatası", 500);
    }
  },
} satisfies ExportedHandler<Env>;

async function handle(request: Request, env: Env): Promise<Response> {
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
    const scope = await resolveScope(request, env, device, accountKeyOf(request));
    if (!scope.ok) return scope.response;
    const accountKey = scope.accountKey;

    // Cihaz başına hız sınırı. Olmazsa tek bir cihaz kimliğiyle sınırsız
    // istek atıp D1'in günlük okuma kotasını tüketmek ve servisi herkese
    // kapatmak mümkün olur. İstemci
    // dakikada bir istek atıyor; bu tavan onun çok üstünde, kötüye kullanımın
    // çok altında.
    if (!(await consumeDeviceRequest(env, deviceId))) {
      return error("çok fazla istek", 429);
    }

    const ctx: RequestContext = { request, url, env, deviceId, accountKey };
    const route = AUTHENTICATED_ROUTES.get(`${request.method} ${path}`);
    return route ? route(ctx) : error("bulunamadı", 404);
}
