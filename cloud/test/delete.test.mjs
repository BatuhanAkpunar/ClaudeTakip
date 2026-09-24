import test from "node:test";
import assert from "node:assert/strict";
import { call, makeEnv, register, sample, KEY_A } from "./helpers.mjs";

async function rows(env) {
  return (await env.DB.prepare("SELECT device_id, t, account_key FROM sample ORDER BY t").all()).results;
}

test("#60: hesap kipinde silme, bu cihazın anonim satırlarını yetim bırakmıyor", async () => {
  const env = makeEnv();
  const me = await register(env, "192.0.2.1");
  const other = await register(env, "192.0.2.2");
  // Benim anonim satırım (claim edilmemiş) ve hesap satırlarım.
  await call(env, "POST", "/v1/samples", { auth: me, body: { samples: [sample(1)] } });
  await call(env, "POST", "/v1/samples", { auth: me, key: KEY_A, body: { samples: [sample(2)] } });
  // Aynı hesaptaki diğer Mac'in hesap satırı ve anonim satırı.
  await call(env, "POST", "/v1/samples", { auth: other, key: KEY_A, body: { samples: [sample(3)] } });
  await call(env, "POST", "/v1/samples", { auth: other, body: { samples: [sample(4)] } });

  const r = await call(env, "DELETE", "/v1/device", { auth: me, key: KEY_A });
  assert.equal(r.status, 200);
  assert.deepEqual(r.data, { deleted: true, removed: 3 });

  // Yalnızca diğer cihazın kendi anonim satırı kaldı; hiçbir yetim satır yok.
  assert.deepEqual(await rows(env), [{ device_id: other.deviceId, t: 4, account_key: null }]);
  const orphans = (
    await env.DB.prepare("SELECT COUNT(*) AS n FROM sample WHERE device_id NOT IN (SELECT id FROM device)").first()
  ).n;
  assert.equal(orphans, 0);

  // Diğer Mac kayıtlı ve bağlı kalıyor: yeniden kaydolup tüm arşivi geri yüklemiyor.
  const again = await call(env, "GET", "/v1/summary", { auth: other, key: KEY_A });
  assert.equal(again.status, 200);
  assert.equal(again.data.count, 0);
  assert.equal((await call(env, "GET", "/v1/summary", { auth: me })).status, 401);
});

test("#60: anonim kipte silme eskisi gibi yalnızca bu cihazın anonim verisi", async () => {
  const env = makeEnv();
  const me = await register(env);
  await call(env, "POST", "/v1/samples", { auth: me, body: { samples: [sample(1), sample(2)] } });
  const r = await call(env, "DELETE", "/v1/device", { auth: me });
  assert.deepEqual(r.data, { deleted: true, removed: 2 });
  assert.deepEqual(await rows(env), []);
});
