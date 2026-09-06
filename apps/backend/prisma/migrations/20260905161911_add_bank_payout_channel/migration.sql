-- AlterTable
ALTER TABLE "beneficiaries" ADD COLUMN     "account_number" TEXT,
ADD COLUMN     "channel" TEXT NOT NULL DEFAULT 'MOBILE_MONEY',
ADD COLUMN     "institution_code" TEXT,
ALTER COLUMN "phone" DROP NOT NULL;

-- AlterTable
ALTER TABLE "transactions" ADD COLUMN     "channel" TEXT NOT NULL DEFAULT 'MOBILE_MONEY',
ADD COLUMN     "institution_code" TEXT,
ADD COLUMN     "recipient_account" TEXT;
