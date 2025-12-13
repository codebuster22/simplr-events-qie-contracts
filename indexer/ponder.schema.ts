import { onchainTable, relations } from "ponder";

// ==================== TABLES ====================

export const user = onchainTable("user", (t) => ({
  id: t.hex().primaryKey(), // wallet address
}));

export const event = onchainTable("event", (t) => ({
  id: t.text().primaryKey(), // eventAddress
  eventId: t.bigint().notNull(),
  name: t.text().notNull(),
  symbol: t.text().notNull(),
  baseURI: t.text().notNull(),
  creatorId: t.hex().notNull(), // FK to user
  accessPassNFT: t.hex().notNull(),
  royaltyBps: t.integer().notNull(),
  totalTicketsSold: t.bigint().notNull(),
  totalTicketsRedeemed: t.bigint().notNull(),
  createdAt: t.bigint().notNull(),
}));

export const tier = onchainTable("tier", (t) => ({
  id: t.text().primaryKey(), // eventAddress-tierId
  eventId: t.text().notNull(), // FK to event
  tierId: t.bigint().notNull(),
  tierName: t.text().notNull(),
  price: t.bigint().notNull(),
  maxSupply: t.bigint().notNull(),
  active: t.boolean().notNull(),
  ticketsSold: t.bigint().notNull(),
  ticketsRedeemed: t.bigint().notNull(),
}));

export const ticketBalance = onchainTable("ticket_balance", (t) => ({
  id: t.text().primaryKey(), // eventAddress-tierId-userId
  eventId: t.text().notNull(), // FK to event
  tierId: t.text().notNull(), // FK to tier
  userId: t.hex().notNull(), // FK to user
  balance: t.bigint().notNull(),
}));

export const ticketPurchase = onchainTable("ticket_purchase", (t) => ({
  id: t.text().primaryKey(), // txHash-logIndex
  eventId: t.text().notNull(), // FK to event
  tierId: t.text().notNull(), // FK to tier
  buyerId: t.hex().notNull(), // FK to user
  quantity: t.bigint().notNull(),
  totalPaid: t.bigint().notNull(),
  timestamp: t.bigint().notNull(),
  txHash: t.hex().notNull(),
}));

export const ticketRedemption = onchainTable("ticket_redemption", (t) => ({
  id: t.text().primaryKey(), // txHash-logIndex
  eventId: t.text().notNull(), // FK to event
  tierId: t.text().notNull(), // FK to tier
  userId: t.hex().notNull(), // FK to user
  accessPassId: t.bigint().notNull(),
  timestamp: t.bigint().notNull(),
  txHash: t.hex().notNull(),
}));

export const accessPass = onchainTable("access_pass", (t) => ({
  id: t.text().primaryKey(), // accessPassNFT-tokenId
  accessPassNFT: t.hex().notNull(),
  eventId: t.text().notNull(), // FK to event
  tokenId: t.bigint().notNull(),
  tierId: t.text().notNull(), // FK to tier (composite key: eventAddress-tierId)
  ownerId: t.hex().notNull(), // FK to user
  mintTimestamp: t.bigint().notNull(),
}));

export const listing = onchainTable("listing", (t) => ({
  id: t.text().primaryKey(), // listingId
  listingId: t.bigint().notNull(),
  sellerId: t.hex().notNull(), // FK to user
  eventId: t.text().notNull(), // FK to event
  tierId: t.text().notNull(), // FK to tier
  quantity: t.bigint().notNull(),
  quantityRemaining: t.bigint().notNull(),
  pricePerUnit: t.bigint().notNull(),
  expirationTime: t.bigint().notNull(),
  active: t.boolean().notNull(),
  createdAt: t.bigint().notNull(),
  txHash: t.hex().notNull(),
}));

export const listingPurchase = onchainTable("listing_purchase", (t) => ({
  id: t.text().primaryKey(), // txHash-logIndex
  listingId: t.text().notNull(), // FK to listing
  buyerId: t.hex().notNull(), // FK to user
  quantity: t.bigint().notNull(),
  totalPrice: t.bigint().notNull(),
  royaltyPaid: t.bigint().notNull(),
  royaltyReceiver: t.hex().notNull(),
  timestamp: t.bigint().notNull(),
  txHash: t.hex().notNull(),
}));

// ==================== RELATIONS ====================

// User relations (one-to-many)
export const userRelations = relations(user, ({ many }) => ({
  createdEvents: many(event), // Events created by this user
  ticketBalances: many(ticketBalance), // Ticket holdings
  accessPasses: many(accessPass), // Access passes owned
  listings: many(listing), // Marketplace listings
  purchases: many(ticketPurchase), // Ticket purchases
  redemptions: many(ticketRedemption), // Ticket redemptions
  listingPurchases: many(listingPurchase), // Marketplace purchases
}));

// Event relations
export const eventRelations = relations(event, ({ one, many }) => ({
  creator: one(user, { fields: [event.creatorId], references: [user.id] }),
  tiers: many(tier),
  ticketBalances: many(ticketBalance),
  accessPasses: many(accessPass),
  listings: many(listing),
  purchases: many(ticketPurchase),
  redemptions: many(ticketRedemption),
}));

// Tier relations
export const tierRelations = relations(tier, ({ one, many }) => ({
  event: one(event, { fields: [tier.eventId], references: [event.id] }),
  ticketBalances: many(ticketBalance),
  purchases: many(ticketPurchase),
  redemptions: many(ticketRedemption),
  listings: many(listing),
}));

// TicketBalance relations
export const ticketBalanceRelations = relations(ticketBalance, ({ one }) => ({
  event: one(event, { fields: [ticketBalance.eventId], references: [event.id] }),
  tier: one(tier, { fields: [ticketBalance.tierId], references: [tier.id] }),
  user: one(user, { fields: [ticketBalance.userId], references: [user.id] }),
}));

// TicketPurchase relations
export const ticketPurchaseRelations = relations(ticketPurchase, ({ one }) => ({
  event: one(event, { fields: [ticketPurchase.eventId], references: [event.id] }),
  tier: one(tier, { fields: [ticketPurchase.tierId], references: [tier.id] }),
  buyer: one(user, { fields: [ticketPurchase.buyerId], references: [user.id] }),
}));

// TicketRedemption relations
export const ticketRedemptionRelations = relations(ticketRedemption, ({ one }) => ({
  event: one(event, { fields: [ticketRedemption.eventId], references: [event.id] }),
  tier: one(tier, { fields: [ticketRedemption.tierId], references: [tier.id] }),
  user: one(user, { fields: [ticketRedemption.userId], references: [user.id] }),
}));

// AccessPass relations
export const accessPassRelations = relations(accessPass, ({ one }) => ({
  event: one(event, { fields: [accessPass.eventId], references: [event.id] }),
  tier: one(tier, { fields: [accessPass.tierId], references: [tier.id] }),
  owner: one(user, { fields: [accessPass.ownerId], references: [user.id] }),
}));

// Listing relations
export const listingRelations = relations(listing, ({ one, many }) => ({
  seller: one(user, { fields: [listing.sellerId], references: [user.id] }),
  event: one(event, { fields: [listing.eventId], references: [event.id] }),
  tier: one(tier, { fields: [listing.tierId], references: [tier.id] }),
  purchases: many(listingPurchase),
}));

// ListingPurchase relations
export const listingPurchaseRelations = relations(listingPurchase, ({ one }) => ({
  listing: one(listing, { fields: [listingPurchase.listingId], references: [listing.id] }),
  buyer: one(user, { fields: [listingPurchase.buyerId], references: [user.id] }),
}));
