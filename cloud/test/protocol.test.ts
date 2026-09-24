/**
 * Worker'ın tel sözleşmesi: Sources/LimitCore/CloudSync.swift'in dayandığı
 * uçlar, durum kodları ve JSON alan adları.
 *
 * Beklenen değerler KARAKTERİZASYON: bugünkü Worker'ın gerçekte ne döndürdüğü.
 * Bir iddia kırılırsa önce Worker'ın davranışı değişti mi diye bakılır;
 * istemci bu alanları adıyla okuyor.
 *
 * Veritabanı D1 değil, bellek içi SQLite (bkz. d1-shim.ts).
 *
 * Yalıtım: her senaryo kendi cihazını kaydediyor ve her kayıt ayrı bir
 * `cf-connecting-ip` ile geliyor. Cihaz başına dakikada 30 istek ve IP başına
 * saatte 20 kayıt sınırı ortak bir kovada birikirse, bir senaryo başka bir
 * senaryonun isteklerinden 429 alır.
 */
import assert from "node:assert/strict";
import { test } from "node:test";
import worker from "../src/index.ts";
import { makeD1 } from "./d1-shim.ts";

const env = { DB: makeD1(), IP_SALT: "test" };

// 64 onaltılık karakter: Worker'ın kabul ettiği tek hesap anahtarı biçimi.
const KEY_A = "a".repeat(64);
const KEY_B = "b".repeat(64);

// 2023-11-14; 2100 tavanının çok altında, sıfırın üstünde.
const T0 = 1_700_000_000_000;

type Reply = { status: number; json: any };

async function call(
  method: string,
  path: string,
  options: { token?: string; accountKey?: string; body?: unknown; headers?: Record<string, string> } = {},
): Promise<Reply> {
  const headers = new Headers(options.headers);
  if (options.token !== undefined) headers.set("authorization", `Bearer ${options.token}`);
  if (options.accountKey !== undefined) headers.set("x-account-key", options.accountKey);
  let body: string | undefined;
  if (options.body !== undefined) {
    body = typeof options.body === "string" ? options.body : JSON.stringify(options.body);
    headers.set("content-type", "application/json");
  }
  const response = await worker.fetch(
    new Request(`https://w.test${path}`, { method, headers, body }),
    env as never,
  );
  const text = await response.text();
  return { status: response.status, json: text ? JSON.parse(text) : null };
}

let lastOctet = 0;

/** Her çağrı yeni bir IP'den yeni bir cihaz: `<deviceId>.<secret>`. */
async function register(): Promise<string> {
  lastOctet += 1;
  const reply = await call("POST", "/v1/devices", {
    headers: { "cf-connecting-ip": `198.51.100.${lastOctet}` },
  });
  assert.equal(reply.status, 200);
  return `${reply.json.deviceId}.${reply.json.secret}`;
}

/** CloudSync.upload'un gönderdiği biçimde üç geçerli satır. */
function threeRows() {
  return [
    { t: T0, fiveHour: 10, sevenDay: 20, extra: null },
    { t: T0 + 60_000, fiveHour: 11, sevenDay: 21, extra: 5 },
    { t: T0 + 120_000, fiveHour: 12, sevenDay: 22, extra: null },
  ];
}

async function seed(token: string): Promise<void> {
  const reply = await call("POST", "/v1/samples", {
    token,
    body: { plan: "pro", samples: threeRows() },
  });
  assert.equal(reply.status, 200);
}

test("GET /v1/health → 200", async () => {
  const reply = await call("GET", "/v1/health");
  assert.equal(reply.status, 200);
  assert.deepEqual(reply.json, { ok: true });
});

test("POST /v1/devices → metin deviceId ve secret", async () => {
  const reply = await call("POST", "/v1/devices", {
    headers: { "cf-connecting-ip": "203.0.113.1" },
  });
  assert.equal(reply.status, 200);
  assert.deepEqual(Object.keys(reply.json).sort(), ["deviceId", "secret"]);
  assert.equal(typeof reply.json.deviceId, "string");
  assert.equal(typeof reply.json.secret, "string");
  assert.ok(reply.json.deviceId.length > 0);
  assert.ok(reply.json.secret.length > 0);
});

