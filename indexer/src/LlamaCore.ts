import { ponder } from "ponder:registry";

ponder.on("Event:Initialized", async ({ event }) => {
  console.log(
    `Handling Initialized event from Event @ ${event.log.address}`,
  );
});