import test from "node:test";
import assert from "node:assert/strict";
import { call, makeEnv, register, sample, KEY_A, KEY_B } from "./helpers.mjs";

const DAY = 86_400_000;

async function ageBindLog(env, ms) {
  await env.DB.prepare("UPDATE account_bind_log SET created_at = created_at - ?").bind(ms).run();
}

test("#48: bir hesaba 24 saatte en fazla 5 yeni cihaz bağlanıyor, her bağ günlükte", async (t) => {
  const warn = t.mock.method(console, "warn", () => {});
  const env = makeEnv();
  const statuses = [];
  const devices = [];
  for (let i = 0; i < 6; i++) {
    const dev = await register(env, `198.51.100.${i + 1}`);
    devices.push(dev);
    const r = await call(env, "POST", "/v1/samples", { auth: dev, key: KEY_A, body: { samples: [sample(1000 + i)] } });
    statuses.push(r.status);
    if (r.status === 429) {
      assert.deepEqual(r.data, { error: "bu hesaba çok fazla cihaz bağlandı, daha sonra tekrar deneyin" });
    }
  }
  assert.deepEqual(statuses, [200, 200, 200, 200, 200, 429]);

  // Reddedilen cihaz bağlanmadı ve hesaba hiçbir şey yazamadı.
  const last = await env.DB.prepare("SELECT account_key FROM device WHERE id = ?").bind(devices[5].deviceId).first();
  assert.equal(last.account_key, null);
  const n = (await env.DB.prepare("SELECT COUNT(*) AS n FROM sample WHERE account_key = ?").bind(KEY_A).first()).n;
  assert.equal(n, 5);

  const log = (await env.DB.prepare("SELECT device_id, had_data, ip_hash FROM account_bind_log ORDER BY created_at").all()).results;
  assert.equal(log.length, 5);
  assert.deepEqual(log.map((r) => r.had_data), [0, 1, 1, 1, 1]);
  assert.ok(log.every((r) => /^[0-9a-f]{64}$/.test(r.ip_hash)));
  // Verisi olan hesaba her yeni bağ uyarı bıraktı (4) + tavan uyarısı (1).
  assert.equal(warn.mock.callCount(), 5);

  // Başka hesap etkilenmiyor.
  const other = await register(env, "198.51.100.200");
  assert.equal((await call(env, "GET", "/v1/summary", { auth: other, key: KEY_B })).status, 200);

  // 24 saat sonra yeniden bağlanabiliyor.
  await ageBindLog(env, DAY + 1);
  assert.equal((await call(env, "GET", "/v1/summary", { auth: devices[5], key: KEY_A })).status, 200);
});

test("#48: hesapta 30 günde görülmüş en fazla 8 cihaz", async (t) => {
  t.mock.method(console, "warn", () => {});
  const env = makeEnv();
  const devices = [];
  for (let i = 0; i < 9; i++) {
    const dev = await register(env, `203.0.113.${i + 1}`);
    devices.push(dev);
    // Günlük tavanı bu testin konusu değil: her bağdan sonra günlüğü eskit.
    const r = await call(env, "GET", "/v1/summary", { auth: dev, key: KEY_A });
    await ageBindLog(env, DAY + 1);
    assert.equal(r.status, i < 8 ? 200 : 429, `cihaz ${i}`);
  }
  // Bağlı cihazlar tavandan etkilenmiyor.
  assert.equal((await call(env, "GET", "/v1/summary", { auth: devices[0], key: KEY_A })).status, 200);

  // 30 günden uzun süredir görülmeyen cihaz sayımdan düşüyor.
  await env.DB.prepare("UPDATE device SET last_seen_at = last_seen_at - ? WHERE id = ?")
    .bind(31 * DAY, devices[1].deviceId)
    .run();
  assert.equal((await call(env, "GET", "/v1/summary", { auth: devices[8], key: KEY_A })).status, 200);
});

test("#48: anahtarsız (anonim) istekler tavanlardan etkilenmiyor", async () => {
  const env = makeEnv();
  const dev = await register(env);
  const r = await call(env, "POST", "/v1/samples", { auth: dev, body: { samples: [sample(1)] } });
  assert.equal(r.status, 200);
  const n = (await env.DB.prepare("SELECT COUNT(*) AS n FROM account_bind_log").first()).n;
  assert.equal(n, 0);
});
