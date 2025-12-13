import { ponder } from "ponder:registry";
import { event, user } from "ponder:schema";
import { EventAbi } from "../abis/EventAbi";

ponder.on("EventFactory:EventCreated", async ({ event: ev, context }) => {
  const { eventAddress, creator, name, eventId, accessPassNFT } = ev.args;

  // Ensure user exists
  await context.db.insert(user).values({ id: creator }).onConflictDoNothing();

  // Read additional data from Event contract
  const [symbol, baseURI, royaltyInfo] = await Promise.all([
    context.client.readContract({
      address: eventAddress,
      abi: EventAbi,
      functionName: "symbol",
    }),
    context.client.readContract({
      address: eventAddress,
      abi: EventAbi,
      functionName: "uri",
      args: [0n],
    }),
    context.client.readContract({
      address: eventAddress,
      abi: EventAbi,
      functionName: "royaltyInfo",
      args: [0n, 10000n],
    }),
  ]);

  // Upsert Event (may already exist from TierCreated)
  await context.db
    .insert(event)
    .values({
      id: eventAddress,
      eventId,
      name,
      symbol,
      baseURI,
      creatorId: creator,
      accessPassNFT,
      royaltyBps: Number(royaltyInfo[1]),
      totalTicketsSold: 0n,
      totalTicketsRedeemed: 0n,
      createdAt: ev.block.timestamp,
    })
    .onConflictDoUpdate({
      eventId,
      name,
      symbol,
      baseURI,
      creatorId: creator,
      accessPassNFT,
      royaltyBps: Number(royaltyInfo[1]),
      createdAt: ev.block.timestamp,
    });
});
