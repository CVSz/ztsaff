CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role VARCHAR(20) NOT NULL DEFAULT 'user',
  plan VARCHAR(50) DEFAULT 'free',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE scripts (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  product_name VARCHAR(255),
  category VARCHAR(100),
  content TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE product_feeds (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  source VARCHAR(100) NOT NULL DEFAULT 'tiktok_shop_affiliate',
  feed_name VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE products (
  id SERIAL PRIMARY KEY,
  feed_id INTEGER REFERENCES product_feeds(id),
  user_id INTEGER REFERENCES users(id),
  product_id VARCHAR(128) NOT NULL,
  title VARCHAR(255) NOT NULL,
  category VARCHAR(100),
  price NUMERIC(12,2),
  currency VARCHAR(12) DEFAULT 'THB',
  product_url TEXT,
  image_url TEXT,
  raw_payload JSONB,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE video_jobs (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  product_ref INTEGER REFERENCES products(id),
  status VARCHAR(30) DEFAULT 'generated',
  title VARCHAR(255),
  hook TEXT,
  script TEXT,
  storyboard JSONB,
  hashtags TEXT,
  tts_voice VARCHAR(50) DEFAULT 'th_female_1',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE showcase_uploads (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  video_job_id INTEGER REFERENCES video_jobs(id),
  status VARCHAR(30) DEFAULT 'queued',
  showcase_video_id VARCHAR(100),
  publish_url TEXT,
  payload JSONB,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE rental_plans (
  id SERIAL PRIMARY KEY,
  code VARCHAR(50) UNIQUE NOT NULL,
  name VARCHAR(100) NOT NULL,
  monthly_price NUMERIC(10,2) NOT NULL,
  max_video_jobs INTEGER NOT NULL,
  perks TEXT,
  active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_rentals (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  plan_id INTEGER REFERENCES rental_plans(id),
  months INTEGER NOT NULL DEFAULT 1,
  total_price NUMERIC(12,2) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  starts_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  ends_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO rental_plans (code, name, monthly_price, max_video_jobs, perks)
VALUES
  ('starter', 'Starter', 299, 30, 'Basic AI script + video package generation'),
  ('growth', 'Growth', 999, 150, 'Priority generation + richer storyboard'),
  ('pro', 'Pro', 2499, 1000, 'Team-ready scaling + advanced automation');


CREATE TABLE wallet_accounts (
  id SERIAL PRIMARY KEY,
  user_id INTEGER UNIQUE REFERENCES users(id),
  balance NUMERIC(14,2) NOT NULL DEFAULT 0,
  currency VARCHAR(12) NOT NULL DEFAULT 'THB',
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE wallet_transactions (
  id SERIAL PRIMARY KEY,
  wallet_id INTEGER REFERENCES wallet_accounts(id),
  user_id INTEGER REFERENCES users(id),
  tx_type VARCHAR(30) NOT NULL,
  amount NUMERIC(14,2) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'completed',
  note VARCHAR(255),
  metadata JSONB,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_wallet_transactions_wallet_id ON wallet_transactions(wallet_id, created_at DESC);
CREATE INDEX idx_wallet_transactions_user_id ON wallet_transactions(user_id, created_at DESC);
