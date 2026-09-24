const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: JSON_HEADERS });
}

export function error(message: string, status: number): Response {
  return json({ error: message }, status);
}

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

type JsonBody = { ok: true; body: Record<string, unknown> } | { ok: false; response: Response };

/**
 * İstek gövdesini sınırlı okuyup bir JSON nesnesine çevirir.
 *
 * Sıra: bildirilen content-length ön elemesi, sınırlı okuma, ayrıştırma,
 * nesne denetimi. Her adımın hata kodu ve mesajı sabit.
 */
export async function readJsonObject(request: Request, limit: number): Promise<JsonBody> {
  // Devasa bir gövdeyi ayrıştırmaya hiç başlamamak, ayrıştırdıktan sonra
  // reddetmekten ucuz: Worker'ın CPU bütçesi 10 ms.
  // content-length yalnızca UCUZ bir ön eleme: chunked gönderimde başlık
  // hiç gelmez ve sınır atlatılabilir. Gerçek sınır gövde okunurken
  // uygulanıyor (readBoundedText).
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > limit) {
    return { ok: false, response: error("gövde çok büyük", 413) };
  }
  // Gövde SINIRLI okunuyor: `request.json()` boyuta bakmadan tamamını belleğe
  // alır, dolayısıyla chunked bir istek content-length denetimini atlayıp
  // Worker'ın bellek ve CPU bütçesini tüketebilir.
  const text = await readBoundedText(request, limit);
  if (text === null) return { ok: false, response: error("gövde çok büyük", 413) };
  let payload: unknown;
  try {
    payload = JSON.parse(text);
  } catch {
    return { ok: false, response: error("gövde okunamadı", 400) };
  }
  // Dizi de `typeof === "object"`: `[]` bu denetimi geçip `samples` alanı
  // yokmuş gibi boş bir yükleme olarak 200 alıyordu.
  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
    return { ok: false, response: error("gövde bir nesne olmalı", 400) };
  }
  return { ok: true, body: payload as Record<string, unknown> };
}
