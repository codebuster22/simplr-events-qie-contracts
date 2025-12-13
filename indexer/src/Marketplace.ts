import { ponder } from "ponder:registry";
import { listing, listingPurchase, user } from "ponder:schema";

// ListingCreated Handler
ponder.on("Marketplace:ListingCreated", async ({ event: ev, context }) => {
  const {
    listingId,
    seller,
    eventContract,
    tokenId,
    quantity,
    pricePerUnit,
    expirationTime,
  } = ev.args;

  // tokenId in Marketplace corresponds to tierId in Event contract (ERC-1155)
  const tierId = `${eventContract}-${tokenId}`;

  // Ensure user exists
  await context.db.insert(user).values({ id: seller }).onConflictDoNothing();

  // Create Listing
  await context.db.insert(listing).values({
    id: listingId.toString(),
    listingId,
    sellerId: seller,
    eventId: eventContract,
    tierId,
    quantity,
    quantityRemaining: quantity,
    pricePerUnit,
    expirationTime,
    active: true,
    createdAt: ev.block.timestamp,
    txHash: ev.transaction.hash,
  });
});

// ListingPurchased Handler
ponder.on("Marketplace:ListingPurchased", async ({ event: ev, context }) => {
  const { listingId, buyer, quantity, totalPrice, royaltyPaid, royaltyReceiver } =
    ev.args;

  const purchaseId = `${ev.transaction.hash}-${ev.log.logIndex}`;
  const listingIdStr = listingId.toString();

  // Ensure user exists
  await context.db.insert(user).values({ id: buyer }).onConflictDoNothing();

  // Create ListingPurchase record
  await context.db.insert(listingPurchase).values({
    id: purchaseId,
    listingId: listingIdStr,
    buyerId: buyer,
    quantity,
    totalPrice,
    royaltyPaid,
    royaltyReceiver,
    timestamp: ev.block.timestamp,
    txHash: ev.transaction.hash,
  });

  // Update Listing quantityRemaining and active status
  const existingListing = await context.db.find(listing, { id: listingIdStr });
  if (existingListing) {
    const newQuantityRemaining = existingListing.quantityRemaining - quantity;
    if (newQuantityRemaining < 0n) {
      console.warn(`[ListingPurchased] Quantity underflow detected for listing ${listingIdStr}: ${existingListing.quantityRemaining} - ${quantity}`);
    }
    await context.db.update(listing, { id: listingIdStr }).set({
      quantityRemaining: newQuantityRemaining > 0n ? newQuantityRemaining : 0n,
      active: newQuantityRemaining > 0n,
    });
  } else {
    console.warn(`[ListingPurchased] Listing not found: ${listingIdStr}`);
  }
});

// ListingCancelled Handler
ponder.on("Marketplace:ListingCancelled", async ({ event: ev, context }) => {
  const { listingId } = ev.args;

  await context.db.update(listing, { id: listingId.toString() }).set({
    active: false,
  });
});

// ListingPriceUpdated Handler
ponder.on("Marketplace:ListingPriceUpdated", async ({ event: ev, context }) => {
  const { listingId, newPrice } = ev.args;

  await context.db.update(listing, { id: listingId.toString() }).set({
    pricePerUnit: newPrice,
  });
});
