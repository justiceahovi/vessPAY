import { Router, Request, Response } from 'express';
import { prisma } from '../lib/db';
import { verifyWeWireSignature } from '../lib/webhook';
import { DEFAULT_WALLET_CURRENCY } from '../lib/currencies';
import { priceCryptoDeposit } from '../lib/crypto-conversion';

const router = Router();

export interface CryptoDepositEvent {
  /** Token received, e.g. 'USDC'. */
  asset: string;
  /** Chain it arrived on, e.g. 'BASE'. Absent on some payload shapes. */
  chain: string | null;
  /** On-chain transaction hash: the deposit's only stable identity. */
  txHash: string;
  /** Exact token amount, kept as a string so no precision is lost in transit. */
  amount: string;
  /** Destination address, used to attribute the deposit to a user. */
  address: string | null;
}

/**
 * Recognises a crypto deposit in a webhook payload, or returns null for a fiat
 * one.
 *
 * A crypto deposit is distinguished by carrying an on-chain hash. WeWire's
 * exact field naming for these events is NOT yet verified -- the sandbox has no
 * crypto deposit simulator and we have never received one -- so several
 * spellings are accepted rather than betting on a single one. Confirm against
 * a real delivery before trusting this in production.
 */
export function parseCryptoDeposit(data: any): CryptoDepositEvent | null {
  if (!data || typeof data !== 'object') return null;

  const pick = (...keys: string[]): string | null => {
    for (const key of keys) {
      const value = data[key];
      if (value !== undefined && value !== null && String(value).trim() !== '') {
        return String(value).trim();
      }
    }
    return null;
  };

  const txHash = pick('txHash', 'transactionHash', 'hash', 'onChainHash', 'chainTxHash');
  const asset = pick('asset', 'token', 'tokenSymbol');

  // Both are required: a hash without an asset is not something we can credit,
  // and an asset without a hash cannot be made idempotent.
  if (!txHash || !asset) return null;

  const amount = pick('amount', 'value', 'tokenAmount');
  if (!amount) return null;

  return {
    asset: asset.toUpperCase(),
    chain: pick('chain', 'network', 'blockchain')?.toUpperCase() ?? null,
    txHash,
    amount,
    address: pick('address', 'toAddress', 'destinationAddress', 'depositAddress'),
  };
}

/**
 * Records a crypto deposit that arrived without a matching intent.
 *
 * Attribution runs address first (the user was given that address, so it is
 * theirs) and falls back to the sub-customer id. A deposit we cannot attribute
 * is deliberately left unrecorded rather than credited to a guess.
 *
 * The row carries the exact token amount, but `amount` -- the fiat figure
 * credited -- stays 0 here. Pricing and crediting happen in
 * [creditCryptoDeposit], so a deposit that cannot be priced is still recorded
 * rather than lost.
 */
async function createCryptoFundingTransaction(
  tx: any,
  deposit: CryptoDepositEvent,
  subCustomerId?: string | null
): Promise<any | null> {
  let user: any = null;

  if (deposit.address) {
    const owned = await tx.cryptoDepositAddress.findFirst({
      where: { address: deposit.address },
      select: { userId: true },
    });
    if (owned) user = { id: owned.userId };
  }

  if (!user && subCustomerId) {
    user = await tx.user.findFirst({
      where: { wewireSubcustomerId: subCustomerId },
      select: { id: true },
    });
  }

  if (!user) {
    console.warn(
      `[Webhook] Crypto deposit ${deposit.txHash} could not be attributed to a user; not recorded.`
    );
    return null;
  }

  return tx.fundingTransaction.create({
    data: {
      userId: user.id,
      source: 'CRYPTO',
      asset: deposit.asset,
      chain: deposit.chain,
      txHash: deposit.txHash,
      assetAmount: deposit.amount,
      // The fiat value is not known here: converting is a separate decision,
      // and inventing a figure would credit money that has not been priced.
      amount: 0,
      currency: deposit.asset,
      status: 'PENDING',
    },
  });
}

/**
 * Prices a recorded crypto deposit and credits the user's wallet.
 *
 * The token amount is never credited as-is: 10 USDC is not 10 GBP. It is priced
 * into whichever currency the user actually holds, and the rate used is stored
 * on the row so the spread against treasury's eventual conversion is
 * measurable.
 *
 * A deposit that cannot be priced stays PENDING and uncredited. That is the
 * deliberate choice -- an unpriceable deposit is a question for a human, not a
 * reason to invent a number.
 */
