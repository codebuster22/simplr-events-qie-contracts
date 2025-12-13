import { ponder } from "ponder:registry";
import { accessPass, user } from "ponder:schema";
import { AccessPassNFTAbi } from "../abis/AccessPassNFTAbi";
import { zeroAddress } from "viem";

// AccessPassMinted Handler
ponder.on("AccessPassNFT:AccessPassMinted", async ({ event: ev, context }) => {
  const { tokenId, recipient, tierId } = ev.args;
  const accessPassAddress = ev.log.address;

  // Get parent Event address
  const eventContract = await context.client.readContract({
    address: accessPassAddress,
    abi: AccessPassNFTAbi,
    functionName: "eventContract",
  });

  // Ensure user exists
  await context.db.insert(user).values({ id: recipient }).onConflictDoNothing();

  // Create AccessPass with composite tierId for proper relation to tier table
  const tierIdStr = `${eventContract}-${tierId}`;
  await context.db.insert(accessPass).values({
    id: `${accessPassAddress}-${tokenId}`,
    accessPassNFT: accessPassAddress,
    eventId: eventContract,
    tokenId,
    tierId: tierIdStr,
    ownerId: recipient,
    mintTimestamp: ev.block.timestamp,
  });
});

// Transfer Handler - Update owner (skip mints, from=0x0)
ponder.on("AccessPassNFT:Transfer", async ({ event: ev, context }) => {
  const { from, to, tokenId } = ev.args;
  const accessPassAddress = ev.log.address;

  // Skip mint transfers (already handled by AccessPassMinted)
  if (from === zeroAddress) {
    return;
  }

  // Ensure new owner exists
  if (to !== zeroAddress) {
    await context.db.insert(user).values({ id: to }).onConflictDoNothing();
  }

  // Update AccessPass owner
  const accessPassId = `${accessPassAddress}-${tokenId}`;

  if (to === zeroAddress) {
    // Burn - delete the access pass
    await context.db.delete(accessPass, { id: accessPassId });
  } else {
    // Transfer - update owner
    await context.db.update(accessPass, { id: accessPassId }).set({
      ownerId: to,
    });
  }
});
