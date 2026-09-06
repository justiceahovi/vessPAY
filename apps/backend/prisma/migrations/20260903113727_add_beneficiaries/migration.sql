-- CreateTable
CREATE TABLE "beneficiaries" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "country" TEXT NOT NULL,
    "network" TEXT NOT NULL,
    "phone" TEXT NOT NULL,
    "wewire_beneficiary_id" TEXT,
    "wewire_account_id" TEXT,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "beneficiaries_pkey" PRIMARY KEY ("id")
);

-- AddForeignKey
ALTER TABLE "beneficiaries" ADD CONSTRAINT "beneficiaries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