test("POST /v1/samples → inserted, yeniden gönderim, rejected", async () => {
  const token = await register();

  const first = await call("POST", "/v1/samples", {
    token,
    body: { plan: "pro", samples: threeRows() },
  });
  assert.equal(first.status, 200);
  assert.deepEqual(first.json, { received: 3, rejected: 0, inserted: 3 });

  // Aynı satırlar yeniden: satır çoğalmıyor (özet hâlâ 3), ama `inserted`
  // yine 3. Deyim `ON CONFLICT ... DO UPDATE` ve SQLite güncellenen satırı
  // da `changes` içinde sayıyor; D1 aynı SQLite sayacını döndürüyor.
  const again = await call("POST", "/v1/samples", {
    token,
    body: { plan: "pro", samples: threeRows() },
  });
  assert.equal(again.status, 200);
  assert.deepEqual(again.json, { received: 3, rejected: 0, inserted: 3 });
  const afterResend = await call("GET", "/v1/summary", { token });
  assert.equal(afterResend.json.count, 3);

  // t = 0 ve sayı olmayan yüzde reddediliyor, sayıları raporlanıyor.
  const bad = await call("POST", "/v1/samples", {
    token,
    body: {
      plan: "pro",
      samples: [
        { t: 0, fiveHour: 10, sevenDay: 20 },
        { t: T0 + 180_000, fiveHour: "x", sevenDay: 20 },
      ],
    },
  });
  assert.equal(bad.status, 200);
  assert.deepEqual(bad.json, { received: 0, rejected: 2, inserted: 0 });
});

test("GET /v1/summary → yalnızca count, oldest, newest", async () => {
  const token = await register();

  const empty = await call("GET", "/v1/summary", { token });
  assert.equal(empty.status, 200);
  assert.deepEqual(empty.json, { count: 0, oldest: null, newest: null });

  await seed(token);
  const full = await call("GET", "/v1/summary", { token });
  assert.equal(full.status, 200);
  assert.deepEqual(Object.keys(full.json).sort(), ["count", "newest", "oldest"]);
  assert.deepEqual(full.json, { count: 3, oldest: T0, newest: T0 + 120_000 });
});

test("GET /v1/samples → sayfalı: samples, hasMore, nextSince", async () => {
  const token = await register();
  await seed(token);

  const page1 = await call("GET", "/v1/samples?since=0&limit=2", { token });
  assert.equal(page1.status, 200);
  assert.deepEqual(Object.keys(page1.json).sort(), ["hasMore", "nextSince", "samples"]);
  for (const row of page1.json.samples) {
    assert.deepEqual(Object.keys(row).sort(), ["extra", "fiveHour", "sevenDay", "t"]);
  }
  assert.deepEqual(page1.json.samples, [
    { t: T0, fiveHour: 10, sevenDay: 20, extra: null },
    { t: T0 + 60_000, fiveHour: 11, sevenDay: 21, extra: 5 },
  ]);
  assert.equal(page1.json.hasMore, true);
  // Son satırın t'si + 1: istemci bir sonraki isteği buradan başlatıyor.
  assert.equal(page1.json.nextSince, T0 + 60_000 + 1);

  const page2 = await call("GET", `/v1/samples?since=${page1.json.nextSince}&limit=2`, { token });
  assert.equal(page2.status, 200);
  assert.deepEqual(page2.json, {
    samples: [{ t: T0 + 120_000, fiveHour: 12, sevenDay: 22, extra: null }],
    hasMore: false,
    nextSince: null,
  });
});

test("POST /v1/claim → sayı olarak claimed", async () => {
  const token = await register();
  await seed(token);

  const reply = await call("POST", "/v1/claim", { token, accountKey: KEY_A, body: {} });
  assert.equal(reply.status, 200);
  assert.deepEqual(reply.json, { claimed: 3 });
});

