-- Waitlist for tryglyf.com. Safe to run more than once.
-- Apply:  psql "$DATABASE_URL" -f db/waitlist.sql

CREATE TABLE IF NOT EXISTS waitlist (
  id          bigserial   PRIMARY KEY,
  email       text        NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  source      text,        -- which form: hero / footer
  country     text,        -- from Vercel's IP country header, when present
  referrer    text
);

-- One signup per address, regardless of letter case.
CREATE UNIQUE INDEX IF NOT EXISTS waitlist_email_unique ON waitlist (lower(email));

-- The same basic shape check as the site, enforced by the database too, so
-- nothing malformed gets in even if someone calls the API directly.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'waitlist_email_format') THEN
    ALTER TABLE waitlist ADD CONSTRAINT waitlist_email_format CHECK (
      char_length(email) <= 254
      AND email ~* '^[a-z0-9._%+-]{1,64}@[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}$'
      AND email !~ '\.\.'
    );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS waitlist_created_at ON waitlist (created_at DESC);
