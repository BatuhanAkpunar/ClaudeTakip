CREATE TABLE IF NOT EXISTS registration_log (
    ip_hash    TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS registration_log_ip ON registration_log(ip_hash, created_at);
