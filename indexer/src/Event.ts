import { ponder } from "ponder:registry";
import {
  event,
  tier,
  ticketBalance,
  ticketPurchase,
  ticketRedemption,
  user,
} from "ponder:schema";
import { EventAbi } from "../abis/EventAbi";
import { zeroAddress } from "viem";

// TierCreated Handler - Also creates partial Event entity due to event ordering
ponder.on("Event:TierCreated", async ({ event: ev, context }) => {
  const eventAddress = ev.log.address;

  // Read contract data to create Event entity
  const [name, symbol, owner, accessPassNFT] = await Promise.all([
    context.client.readContract({
      address: eventAddress,
      abi: EventAbi,
      functionName: "name",
    }),
    context.client.readContract({
      address: eventAddress,
      abi: EventAbi,
      functionName: "symbol",
    }),
    context.client.readContract({
      address: eventAddress,
      abi: EventAbi,
      functionName: "owner",
    }),
    context.client.readContract({
      address: eventAddress,
      abi: EventAbi,
      functionName: "accessPassNFT",
    }),
  ]);

  // Ensure user exists
  await context.db.insert(user).values({ id: owner }).onConflictDoNothing();

  // Create Event entity if not exists (EventCreated will update with eventId later)
  await context.db
    .insert(event)
    .values({
      id: eventAddress,
      eventId: 0n, // Placeholder - updated by EventCreated
      name,
      symbol,
      baseURI: "",
      creatorId: owner,
      accessPassNFT,
      royaltyBps: 0,
      totalTicketsSold: 0n,
      totalTicketsRedeemed: 0n,
      createdAt: ev.block.timestamp,
    })
    .onConflictDoNothing();

  // Create Tier
  const tierId = `${eventAddress}-${ev.args.tierId}`;
  await context.db
    .insert(tier)
    .values({
      id: tierId,
      eventId: eventAddress,
      tierId: ev.args.tierId,
      tierName: ev.args.tierName,
      price: ev.args.price,
      maxSupply: ev.args.maxSupply,
      active: true,
      ticketsSold: 0n,
      ticketsRedeemed: 0n,
    })
    .onConflictDoNothing();
});

// TierUpdated Handler
ponder.on("Event:TierUpdated", async ({ event: ev, context }) => {
  const eventAddress = ev.log.address;
  const tierId = `${eventAddress}-${ev.args.tierId}`;

  await context.db.update(tier, { id: tierId }).set({
    price: ev.args.newPrice,
    maxSupply: ev.args.newMaxSupply,
  });
});

// TierActiveStatusChanged Handler
ponder.on("Event:TierActiveStatusChanged", async ({ event: ev, context }) => {
  const eventAddress = ev.log.address;
  const tierId = `${eventAddress}-${ev.args.tierId}`;

  await context.db.update(tier, { id: tierId }).set({
    active: ev.args.active,
  });
});

// TicketsPurchased Handler
ponder.on("Event:TicketsPurchased", async ({ event: ev, context }) => {
  const eventAddress = ev.log.address;
  const { buyer, tierId: tierIdNum, quantity, totalPaid } = ev.args;
  const tierId = `${eventAddress}-${tierIdNum}`;
  const purchaseId = `${ev.transaction.hash}-${ev.log.logIndex}`;

  // Ensure user exists
  await context.db.insert(user).values({ id: buyer }).onConflictDoNothing();

  // Create purchase record
  await context.db.insert(ticketPurchase).values({
    id: purchaseId,
    eventId: eventAddress,
    tierId,
    buyerId: buyer,
    quantity,
    totalPaid,
    timestamp: ev.block.timestamp,
    txHash: ev.transaction.hash,
  });

  // Increment tier ticketsSold
  const existingTier = await context.db.find(tier, { id: tierId });
  if (existingTier) {
    await context.db.update(tier, { id: tierId }).set({
      ticketsSold: existingTier.ticketsSold + quantity,
    });
  } else {
    console.warn(`[TicketsPurchased] Tier not found: ${tierId}`);
  }

  // Increment event totalTicketsSold
  const existingEvent = await context.db.find(event, { id: eventAddress });
  if (existingEvent) {
    await context.db.update(event, { id: eventAddress }).set({
      totalTicketsSold: existingEvent.totalTicketsSold + quantity,
    });
  } else {
    console.warn(`[TicketsPurchased] Event not found: ${eventAddress}`);
  }
});