async function creditCryptoDeposit(tx: any, fundingTx: any): Promise<void> {
  const user = await tx.user.findUnique({
    where: { id: fundingTx.userId },
    select: { primaryCurrency: true },
  });

  const walletCurrency = (user?.primaryCurrency || DEFAULT_WALLET_CURRENCY).toUpperCase();

  const pricing = await priceCryptoDeposit(
    fundingTx.asset,
    fundingTx.assetAmount?.toString() ?? '0',
    walletCurrency
  );

  if (!pricing) {
    console.warn(
      `[Webhook] Crypto deposit ${fundingTx.txHash} (${fundingTx.assetAmount} ${fundingTx.asset}) ` +
        `could not be priced into ${walletCurrency}; left PENDING and uncredited.`
    );
    return;
  }

  await tx.fundingTransaction.update({
    where: { id: fundingTx.id },
    data: {
      status: 'COMPLETED',
      currency: pricing.currency,
      amount: pricing.fiatAmount,
      settledAmount: pricing.fiatAmount,
      conversionRate: pricing.rate,
      conversionVia: pricing.via,
    },
  });

  const wallet = await tx.wallet.findFirst({
    where: { userId: fundingTx.userId, currency: pricing.currency },
  });

  if (!wallet) {
    await tx.wallet.create({
      data: {
        userId: fundingTx.userId,
        currency: pricing.currency,
        balance: pricing.fiatAmount,
      },
    });
  } else {
    await tx.wallet.update({
      where: { id: wallet.id },
      data: { balance: { increment: pricing.fiatAmount } },
    });
  }

  console.log(
    `[Webhook] Crypto deposit ${fundingTx.txHash} COMPLETED. ` +
      `${pricing.assetAmount} ${pricing.asset} -> ${pricing.fiatAmount} ${pricing.currency} ` +
      `@ ${pricing.rate} (${pricing.via}) for user ${fundingTx.userId}.`
  );
}

/**
 * What actually landed, and what the rails took, in wallet units.
 *
 * The sent amount and the settled amount differ: 250.00 GBP sent settles as
 * 249.45 with a 0.55 fee. WeWire reports `amount` gross with `fee` alongside,
 * and `balanceAfter` minus `balanceBefore` as the net. Prefer the observed net,
 * fall back to gross minus fee, and only fall back to the requested figure when
 * the payload says nothing about value.
 */
export function parseSettlement(
  data: any,
  requestedAmount: number
): { settled: number; fee: number } {
  const num = (v: unknown): number | null => {
    if (v === null || v === undefined || v === '') return null;
    const n = typeof v === 'number' ? v : Number(v);
    return Number.isFinite(n) ? n : null;
  };
  const round = (n: number) => Number(n.toFixed(2));

  const reportedFee = num(data?.fee) ?? 0;
  const gross = num(data?.amount);
  const before = num(data?.balanceBefore);
  const after = num(data?.balanceAfter);

  if (before !== null && after !== null) {
    const net = after - before;
    if (net > 0) {
      // Trust the observed movement, and derive the fee from it when the
      // payload reports a gross amount to compare against.
      const derivedFee = gross !== null ? Math.max(gross - net, 0) : reportedFee;
      return { settled: round(net), fee: round(derivedFee) };
    }
  }

  if (gross !== null) {
    const net = gross - reportedFee;
    if (net > 0) return { settled: round(net), fee: round(reportedFee) };
  }

  return { settled: requestedAmount, fee: round(reportedFee) };
}

/** Convenience wrapper for callers that only need the credited figure. */
export function parseSettledAmount(data: any, requestedAmount: number): number {
  return parseSettlement(data, requestedAmount).settled;
}


/**
 * POST /api/webhooks/wewire
 * WeWire webhook ingestion endpoint.
 * 
 * Blueprint Section 7:
 * POST /api/webhooks/wewire -- verify signature, store event, update ledger, idempotent
 * 
 * Blueprint Section 10:
 * "4. Webhook handler verifies the signature and is idempotent — reprocessing the same event_id must not double-credit a wallet or duplicate a transaction."
 */
