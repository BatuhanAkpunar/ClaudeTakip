import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { call, makeEnv } from "./helpers.mjs";

const sha = (s) => createHash("sha256").update(s).digest("hex");
const IP = "198.51.100.23";

async function loggedHash(env) {
  return (await env.DB.prepare("SELECT ip_hash FROM registration_log").first()).ip_hash;
}

test("#53: IP_SALT yoksa açık sabit tuz kullanılmıyor", async () => {
  const env = makeEnv({ IP_SALT: undefined });
  assert.equal((await call(env, "POST", "/v1/devices", { ip: IP })).status, 200);
  const hash = await loggedHash(env);
  assert.notEqual(hash, sha(`claude-limit/ip/v1:${IP}`));

  const salt = (await env.DB.prepare("SELECT value FROM server_secret WHERE name = 'ip_salt'").first()).value;
  assert.match(salt, /^[0-9a-f]{64}$/);
  assert.equal(hash, sha(`${salt}:${IP}`));

  // Tuz kalıcı: aynı IP aynı özeti üretiyor, sınır çalışıyor.
  await call(env, "POST", "/v1/devices", { ip: IP });
  const hashes = (await env.DB.prepare("SELECT DISTINCT ip_hash FROM registration_log").all()).results;
  assert.equal(hashes.length, 1);

  // Başka bir veritabanı başka bir tuz alıyor.
  const other = makeEnv({ IP_SALT: undefined });
  await call(other, "POST", "/v1/devices", { ip: IP });
  assert.notEqual(await loggedHash(other), hash);
});

test("#53: IP_SALT tanımlıysa o kullanılıyor, tablo boş kalıyor", async () => {
  const env = makeEnv({ IP_SALT: "gizli" });
  await call(env, "POST", "/v1/devices", { ip: IP });
  assert.equal(await loggedHash(env), sha(`gizli:${IP}`));
  const n = (await env.DB.prepare("SELECT COUNT(*) AS n FROM server_secret").first()).n;
  assert.equal(n, 0);
});
