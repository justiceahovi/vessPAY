-- CreateTable
CREATE TABLE "transactions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "type" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "source_currency" TEXT NOT NULL,
    "source_amount" DECIMAL(14,2) NOT NULL,
    "destination_currency" TEXT NOT NULL,
    "destination_amount" DECIMAL(14,2) NOT NULL,
    "fee" DECIMAL(14,2) NOT NULL,
    "exchange_rate" DECIMAL(14,6) NOT NULL,
    "recipient_name" TEXT,
    "recipient_phone" TEXT,
    "network" TEXT,
    "country" TEXT,
    "wewire_transaction_id" TEXT,
    "idempotency_key" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "transactions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "transactions_idempotency_key_key" ON "transactions"("idempotency_key");

-- AddForeignKey
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
