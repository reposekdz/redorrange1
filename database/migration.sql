-- RedOrrange Migration - Ad & Escrow Enhancements
-- Apply these to your existing database

-- 1. Update payment_orders to support multiple target types
ALTER TABLE payment_orders 
  ADD COLUMN IF NOT EXISTS target_type ENUM('coin_package','marketplace_item','ad_topup') DEFAULT 'coin_package',
  ADD COLUMN IF NOT EXISTS target_id VARCHAR(36);

-- 2. Update likes to support ads
ALTER TABLE likes 
  MODIFY COLUMN target_type ENUM('post','comment','reel','story','ad') NOT NULL;

-- 3. Update comments to support ads
ALTER TABLE comments 
  MODIFY COLUMN target_type ENUM('post','reel','story','ad') NOT NULL;

-- 4. Ensure escrow_orders has payment_ref and funded_at
ALTER TABLE escrow_orders
  ADD COLUMN IF NOT EXISTS payment_ref VARCHAR(200) AFTER payment_method,
  ADD COLUMN IF NOT EXISTS funded_at TIMESTAMP NULL AFTER auto_release_at;

-- 5. Ensure ads table has interaction counters
ALTER TABLE ads
  ADD COLUMN IF NOT EXISTS reactions INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS comments_count INT DEFAULT 0;