router.post('/wewire', async (req: Request, res: Response): Promise<void> => {
  try {
    const secret = process.env.WEWIRE_WEBHOOK_SECRET;

    // 1. Verify signature
    if (secret) {
      const rawBody = (req as any).rawBody || JSON.stringify(req.body);
      const isValid = verifyWeWireSignature({
        secret,
        headers: req.headers,
        rawBody,
      });

      if (!isValid) {
        res.status(401).json({
          error: {
            code: 'INVALID_SIGNATURE',
            message: 'Webhook signature verification failed',
          },
        });
        return;
      }
    }

    const body = req.body || {};
    const headerId = req.headers['webhook-id'] || req.headers['Webhook-Id'];
    const eventId = (typeof headerId === 'string' && headerId.trim())
      ? headerId.trim()
      : body.eventId || body.id || body.data?.transactionId;

    if (!eventId || typeof eventId !== 'string') {
      res.status(400).json({
        error: {
          code: 'INVALID_EVENT',
          message: 'Could not determine event_id from webhook delivery',
        },
      });
      return;
    }

    const eventType = body.eventType || body.event || 'unknown';

    // 2. Idempotency Check: Skip if already marked processed
    const existingEvent = await prisma.webhookEvent.findUnique({
      where: { eventId },
    });

    if (existingEvent && existingEvent.processed) {
      console.log(`[Webhook] Event ${eventId} already processed. Skipping duplicate delivery.`);
      res.status(200).json({
        status: 'SKIPPED',
        message: 'Event already processed',
        eventId,
      });
      return;
    }

    // 3. Record or update webhook_events row
    let webhookRecord = existingEvent;
    if (!webhookRecord) {
      webhookRecord = await prisma.webhookEvent.create({
        data: {
          provider: 'wewire',
          eventType,
          eventId,
          payload: body,
          processed: false,
        },
      });
    }

    // 4. Process event business logic inside a database transaction (T3.5)
    await prisma.$transaction(async (tx) => {
      const data = body.data || body;
      const ref = data.reference || data.checkoutId || body.reference || body.checkoutId;
      const fundingTxId = data.fundingTransactionId || body.fundingTransactionId;
      const subCustomerId = data.subCustomerId || body.subCustomerId;

      const isFundingConfirmed =
        eventType === 'transaction.pay_in' ||
        eventType === 'subcustomer.wallet.deposit.received' ||
        eventType === 'collection.completed' ||
        eventType === 'funding.completed' ||
        eventType === 'checkout.completed' ||
        (eventType === 'transaction.status_updated' &&
          (data.status === 'SUCCESSFUL' || data.status === 'COMPLETED') &&
          data.type === 'CREDIT');

      // A crypto deposit is address-first: it arrives unannounced, for an
      // amount nobody declared in advance. It therefore has no PENDING row to
      // match, and must never be matched against one -- the loosest fiat
      // fallback below ("this user's newest PENDING deposit") would otherwise
      // credit an unrelated GBP top-up because some USDC turned up.
      const cryptoDeposit = parseCryptoDeposit(data);

      if (isFundingConfirmed) {
        // Find matching FundingTransaction
        let fundingTx: any = null;

        if (fundingTxId) {
          fundingTx = await tx.fundingTransaction.findUnique({
            where: { id: fundingTxId },
          });
        }

        if (!fundingTx && ref) {
          fundingTx = await tx.fundingTransaction.findFirst({
            where: { checkoutId: ref },
          });
        }

        // The on-chain hash is the only stable identity a crypto deposit
        // carries, and redelivery is guaranteed, so it is what makes this
        // idempotent.
        if (!fundingTx && cryptoDeposit?.txHash) {
          fundingTx = await tx.fundingTransaction.findUnique({
            where: { txHash: cryptoDeposit.txHash },
          });
        }

        if (!fundingTx && !cryptoDeposit && subCustomerId) {
          const matchedUser = await tx.user.findFirst({
            where: { wewireSubcustomerId: subCustomerId },
          });
          if (matchedUser) {
            fundingTx = await tx.fundingTransaction.findFirst({
              where: {
                userId: matchedUser.id,
                // EXPIRED is included deliberately. Expiry stops us *offering*
                // a stale deposit in the app; it must never stop us receiving
                // one. Someone who set up a transfer on Monday and sent it on
                // Wednesday still has to be credited.
                status: { in: ['PENDING', 'EXPIRED'] },
                // Never let a crypto arrival settle a fiat intent.
                source: 'FIAT',
              },
              orderBy: { createdAt: 'desc' },
            });
          }
        }

        // Nothing to match, so record the deposit that actually happened.
        if (!fundingTx && cryptoDeposit) {
          fundingTx = await createCryptoFundingTransaction(tx, cryptoDeposit, subCustomerId);
        }

        if (fundingTx && fundingTx.source === 'CRYPTO') {
          if (fundingTx.status !== 'COMPLETED') {
            await creditCryptoDeposit(tx, fundingTx);
          } else {
            console.log(
              `[Webhook] Crypto deposit ${fundingTx.txHash} already COMPLETED. Skipping wallet credit.`
            );
          }
        } else if (fundingTx) {
          // If already COMPLETED, do not increment again (idempotency defense)
          if (fundingTx.status !== 'COMPLETED') {
            // Credit what actually settled, not what the user asked to send:
            // the rails take a fee on the way in (a 250.00 GBP deposit settles
            // as 249.45). Crediting the requested figure would invent money.
            const { settled: settledAmount, fee } = parseSettlement(
              data,
              Number(fundingTx.amount)
            );

            await tx.fundingTransaction.update({
              where: { id: fundingTx.id },
              data: {
                status: 'COMPLETED',
                settledAmount,
                fee,
              },
            });

            // Find or create matching wallet
            const walletCurrency = fundingTx.currency || 'USD';
            let wallet = await tx.wallet.findFirst({
              where: {
                userId: fundingTx.userId,
                currency: walletCurrency,
              },
            });

            if (!wallet) {
              wallet = await tx.wallet.create({
                data: {
                  userId: fundingTx.userId,
                  currency: walletCurrency,
                  balance: settledAmount,
                },
              });
            } else {
              await tx.wallet.update({
                where: { id: wallet.id },
                data: {
                  balance: {
                    increment: settledAmount,
                  },
                },
              });
            }

            console.log(
              `[Webhook] Funding transaction ${fundingTx.id} COMPLETED. Credited ${settledAmount} ${walletCurrency} to user ${fundingTx.userId} (sent ${Number(fundingTx.amount)}, fee ${fee}).`
            );
          } else {
            console.log(
              `[Webhook] Funding transaction ${fundingTx.id} already COMPLETED. Skipping wallet credit.`
            );
          }
        } else {
          console.warn(`[Webhook] No matching funding transaction found for event ${eventId}`);
        }
      }

      // 4b. Payout / Disbursement webhook handling (T5.4)
      const isPayoutInitiated =
        eventType === 'disbursement.initiated' ||
        (eventType === 'transaction.status_updated' &&
          (data.status === 'PENDING' || data.status === 'PROCESSING') &&
          (data.type === 'DISBURSEMENT' || data.type === 'DEBIT'));

      const isPayoutCompleted =
        eventType === 'disbursement.completed' ||
        eventType === 'payout.completed' ||
        (eventType === 'transaction.status_updated' &&
          (data.status === 'SUCCESSFUL' || data.status === 'COMPLETED') &&
          (data.type === 'DISBURSEMENT' || data.type === 'DEBIT'));

      const isPayoutFailed =
        eventType === 'disbursement.failed' ||
        eventType === 'payout.failed' ||
        (eventType === 'transaction.status_updated' &&
          data.status === 'FAILED' &&
          (data.type === 'DISBURSEMENT' || data.type === 'DEBIT'));

      if (isPayoutInitiated || isPayoutCompleted || isPayoutFailed) {
        const wewireTxId = data.id || data.transactionId || body.id || body.transactionId;
        const payoutRef = data.reference || body.reference;
        const payoutIdempotencyKey = data.idempotencyKey || body.idempotencyKey;

        // Match local Transaction record
        let localTx: any = null;
        if (wewireTxId) {
          localTx = await tx.transaction.findFirst({
            where: { wewireTransactionId: wewireTxId },
          });
        }

        if (!localTx && payoutRef) {
          localTx = await tx.transaction.findFirst({
            where: {
              OR: [
                { id: payoutRef.startsWith('VP-') ? undefined : payoutRef },
                { idempotencyKey: payoutRef },
              ].filter(Boolean) as any,
            },
          });
        }

        if (!localTx && payoutIdempotencyKey) {
          localTx = await tx.transaction.findFirst({
            where: {
              OR: [
                { idempotencyKey: payoutIdempotencyKey },
                { id: payoutIdempotencyKey.replace('VP-DISB-', '') },
              ],
            },
          });
        }

        if (localTx) {
          if (isPayoutInitiated) {
            // Move through PROCESSING
            if (localTx.status === 'CREATED' || localTx.status === 'PENDING') {
              await tx.transaction.update({
                where: { id: localTx.id },
                data: { status: 'PROCESSING' },
              });
              console.log(`[Webhook] Payout ${localTx.id} moved to PROCESSING.`);
            }
          } else if (isPayoutCompleted) {
            // Move through PROCESSING -> COMPLETED and debit wallet exactly once
            if (localTx.status !== 'COMPLETED') {
              await tx.transaction.update({
                where: { id: localTx.id },
                data: { status: 'COMPLETED' },
              });

              // Debit user's source wallet ledger on transition to COMPLETED (T5.4)
              // Includes WeWire's own disbursement fee (localTx.wewireFee), passed on
              // to the user rather than absorbed by vessPay.
              const totalDebit =
                Number(localTx.sourceAmount) + Number(localTx.fee) + Number(localTx.wewireFee || 0);
              const wallet = await tx.wallet.findFirst({
                where: {
                  userId: localTx.userId,
                  currency: localTx.sourceCurrency,
                },
              });

              if (wallet) {
                await tx.wallet.update({
                  where: { id: wallet.id },
                  data: {
                    balance: {
                      decrement: totalDebit,
                    },
                  },
                });
                console.log(
                  `[Webhook] Payout ${localTx.id} COMPLETED. Debited $${totalDebit.toFixed(2)} ${localTx.sourceCurrency} from user ${localTx.userId} wallet.`
                );
              } else {
                console.warn(`[Webhook] Warning: No wallet found for user ${localTx.userId} to debit payout.`);
              }
            } else {
              console.log(
                `[Webhook] Payout ${localTx.id} already COMPLETED. Skipping duplicate wallet debit.`
              );
            }
          } else if (isPayoutFailed) {
            if (localTx.status !== 'FAILED') {
              await tx.transaction.update({
                where: { id: localTx.id },
                data: { status: 'FAILED' },
              });
              console.log(`[Webhook] Payout ${localTx.id} transitioned to FAILED. No wallet debit executed.`);
            }
          }
        } else {
          console.warn(`[Webhook] No matching payout transaction found for event ${eventId}`);
        }
      }

      // 4c. Virtual account provisioning (WeWire fires a status update on every
      // transition: REQUESTED -> PENDING -> ACTIVE). Recording the account id
      // here means the deposit screen learns it has gone live without polling.
      const isAccountStatusUpdate =
        eventType === 'virtual_account.status_updated' ||
        eventType === 'subcustomer.account.status_updated' ||
        eventType === 'account.status_updated';

      if (isAccountStatusUpdate) {
        const accountId = data.id || data.accountId || data.virtualAccountId;
        const accountCurrency = (data.currency || '').toString().toUpperCase();
        const accountStatus = (data.status || '').toString().toUpperCase();
        const accountSubCustomerId = data.subCustomerId || subCustomerId;

        if (!accountId || !accountSubCustomerId) {
          console.warn(
            `[Webhook] Account status event ${eventId} lacks an account or sub-customer id; skipping.`
          );
        } else {
          const owner = await tx.user.findFirst({
            where: { wewireSubcustomerId: accountSubCustomerId },
          });

          if (!owner) {
            console.warn(
              `[Webhook] No user holds sub-customer ${accountSubCustomerId} for event ${eventId}.`
            );
          } else {
            // Accounts are per-currency, so bind to the wallet of that currency.
            const wallet = await tx.wallet.findFirst({
              where: {
                userId: owner.id,
                currency: accountCurrency || DEFAULT_WALLET_CURRENCY,
              },
            });

            if (!wallet) {
              console.warn(
                `[Webhook] User ${owner.id} has no ${accountCurrency} wallet to attach account ${accountId} to.`
              );
            } else if (accountStatus === 'ACTIVE') {
              await tx.wallet.update({
                where: { id: wallet.id },
                data: { wewireAccountId: accountId },
              });
              console.log(
                `[Webhook] Virtual account ${accountId} is ACTIVE for user ${owner.id} (${wallet.currency}).`
              );
            } else if (
              ['DENIED', 'CLOSED', 'SUSPENDED'].includes(accountStatus)
            ) {
              // Stop pointing at an account that can no longer receive money.
              if (wallet.wewireAccountId === accountId) {
                await tx.wallet.update({
                  where: { id: wallet.id },
                  data: { wewireAccountId: null },
                });
              }
              console.warn(
                `[Webhook] Virtual account ${accountId} is ${accountStatus} for user ${owner.id}; detached.`
              );
            } else {
              console.log(
                `[Webhook] Virtual account ${accountId} is ${accountStatus} for user ${owner.id}; still provisioning.`
              );
            }
          }
        }
      }

      // 4d. Compliance state. WeWire pushes every KYC transition, so mirror it
      // locally: the deposit gate can then read our own database instead of
      // calling WeWire on every poll.
      const isKycUpdate =
        eventType === 'subcustomer.kyc_status_updated' ||
        eventType === 'subcustomer.enhanced_kyc_status_updated';

      if (isKycUpdate) {
        const kycSubCustomerId = data.subCustomerId || subCustomerId;
        if (!kycSubCustomerId) {
          console.warn(`[Webhook] KYC event ${eventId} has no sub-customer id.`);
        } else {
          const owner = await tx.user.findFirst({
            where: { wewireSubcustomerId: kycSubCustomerId },
          });

          if (!owner) {
            console.warn(
              `[Webhook] No user holds sub-customer ${kycSubCustomerId} for KYC event ${eventId}.`
            );
          } else {
            // Each event carries only the status it is about, so update the
            // field it reports and leave the other as it stands.
            const updates: Record<string, unknown> = {
              kycStatusUpdatedAt: new Date(),
            };
            if (typeof data.onboardingStatus === 'string') {
              updates.onboardingStatus = data.onboardingStatus.toUpperCase();
            }
            if (typeof data.enhancedKycStatus === 'string') {
              updates.enhancedKycStatus = data.enhancedKycStatus.toUpperCase();
            }

            await tx.user.update({ where: { id: owner.id }, data: updates });
            console.log(
              `[Webhook] KYC state for user ${owner.id} updated: ${JSON.stringify(updates)}`
            );
          }
        }
      }

      // 4e. Sweeps move the settled balance from the sub-customer wallet into
      // the business float. No user money changes hands — the ledger is already
      // credited by the pay-in — so this is recorded purely for reconciliation.
      if (eventType === 'subcustomer.wallet.swept') {
        const sweepSubCustomerId = data.subCustomerId || subCustomerId;
        const depositTransactionId = data.depositTransactionId || null;

        if (!sweepSubCustomerId) {
          console.warn(`[Webhook] Sweep event ${eventId} has no sub-customer id.`);
        } else {
          const owner = await tx.user.findFirst({
            where: { wewireSubcustomerId: sweepSubCustomerId },
          });

          // A sweep is identified by the deposit it settles, so a redelivery
          // updates the same row rather than duplicating the audit trail.
          const record = {
            userId: owner?.id ?? null,
            subCustomerId: sweepSubCustomerId,
            amount: Number(data.amount ?? 0),
            currency: (data.currency || 'USD').toString().toUpperCase(),
            direction: (data.direction || 'AUTO').toString().toUpperCase(),
            fromWalletId: data.fromWalletId ?? null,
            toWalletId: data.toWalletId ?? null,
            depositTransactionId,
            debitTransactionId: data.debitTransactionId ?? null,
            creditTransactionId: data.creditTransactionId ?? null,
            sweptAt: data.sweptAt ? new Date(data.sweptAt) : new Date(),
          };

          if (depositTransactionId) {
            await tx.walletSweep.upsert({
              where: { depositTransactionId },
              create: record,
              update: record,
            });
          } else {
            await tx.walletSweep.create({ data: record });
          }

          console.log(
            `[Webhook] Recorded sweep of ${record.amount} ${record.currency} for sub-customer ${sweepSubCustomerId}.`
          );
        }
      }

      // Mark webhook event record as processed
      await tx.webhookEvent.update({
        where: { id: webhookRecord.id },
        data: { processed: true },
      });
    });

    console.log(`[Webhook] Event ${eventId} (${eventType}) successfully processed.`);
    res.status(200).json({
      status: 'PROCESSED',
      message: 'Event processed successfully',
      eventId,
    });
  } catch (err: any) {
    console.error('Error processing WeWire webhook:', err);
    res.status(500).json({
      error: {
        code: 'INTERNAL_SERVER_ERROR',
        message: 'Failed to process webhook event',
      },
    });
  }
});

export default router;