// TicketRedeemed Handler
ponder.on("Event:TicketRedeemed", async ({ event: ev, context }) => {
  const eventAddress = ev.log.address;
  const { ticketHolder, tierId: tierIdNum, accessPassId } = ev.args;
  const tierId = `${eventAddress}-${tierIdNum}`;
  const redemptionId = `${ev.transaction.hash}-${ev.log.logIndex}`;

  // Ensure user exists
  await context.db
    .insert(user)
    .values({ id: ticketHolder })
    .onConflictDoNothing();

  // Create redemption record
  await context.db.insert(ticketRedemption).values({
    id: redemptionId,
    eventId: eventAddress,
    tierId,
    userId: ticketHolder,
    accessPassId,
    timestamp: ev.block.timestamp,
    txHash: ev.transaction.hash,
  });

  // Increment tier ticketsRedeemed
  const existingTier = await context.db.find(tier, { id: tierId });
  if (existingTier) {
    await context.db.update(tier, { id: tierId }).set({
      ticketsRedeemed: existingTier.ticketsRedeemed + 1n,
    });
  } else {
    console.warn(`[TicketRedeemed] Tier not found: ${tierId}`);
  }

  // Increment event totalTicketsRedeemed
  const existingEvent = await context.db.find(event, { id: eventAddress });
  if (existingEvent) {
    await context.db.update(event, { id: eventAddress }).set({
      totalTicketsRedeemed: existingEvent.totalTicketsRedeemed + 1n,
    });
  } else {
    console.warn(`[TicketRedeemed] Event not found: ${eventAddress}`);
  }
});

// TransferSingle Handler (ERC-1155)
ponder.on("Event:TransferSingle", async ({ event: ev, context }) => {
  const { from, to, id: tokenId, value } = ev.args;
  const eventAddress = ev.log.address;
  const tierId = `${eventAddress}-${tokenId}`;

  // Ensure users exist
  if (from !== zeroAddress) {
    await context.db.insert(user).values({ id: from }).onConflictDoNothing();
  }
  if (to !== zeroAddress) {
    await context.db.insert(user).values({ id: to }).onConflictDoNothing();
  }

  // Update sender balance (if not mint)
  if (from !== zeroAddress) {
    const fromBalanceId = `${eventAddress}-${tokenId}-${from}`;
    const existing = await context.db.find(ticketBalance, { id: fromBalanceId });
    if (existing) {
      const newBalance = existing.balance - value;
      if (newBalance < 0n) {
        console.warn(`[TransferSingle] Balance underflow detected for ${fromBalanceId}: ${existing.balance} - ${value}`);
      }
      if (newBalance > 0n) {
        await context.db.update(ticketBalance, { id: fromBalanceId }).set({
          balance: newBalance,
        });
      } else {
        // Remove balance record if zero or negative
        await context.db.delete(ticketBalance, { id: fromBalanceId });
      }
    } else {
      console.warn(`[TransferSingle] Balance record not found for sender: ${fromBalanceId}`);
    }
  }

  // Update receiver balance (if not burn)
  if (to !== zeroAddress) {
    const toBalanceId = `${eventAddress}-${tokenId}-${to}`;
    await context.db
      .insert(ticketBalance)
      .values({
        id: toBalanceId,
        eventId: eventAddress,
        tierId,
        userId: to,
        balance: value,
      })
      .onConflictDoUpdate((existing) => ({
        balance: existing.balance + value,
      }));
  }
});

// TransferBatch Handler (ERC-1155)
ponder.on("Event:TransferBatch", async ({ event: ev, context }) => {
  const { from, to, ids, values } = ev.args;
  const eventAddress = ev.log.address;

  // Ensure users exist
  if (from !== zeroAddress) {
    await context.db.insert(user).values({ id: from }).onConflictDoNothing();
  }
  if (to !== zeroAddress) {
    await context.db.insert(user).values({ id: to }).onConflictDoNothing();
  }

  // Process each token transfer
  for (let i = 0; i < ids.length; i++) {
    const tokenId = ids[i]!;
    const value = values[i]!;
    const tierId = `${eventAddress}-${tokenId}`;

    // Update sender balance (if not mint)
    if (from !== zeroAddress) {
      const fromBalanceId = `${eventAddress}-${tokenId}-${from}`;
      const existing = await context.db.find(ticketBalance, {
        id: fromBalanceId,
      });
      if (existing) {
        const newBalance = existing.balance - value;
        if (newBalance < 0n) {
          console.warn(`[TransferBatch] Balance underflow detected for ${fromBalanceId}: ${existing.balance} - ${value}`);
        }
        if (newBalance > 0n) {
          await context.db.update(ticketBalance, { id: fromBalanceId }).set({
            balance: newBalance,
          });
        } else {
          // Remove balance record if zero or negative
          await context.db.delete(ticketBalance, { id: fromBalanceId });
        }
      } else {
        console.warn(`[TransferBatch] Balance record not found for sender: ${fromBalanceId}`);
      }
    }

    // Update receiver balance (if not burn)
    if (to !== zeroAddress) {
      const toBalanceId = `${eventAddress}-${tokenId}-${to}`;
      await context.db
        .insert(ticketBalance)
        .values({
          id: toBalanceId,
          eventId: eventAddress,
          tierId,
          userId: to,
          balance: value,
        })
        .onConflictDoUpdate((existing) => ({
          balance: existing.balance + value,
        }));
    }
  }
});
