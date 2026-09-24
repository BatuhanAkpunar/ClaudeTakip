import test from "node:test";
import assert from "node:assert/strict";
import { describeSchema, migratedDb, schemaDb } from "./d1.mjs";

test("schema.sql, taban + tüm göçlerin sırayla uygulanmış hâliyle aynı", () => {
  assert.deepEqual(describeSchema(schemaDb()), describeSchema(migratedDb()));
});
