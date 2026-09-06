-- AlterTable
ALTER TABLE "users" ADD COLUMN     "onboarding_status" TEXT;
ALTER TABLE "users" ADD COLUMN     "enhanced_kyc_status" TEXT;
ALTER TABLE "users" ADD COLUMN     "kyc_status_updated_at" TIMESTAMPTZ;

-- CreateTable
CREATE TABLE "wallet_sweeps" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID,
    "sub_customer_id" TEXT NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "currency" TEXT NOT NULL,
    "direction" TEXT NOT NULL DEFAULT 'AUTO',
    "from_wallet_id" TEXT,
    "to_wallet_id" TEXT,
    "deposit_transaction_id" TEXT,
    "debit_transaction_id" TEXT,
    "credit_transaction_id" TEXT,
    "swept_at" TIMESTAMPTZ NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "wallet_sweeps_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "wallet_sweeps_deposit_transaction_id_key" ON "wallet_sweeps"("deposit_transaction_id");

-- CreateIndex
CREATE INDEX "wallet_sweeps_sub_customer_id_idx" ON "wallet_sweeps"("sub_customer_id");

-- AddForeignKey
ALTER TABLE "wallet_sweeps" ADD CONSTRAINT "wallet_sweeps_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
