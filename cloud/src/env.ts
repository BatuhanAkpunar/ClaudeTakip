export interface Env {
  /** Hız sınırı özetinin tuzu (`wrangler secret put IP_SALT`). Yoksa veritabanında üretilen rastgele tuz (server_secret). */
  IP_SALT?: string;
  DB: D1Database;
}

/** Kimliği doğrulanmış bir isteğin işleyicilere geçen bağlamı. */
export interface RequestContext {
  request: Request;
  url: URL;
  env: Env;
  deviceId: string;
  accountKey: string | null;
}
