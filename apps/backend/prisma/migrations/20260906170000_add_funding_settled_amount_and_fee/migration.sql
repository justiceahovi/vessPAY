-- AlterTable
ALTER TABLE "funding_transactions" ADD COLUMN     "settled_amount" DECIMAL(14,2);
ALTER TABLE "funding_transactions" ADD COLUMN     "fee" DECIMAL(14,2) NOT NULL DEFAULT 0.00;
