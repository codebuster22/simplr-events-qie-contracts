import { parseAbiItem } from "abitype";
import { createConfig, factory } from "ponder";

import { AccessPassNFTAbi } from "./abis/AccessPassNFTAbi";
import { EventAbi } from "./abis/EventAbi";
import { MarketplaceAbi } from "./abis/MarketplaceAbi";
import { EventFactoryAbi } from "./abis/EventFactoryAbi";

const FactoryEventAbi = parseAbiItem(
  "event EventCreated(address indexed eventAddress,address indexed creator,string name,uint256 indexed eventId,address accessPassNFT)",
);

type SupportedChains = "qieMainnet" | "qieTestnet";

export default createConfig({
  chains: {
    qieMainnet: {
      id: 1990,
      rpc: process.env.PONDER_RPC_URL_QIE_MAINNET,
    },
    qieTestnet: {
      id: 1983,
      rpc: process.env.PONDER_RPC_URL_QIE_TESTNET,
    }
  },
  contracts: {
    Event: {
      chain: process.env.PONDER_NETWORK as SupportedChains,
      abi: EventAbi,
      address: factory({
        address: process.env.EVENT_FACTORY_ADDRESS as `0x${string}`,
        event: FactoryEventAbi,
        parameter: "eventAddress",
      }),
      startBlock: parseInt(process.env.FACTORY_START_BLOCK || "0"),
    },
    AccessPassNFT: {
      chain: process.env.PONDER_NETWORK as SupportedChains,
      abi: AccessPassNFTAbi,
      address: factory({
        address: process.env.EVENT_FACTORY_ADDRESS as `0x${string}`,
        event: FactoryEventAbi,
        parameter: "accessPassNFT",
      }),
      startBlock: parseInt(process.env.FACTORY_START_BLOCK || "0"),
    },
    EventFactory: {
      chain: process.env.PONDER_NETWORK as SupportedChains,
      abi: EventFactoryAbi,
      address: process.env.EVENT_FACTORY_ADDRESS as `0x${string}`,
      startBlock: parseInt(process.env.FACTORY_START_BLOCK || "0"),
    },
    Marketplace: {
      chain: process.env.PONDER_NETWORK as SupportedChains,
      abi: MarketplaceAbi,
      address: process.env.MARKETPLACE_ADDRESS as `0x${string}`,
      startBlock: parseInt(process.env.MARKETPLACE_START_BLOCK || "0"),
    },
  },
});
