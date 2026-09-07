-- Crypto deposit support.
--
-- A crypto deposit is address-first: it arrives unannounced, with no
-- pre-declared amount to match against, so the address is what attributes it
-- to a user and the on-chain tx hash is what makes it idempotent.

-- CreateTable
CREATE TABLE "crypto_deposit_addresses" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "sub_customer_id" TEXT NOT NULL,
    "wewire_address_id" TEXT NOT NULL,
    "chain" TEXT NOT NULL,
    "network" TEXT NOT NULL,
    "address" TEXT,
    "status" TEXT NOT NULL DEFAULT 'REQUESTED',
    "supported_assets" TEXT[],
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "crypto_deposit_addresses_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "crypto_deposit_addresses_user_id_chain_key"
    ON "crypto_deposit_addresses"("user_id", "chain");

-- CreateIndex
CREATE INDEX "crypto_deposit_addresses_address_idx"
    ON "crypto_deposit_addresses"("address");

-- AddForeignKey
ALTER TABLE "crypto_deposit_addresses"
    ADD CONSTRAINT "crypto_deposit_addresses_user_id_fkey"
    FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AlterTable: crypto columns on funding_transactions
ALTER TABLE "funding_transactions"
    ADD COLUMN "source" TEXT NOT NULL DEFAULT 'FIAT',
    ADD COLUMN "asset" TEXT,
    ADD COLUMN "chain" TEXT,
    ADD COLUMN "tx_hash" TEXT,
    ADD COLUMN "asset_amount" DECIMAL(38,18);

-- CreateIndex: the on-chain hash is the idempotency key for a crypto deposit
CREATE UNIQUE INDEX "funding_transactions_tx_hash_key"
    ON "funding_transactions"("tx_hash");