test("DELETE /v1/device → sayı olarak removed; ardından aynı kimlik 401", async () => {
  const token = await register();
  await seed(token);

  const reply = await call("DELETE", "/v1/device", { token });
  assert.equal(reply.status, 200);
  assert.deepEqual(reply.json, { deleted: true, removed: 3 });

  // İstemci 401'i "cihaz kaydı yok, yeniden kaydol" diye okuyor.
  const after = await call("GET", "/v1/summary", { token });
  assert.equal(after.status, 401);
});

test("Kimlik: eksik ya da bozuk bearer 401, bilinmeyen yol 404", async () => {
  const token = await register();
  const deviceId = token.slice(0, token.indexOf("."));

  const missing = await call("GET", "/v1/summary");
  assert.equal(missing.status, 401);
  assert.equal(typeof missing.json.error, "string");

  const noSeparator = await call("GET", "/v1/summary", { token: "nokta-yok" });
  assert.equal(noSeparator.status, 401);

  const wrongSecret = await call("GET", "/v1/summary", { token: `${deviceId}.yanlis` });
  assert.equal(wrongSecret.status, 401);

  const unknownDevice = await call("GET", "/v1/summary", { token: "yok.yok" });
  assert.equal(unknownDevice.status, 401);

  const notBearer = await call("GET", "/v1/summary", {
    headers: { authorization: `Basic ${token}` },
  });
  assert.equal(notBearer.status, 401);

  const unknownPath = await call("GET", "/v1/yok", { token });
  assert.equal(unknownPath.status, 404);
  assert.equal(typeof unknownPath.json.error, "string");
});

test("512 KiB üstü gövde → 413", async () => {
  const token = await register();

  // Bildirilen uzunluk tek başına yetiyor: gövde okunmadan reddediliyor.
  const declared = await call("POST", "/v1/samples", {
    token,
    body: "{}",
    headers: { "content-length": String(512 * 1024 + 1) },
  });
  assert.equal(declared.status, 413);

  // Uzunluk bildirilmeden gelen büyük gövde okunurken sayılıp kesiliyor.
  const streamed = await call("POST", "/v1/samples", {
    token,
    body: "x".repeat(512 * 1024 + 1),
  });
  assert.equal(streamed.status, 413);
  assert.equal(typeof streamed.json.error, "string");
});

test("Bir dakikada 31. kimlikli istek → 429", async () => {
  // Kendi cihazı: sayaç yalnızca bu senaryonun istekleriyle doluyor.
  const token = await register();

  for (let i = 1; i <= 30; i += 1) {
    const reply = await call("GET", "/v1/summary", { token });
    assert.equal(reply.status, 200, `${i}. istek`);
  }
  const over = await call("GET", "/v1/summary", { token });
  assert.equal(over.status, 429);
  assert.equal(typeof over.json.error, "string");
});

// Davranış #49 ile BİLEREK değişti: eskiden B anahtarı sonsuza kadar 403
// alıyordu, kullanıcı aynı Mac'te hesap değiştiremiyordu. Artık cihaz
// yeniden bağlanıyor (hesap tavanları ve cihaz başına değişiklik sınırıyla).
test("A hesabına bağlı cihaz B anahtarıyla → yeniden bağlanıp 200, A'nın verisi görünmüyor", async () => {
  const token = await register();

  // İlk anahtar cihazı o hesaba bağlıyor (ilk kullanımda güven).
  const bind = await call("GET", "/v1/summary", { token, accountKey: KEY_A });
  assert.equal(bind.status, 200);
  await call("POST", "/v1/samples", { token, accountKey: KEY_A, body: { samples: threeRows() } });

  const other = await call("GET", "/v1/summary", { token, accountKey: KEY_B });
  assert.equal(other.status, 200);
  assert.equal(other.json.count, 0);

  // A'ya geri dönmek de bir yeniden bağlama; A'nın verisi yerinde.
  const back = await call("GET", "/v1/summary", { token, accountKey: KEY_A });
  assert.equal(back.status, 200);
  assert.equal(back.json.count, 3);
});
