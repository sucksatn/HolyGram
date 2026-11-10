-- HolyGram Pro subscriptions. expires_at: -1 = forever, otherwise unix seconds.
CREATE TABLE IF NOT EXISTS subscriptions (
  user_id     INTEGER PRIMARY KEY,
  expires_at  INTEGER NOT NULL,
  note        TEXT,
  granted_by  INTEGER,
  updated_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS subscriptions_expires ON subscriptions (expires_at);
