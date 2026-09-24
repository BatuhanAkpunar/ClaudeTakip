import test from "node:test";
import assert from "node:assert/strict";
import { call, makeEnv, register, sample, KEY_A, KEY_B, KEY_C } from "./helpers.mjs";

const DAY = 86_400_000;

async function boundKey(env, dev) {
  return (await env.DB.prepare("SELECT account_key FROM device WHERE id = ?").bind(dev.deviceId).first()).account_key;
}

test("#49: hesap değiştiren cihaz yeniden bağlanıyor, eski hesabın verisine dokunamıyor", async (t) => {
  t.mock.method(console, "warn", () => {});
  const env = makeEnv();
  const dev = await register(env);
  await call(env, "POST", "/v1/samples", { auth: dev, key: KEY_A, body: { samples: [sample(1)] } });
  assert.equal(await boundKey(env, dev), KEY_A);

  const r = await call(env, "POST", "/v1/samples", { auth: dev, key: KEY_B, body: { samples: [sample(2)] } });
  assert.equal(r.status, 200);
  assert.equal(await boundKey(env, dev), KEY_B);

  // Artık A kapsamında değil: A'yı istemek yeniden bağlama sayılıyor, ama
  // B'deyken A'nın verisi B'ye görünmüyor.
  const sum = await call(env, "GET", "/v1/summary", { auth: dev, key: KEY_B });
  assert.deepEqual(sum.data, { count: 1, oldest: 2, newest: 2 });

  const log = (await env.DB.prepare("SELECT account_key FROM account_bind_log ORDER BY rowid").all()).results;
  assert.deepEqual(log.map((r) => r.account_key), [KEY_A, KEY_B]);
});

test("#49: cihaz başına 30 günde en fazla 10 bağ, sonra 429; pencere geçince açılıyor", async (t) => {
  t.mock.method(console, "warn", () => {});
  const env = makeEnv();
  const dev = await register(env);
  const keys = [KEY_A, KEY_B];
  const statuses = [];
  for (let i = 0; i < 11; i++) {
    const r = await call(env, "GET", "/v1/summary", { auth: dev, key: keys[i % 2] });
    statuses.push(r.status);
    if (r.status === 429) assert.deepEqual(r.data, { error: "hesap değişiklik sınırı aşıldı" });
    // Hesap başına günlük tavan bu testin konusu değil: hesap günlüğünü değil
    // yalnızca 24 saati aşacak kadar eskit, cihaz penceresi (30 gün) içinde kalsın.
    await env.DB.prepare("UPDATE account_bind_log SET created_at = created_at - ?").bind(DAY + 1).run();
    await env.DB.prepare("UPDATE device SET rate_window_start = NULL").run();
  }
  assert.deepEqual(statuses, [...Array(10).fill(200), 429]);

  await env.DB.prepare("UPDATE account_bind_log SET created_at = created_at - ?").bind(30 * DAY).run();
  assert.equal((await call(env, "GET", "/v1/summary", { auth: dev, key: KEY_C })).status, 200);
});

test("#49: yeniden bağlama da hesap tavanlarına tabi", async (t) => {
  t.mock.method(console, "warn", () => {});
  const env = makeEnv();
  // B hesabına bugün 5 cihaz bağlandı.
  for (let i = 0; i < 5; i++) {
    const d = await register(env, `192.0.2.${i + 1}`);
    assert.equal((await call(env, "GET", "/v1/summary", { auth: d, key: KEY_B })).status, 200);
  }
  const dev = await register(env, "192.0.2.99");
  assert.equal((await call(env, "GET", "/v1/summary", { auth: dev, key: KEY_A })).status, 200);
  const r = await call(env, "GET", "/v1/summary", { auth: dev, key: KEY_B });
  assert.equal(r.status, 429);
  assert.equal(await boundKey(env, dev), KEY_A);
});

test("#49: eşzamanlı yeniden bağlamada yarışı kaybeden 403 alıyor", async (t) => {
  t.mock.method(console, "warn", () => {});
  const env = makeEnv();
  const dev = await register(env);
  await call(env, "GET", "/v1/summary", { auth: dev, key: KEY_A });
  env.DB.interleave = true;
  const [b, c] = await Promise.all([
    call(env, "GET", "/v1/summary", { auth: dev, key: KEY_B }),
    call(env, "GET", "/v1/summary", { auth: dev, key: KEY_C }),
  ]);
  const bound = await boundKey(env, dev);
  assert.ok(bound === KEY_B || bound === KEY_C);
  assert.deepEqual([b.status, c.status].sort(), [200, 403]);
});
