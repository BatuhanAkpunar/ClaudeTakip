import test from "node:test";
import assert from "node:assert/strict";
import { call, makeEnv } from "./helpers.mjs";

async function count(env, table) {
  return (await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${table}`).first()).n;
}

test("#56: günlük yazımı düşerse cihaz satırı da geri alınıyor", async (t) => {
  t.mock.method(console, "error", () => {});
  const env = makeEnv();
  env.DB.hook = (sql) => {
    if (sql.includes("INSERT INTO registration_log")) throw new Error("D1_ERROR: yapay");
  };
  const r = await call(env, "POST", "/v1/devices");
  assert.equal(r.status, 500);
  assert.equal(await count(env, "device"), 0);
  assert.equal(await count(env, "registration_log"), 0);
});

test("#56: her başarılı kayıt tam bir günlük girdisi bırakıyor", async () => {
  const env = makeEnv();
  for (let i = 0; i < 3; i++) assert.equal((await call(env, "POST", "/v1/devices")).status, 200);
  assert.equal(await count(env, "device"), 3);
  assert.equal(await count(env, "registration_log"), 3);
});

test("#56: eşzamanlı kayıtlar IP tavanını aşamıyor", async () => {
  const env = makeEnv();
  env.DB.interleave = true;
  const results = await Promise.all(Array.from({ length: 30 }, () => call(env, "POST", "/v1/devices")));
  assert.equal(results.filter((r) => r.status === 200).length, 20);
  assert.equal(results.filter((r) => r.status === 429).length, 10);
  assert.equal(await count(env, "device"), 20);
  assert.equal(await count(env, "registration_log"), 20);
});
