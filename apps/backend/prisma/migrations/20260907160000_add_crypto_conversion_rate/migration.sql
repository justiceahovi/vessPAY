-- Records the rate a crypto deposit was credited at.
--
-- The credit happens at a quoted rate; treasury converts the token separately,
-- at whatever it gets then. Storing the quoted rate is what makes that spread
-- measurable instead of silently absorbed.

ALTER TABLE "funding_transactions"
    ADD COLUMN "conversion_rate" DECIMAL(24,10),
    ADD COLUMN "conversion_via" TEXT;
