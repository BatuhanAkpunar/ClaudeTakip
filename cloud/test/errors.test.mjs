import test from "node:test";
import assert from "node:assert/strict";
import { call, makeEnv, register } from "./helpers.mjs";

test("#59: yakalanmayan D1 hatası JSON hata biçiminde 500 dönüyor", async (t) => {
  t.mock.method(console, "error", () => {});
  const env = makeEnv();
  const dev = await register(env);
  env.DB.hook = (sql) => {
    if (sql.includes("FROM sample")) throw new Error("D1_ERROR: yapay kesinti");
  };
  const r = await call(env, "GET", "/v1/summary", { auth: dev });
  assert.equal(r.status, 500);
  assert.match(r.headers.get("content-type"), /application\/json/);
  assert.deepEqual(r.data, { error: "sunucu hatası" });
  // İç ayrıntı istemciye sızmıyor.
  assert.ok(!r.text.includes("yapay"));
});

test("#59: kayıt sırasında D1 hatası da JSON", async (t) => {
  t.mock.method(console, "error", () => {});
  const env = makeEnv();
  env.DB.hook = () => {
    throw new Error("D1_ERROR");
  };
  const r = await call(env, "POST", "/v1/devices");
  assert.equal(r.status, 500);
  assert.deepEqual(r.data, { error: "sunucu hatası" });
});
