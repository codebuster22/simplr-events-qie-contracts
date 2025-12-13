import { parseAbiItem } from "abitype";
import { createConfig, factory } from "ponder";

import { AccessPassNFTAbi } from "./abis/AccessPassNFTAbi";
import { SimplrErrorsErrorsAbi } from "./abis/SimplrErrorsErrorsAbi";
import { EventAbi } from "./abis/EventAbi";
import { MarketplaceAbi } from "./abis/MarketplaceAbi";
import { EventFactoryAbi } from "./abis/EventFactoryAbi";


const llamaFactoryEvent = parseAbiItem(
  "event LlamaInstanceCreated(address indexed deployer, string indexed name, address llamaCore, address llamaExecutor, address llamaPolicy, uint256 chainId)",
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
        address: "0xFf5d4E226D9A3496EECE31083a8F493edd79AbEB",
        event: llamaFactoryEvent,
        parameter: "llamaCore",
      }),
      startBlock: parseInt(process.env.FACTORY_START_BLOCK || "0"),
    },
    EventFactory: {
      chain: process.env.PONDER_NETWORK as SupportedChains,
      abi: EventFactoryAbi,
      address: process.env.EVENT_FACTORY_ADDRESS as `0x${string}`,
      startBlock: parseInt(process.env.EVENT_FACTORY_START_BLOCK || "0"),
    },
    AccessPassNFT: {
      chain: process.env.PONDER_NETWORK as SupportedChains,
      abi: AccessPassNFTAbi,
      address: process.env.ACCESS_PASS_NFT_ADDRESS as `0x${string}`,
      startBlock: parseInt(process.env.ACCESS_PASS_NFT_START_BLOCK || "0"),
    },
    Marketplace: {
      chain: process.env.PONDER_NETWORK as SupportedChains,
      abi: MarketplaceAbi,
      address: process.env.MARKETPLACE_ADDRESS as `0x${string}`,
      startBlock: parseInt(process.env.MARKETPLACE_START_BLOCK || "0"),
    },
  },
});
