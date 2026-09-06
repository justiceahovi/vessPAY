import { Router, Request, Response } from 'express';
import { prisma } from '../lib/db';
import { verifyWeWireSignature } from '../lib/webhook';
import { DEFAULT_WALLET_CURRENCY } from '../lib/currencies';

const router = Router();

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

        if (!fundingTx && subCustomerId) {
          const matchedUser = await tx.user.findFirst({
            where: { wewireSubcustomerId: subCustomerId },
          });
          if (matchedUser) {
            fundingTx = await tx.fundingTransaction.findFirst({
              where: {
                userId: matchedUser.id,
                status: 'PENDING',
              },
              orderBy: { createdAt: 'desc' },
            });
          }
        }

        if (fundingTx) {
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
              const totalDebit = Number(localTx.sourceAmount) + Number(localTx.fee);
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
