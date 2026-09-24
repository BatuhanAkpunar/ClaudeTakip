import test from "node:test";
import assert from "node:assert/strict";
import { call, makeEnv, register, sample, KEY_A } from "./helpers.mjs";

test("uçtan uca: kayıt, yükleme, özet, indirme, claim, silme", async () => {
  const env = makeEnv();
  const dev = await register(env);
  assert.match(dev.deviceId, /^[0-9a-f-]{36}$/);

  let r = await call(env, "POST", "/v1/samples", { auth: dev, body: { samples: [sample(1000), sample(2000)], plan: "pro" } });
  assert.equal(r.status, 200);
  assert.deepEqual(r.data, { received: 2, rejected: 0, inserted: 2 });

  r = await call(env, "GET", "/v1/summary", { auth: dev });
  assert.deepEqual(r.data, { count: 2, oldest: 1000, newest: 2000 });

  r = await call(env, "POST", "/v1/claim", { auth: dev, key: KEY_A, body: {} });
  assert.deepEqual(r.data, { claimed: 2 });

  r = await call(env, "GET", "/v1/samples?since=0", { auth: dev, key: KEY_A });
  assert.equal(r.data.samples.length, 2);
  assert.equal(r.data.hasMore, false);

  r = await call(env, "DELETE", "/v1/device", { auth: dev, key: KEY_A });
  assert.equal(r.status, 200);
  assert.equal(r.data.deleted, true);
  assert.equal(r.data.removed, 2);

  r = await call(env, "GET", "/v1/summary", { auth: dev });
  assert.equal(r.status, 401);
});

test("kimliksiz istek 401, bilinmeyen yol 404", async () => {
  const env = makeEnv();
  assert.equal((await call(env, "GET", "/v1/summary")).status, 401);
  const dev = await register(env);
  const r = await call(env, "GET", "/v1/nope", { auth: dev });
  assert.equal(r.status, 404);
  assert.deepEqual(r.data, { error: "bulunamadı" });
});
