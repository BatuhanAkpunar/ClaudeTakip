import test from "node:test";
import assert from "node:assert/strict";
import { call, makeEnv, register, sample, KEY_A, KEY_B } from "./helpers.mjs";

test("#50: eşzamanlı ilk bağlamada yalnızca kazanan hesap kapsam alıyor", async () => {
  const env = makeEnv();
  const dev = await register(env);
  env.DB.interleave = true;
  const [a, b] = await Promise.all([
    call(env, "POST", "/v1/samples", { auth: dev, key: KEY_A, body: { samples: [sample(100)] } }),
    call(env, "POST", "/v1/samples", { auth: dev, key: KEY_B, body: { samples: [sample(200)] } }),
  ]);
  const bound = (await env.DB.prepare("SELECT account_key FROM device WHERE id = ?").bind(dev.deviceId).first())
    .account_key;
  const winner = bound === KEY_A ? a : b;
  const loser = bound === KEY_A ? b : a;
  assert.equal(winner.status, 200);
  assert.equal(loser.status, 403);
  assert.deepEqual(loser.data, { error: "bu cihaz o hesaba bağlı değil" });
  // Kaybeden hesabın anahtarıyla hiçbir satır yazılmadı.
  const keys = (await env.DB.prepare("SELECT DISTINCT account_key FROM sample").all()).results.map((r) => r.account_key);
  assert.deepEqual(keys, [bound]);
});

test("#50: aynı anahtarla eşzamanlı bağlama iki isteği de geçiriyor", async () => {
  const env = makeEnv();
  const dev = await register(env);
  env.DB.interleave = true;
  const rs = await Promise.all([
    call(env, "GET", "/v1/summary", { auth: dev, key: KEY_A }),
    call(env, "GET", "/v1/summary", { auth: dev, key: KEY_A }),
  ]);
  assert.deepEqual(rs.map((r) => r.status), [200, 200]);
});
