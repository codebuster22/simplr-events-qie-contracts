# Main App Frontend Integration Guide

This guide is for frontend developers building the main ticketing application. It covers event creation, browsing, ticket purchasing, user portfolio, and marketplace integration.

---

## Table of Contents

1. [Setup & Configuration](#1-setup--configuration)
2. [Event Discovery](#2-event-discovery)
3. [Event Creation](#3-event-creation)
4. [Ticket Purchase](#4-ticket-purchase)
5. [User's Tickets](#5-users-tickets)
6. [Marketplace Integration](#6-marketplace-integration)
7. [Events Reference](#7-events-reference)
8. [Error Handling](#8-error-handling)

---

## 1. Setup & Configuration

### Install Dependencies

```bash
npm install viem
```

### Define QIE Testnet Chain

```typescript
// src/config/chains.ts
import { defineChain } from 'viem'

export const qieTestnet = defineChain({
  id: 1983,
  name: 'QIE Testnet',
  nativeCurrency: {
    decimals: 18,
    name: 'QIE',
    symbol: 'QIE',
  },
  rpcUrls: {
    default: {
      http: ['https://rpc1testnet.qie.digital'],
    },
  },
  blockExplorers: {
    default: { name: 'QIE Explorer', url: 'https://testnet.qie.digital' },
  },
})
```

### Contract Addresses

```typescript
// src/config/contracts.ts
export const CONTRACT_ADDRESSES = {
  eventFactory: '0x0efc2cc2a4ccd3F897076f7526951914362e1e5F' as const,
  marketplace: '0x5715D2CF651DF22032CfCF041bc90a9AA68Dd03f' as const,
  eventImplementation: '0xa6Dc66Fce6147E78abb50F3a9Ed6A14069a0c7D1' as const,
}
```

### Create viem Clients

```typescript
// src/config/client.ts
import { createPublicClient, createWalletClient, http, custom } from 'viem'
import { qieTestnet } from './chains'

// Public client for read operations
export const publicClient = createPublicClient({
  chain: qieTestnet,
  transport: http(),
})

// Wallet client for write operations (requires wallet connection)
export const getWalletClient = () => {
  if (typeof window === 'undefined' || !window.ethereum) {
    throw new Error('No wallet found')
  }
  return createWalletClient({
    chain: qieTestnet,
    transport: custom(window.ethereum),
  })
}
```

### Import ABIs

```typescript
// src/config/abis.ts
import EventFactoryABI from '../abis/EventFactory.json'
import EventABI from '../abis/Event.json'
import MarketplaceABI from '../abis/Marketplace.json'
import AccessPassNFTABI from '../abis/AccessPassNFT.json'

export { EventFactoryABI, EventABI, MarketplaceABI, AccessPassNFTABI }
```

---

## 2. Event Discovery

### Fetching All Events (Historical)

To get the list of all events ever created, query the `EventCreated` events from the EventFactory contract.

```typescript
import { parseAbiItem } from 'viem'
import { publicClient } from './config/client'
import { CONTRACT_ADDRESSES } from './config/contracts'

// Define the event signature
const eventCreatedAbi = parseAbiItem(
  'event EventCreated(address indexed eventAddress, address indexed creator, string name, uint256 indexed eventId)'
)

// Fetch all EventCreated events
async function getAllEvents() {
  const logs = await publicClient.getLogs({
    address: CONTRACT_ADDRESSES.eventFactory,
    event: eventCreatedAbi,
    fromBlock: 0n, // Or specify deployment block for efficiency
    toBlock: 'latest',
  })

  return logs.map((log) => ({
    eventAddress: log.args.eventAddress,
    creator: log.args.creator,
    name: log.args.name,
    eventId: log.args.eventId,
    blockNumber: log.blockNumber,
    transactionHash: log.transactionHash,
  }))
}
```

### Get Events by Creator

```typescript
import { EventFactoryABI } from './config/abis'

async function getEventsByCreator(creatorAddress: `0x${string}`) {
  const events = await publicClient.readContract({
    address: CONTRACT_ADDRESSES.eventFactory,
    abi: EventFactoryABI,
    functionName: 'getEventsByCreator',
    args: [creatorAddress],
  })

  return events // Returns array of event contract addresses
}
```

### Get Event Details

```typescript
import { EventABI } from './config/abis'

async function getEventDetails(eventAddress: `0x${string}`) {
  const [name, symbol, accessPassNFT] = await Promise.all([
    publicClient.readContract({
      address: eventAddress,
      abi: EventABI,
      functionName: 'name',
    }),
    publicClient.readContract({
      address: eventAddress,
      abi: EventABI,
      functionName: 'symbol',
    }),
    publicClient.readContract({
      address: eventAddress,
      abi: EventABI,
      functionName: 'accessPassNFT',
    }),
  ])

  return { name, symbol, accessPassNFT }
}
```

### Get Tier Information

```typescript
interface Tier {
  price: bigint
  maxSupply: bigint
  tierName: string
  active: boolean
}

async function getTier(eventAddress: `0x${string}`, tierId: bigint): Promise<Tier> {
  const tier = await publicClient.readContract({
    address: eventAddress,
    abi: EventABI,
    functionName: 'getTier',
    args: [tierId],
  })

  return tier as Tier
}

// Get total supply (tickets sold) for a tier
async function getTierSupply(eventAddress: `0x${string}`, tierId: bigint) {
  const supply = await publicClient.readContract({
    address: eventAddress,
    abi: EventABI,
    functionName: 'totalSupply',
    args: [tierId],
  })

  return supply
}
```

### Get All Tiers for an Event

To discover all tiers, listen to `TierCreated` events:

```typescript
const tierCreatedAbi = parseAbiItem(
  'event TierCreated(uint256 indexed tierId, string tierName, uint256 price, uint256 maxSupply)'
)

async function getAllTiers(eventAddress: `0x${string}`) {
  const logs = await publicClient.getLogs({
    address: eventAddress,
    event: tierCreatedAbi,
    fromBlock: 0n,
    toBlock: 'latest',
  })

  // Fetch current tier state (may have been updated)
  const tiers = await Promise.all(
    logs.map(async (log) => {
      const tierId = log.args.tierId!
      const currentTier = await getTier(eventAddress, tierId)
      const supply = await getTierSupply(eventAddress, tierId)

      return {
        tierId,
        ...currentTier,
        currentSupply: supply,
        available: currentTier.maxSupply - supply,
      }
    })
  )

  return tiers
}
```

---

## 3. Event Creation

### Data Structures

```typescript
// EventConfig structure
interface EventConfig {
  name: string
  symbol: string
  baseURI: string
  royaltyBps: number // Basis points (500 = 5%)
}

// TierConfig structure
interface TierConfig {
  tierId: bigint
  tierName: string
  price: bigint // In wei
  maxSupply: bigint
}
```

### Create Event

```typescript
import { parseEther } from 'viem'
import { EventFactoryABI } from './config/abis'

async function createEvent(
  eventConfig: EventConfig,
  tiers: TierConfig[],
  gatekeepers: `0x${string}`[]
) {
  const walletClient = getWalletClient()
  const [account] = await walletClient.getAddresses()

  const hash = await walletClient.writeContract({
    address: CONTRACT_ADDRESSES.eventFactory,
    abi: EventFactoryABI,
    functionName: 'createEvent',
    args: [
      {
        name: eventConfig.name,
        symbol: eventConfig.symbol,
        baseURI: eventConfig.baseURI,
        royaltyBps: BigInt(eventConfig.royaltyBps),
      },
      tiers,
      gatekeepers,
    ],
    account,
  })

  // Wait for transaction confirmation
  const receipt = await publicClient.waitForTransactionReceipt({ hash })

  // Extract event address from logs
  const eventCreatedLog = receipt.logs.find((log) => {
    // EventCreated topic
    return log.topics[0] === '0x...' // Use actual topic hash
  })

  return { hash, receipt }
}

// Example usage
const newEvent = await createEvent(
  {
    name: 'Summer Music Festival',
    symbol: 'SMF',
    baseURI: 'https://api.myevent.com/metadata/',
    royaltyBps: 500, // 5% royalty
  },
  [
    {
      tierId: 1n,
      tierName: 'VIP',
      price: parseEther('0.1'), // 0.1 QIE
      maxSupply: 100n,
    },
    {
      tierId: 2n,
      tierName: 'General Admission',
      price: parseEther('0.01'), // 0.01 QIE
      maxSupply: 1000n,
    },
  ],
  ['0x...gatekeeperAddress'] // Gatekeeper addresses
)
```

### Listen for EventCreated

```typescript
async function watchEventCreated(
  callback: (event: {
    eventAddress: `0x${string}`
    creator: `0x${string}`
    name: string
    eventId: bigint
  }) => void
) {
  const unwatch = publicClient.watchEvent({
    address: CONTRACT_ADDRESSES.eventFactory,
    event: eventCreatedAbi,
    onLogs: (logs) => {
      logs.forEach((log) => {
        callback({
          eventAddress: log.args.eventAddress!,
          creator: log.args.creator!,
          name: log.args.name!,
          eventId: log.args.eventId!,
        })
      })
    },
  })

  return unwatch // Call to stop watching
}
```

---

## 4. Ticket Purchase

### Check Availability

```typescript
async function checkTicketAvailability(eventAddress: `0x${string}`, tierId: bigint) {
  const tier = await getTier(eventAddress, tierId)
  const currentSupply = await getTierSupply(eventAddress, tierId)

  return {
    isActive: tier.active,
    price: tier.price,
    maxSupply: tier.maxSupply,
    sold: currentSupply,
    available: tier.maxSupply - currentSupply,
  }
}
```

### Buy Tickets

```typescript
async function buyTickets(
  eventAddress: `0x${string}`,
  tierId: bigint,
  quantity: bigint
) {
  const walletClient = getWalletClient()
  const [account] = await walletClient.getAddresses()

  // Get tier price
  const tier = await getTier(eventAddress, tierId)
  const totalPrice = tier.price * quantity

  const hash = await walletClient.writeContract({
    address: eventAddress,
    abi: EventABI,
    functionName: 'buyTickets',
    args: [tierId, quantity],
    value: totalPrice,
    account,
  })

  const receipt = await publicClient.waitForTransactionReceipt({ hash })

  return { hash, receipt }
}

// Example usage
const purchase = await buyTickets(
  '0x...eventAddress',
  1n, // VIP tier
  2n  // Buy 2 tickets
)
```

### Listen for TicketsPurchased

```typescript
const ticketsPurchasedAbi = parseAbiItem(
  'event TicketsPurchased(address indexed buyer, uint256 indexed tierId, uint256 quantity, uint256 totalPaid)'
)

async function watchTicketPurchases(
  eventAddress: `0x${string}`,
  callback: (purchase: {
    buyer: `0x${string}`
    tierId: bigint
    quantity: bigint
    totalPaid: bigint
  }) => void
) {
  const unwatch = publicClient.watchEvent({
    address: eventAddress,
    event: ticketsPurchasedAbi,
    onLogs: (logs) => {
      logs.forEach((log) => {
        callback({
          buyer: log.args.buyer!,
          tierId: log.args.tierId!,
          quantity: log.args.quantity!,
          totalPaid: log.args.totalPaid!,
        })
      })
    },
  })

  return unwatch
}
```

---

## 5. User's Tickets

### Get User's Ticket Balance (ERC-1155)

```typescript
async function getUserTicketBalance(
  eventAddress: `0x${string}`,
  userAddress: `0x${string}`,
  tierId: bigint
) {
  const balance = await publicClient.readContract({
    address: eventAddress,
    abi: EventABI,
    functionName: 'balanceOf',
    args: [userAddress, tierId],
  })

  return balance
}

// Get all tickets for a user across all tiers
async function getUserAllTickets(
  eventAddress: `0x${string}`,
  userAddress: `0x${string}`
) {
  const tiers = await getAllTiers(eventAddress)

  const balances = await Promise.all(
    tiers.map(async (tier) => {
      const balance = await getUserTicketBalance(eventAddress, userAddress, tier.tierId)
      return {
        tierId: tier.tierId,
        tierName: tier.tierName,
        balance,
      }
    })
  )

  return balances.filter((b) => b.balance > 0n)
}
```

### Get User's Access Passes (ERC-721)

```typescript
import { AccessPassNFTABI } from './config/abis'

// Get user's access pass count
async function getUserAccessPassCount(
  accessPassNFTAddress: `0x${string}`,
  userAddress: `0x${string}`
) {
  const balance = await publicClient.readContract({
    address: accessPassNFTAddress,
    abi: AccessPassNFTABI,
    functionName: 'balanceOf',
    args: [userAddress],
  })

  return balance
}

// Get access pass metadata
interface PassMetadata {
  tierId: bigint
  mintTimestamp: bigint
}

async function getAccessPassMetadata(
  accessPassNFTAddress: `0x${string}`,
  tokenId: bigint
): Promise<PassMetadata> {
  const metadata = await publicClient.readContract({
    address: accessPassNFTAddress,
    abi: AccessPassNFTABI,
    functionName: 'getMetadata',
    args: [tokenId],
  })

  return metadata as PassMetadata
}

// Check if access pass can be transferred
async function isAccessPassTransferable(
  accessPassNFTAddress: `0x${string}`,
  tokenId: bigint
) {
  const transferable = await publicClient.readContract({
    address: accessPassNFTAddress,
    abi: AccessPassNFTABI,
    functionName: 'isTransferable',
    args: [tokenId],
  })

  return transferable
}
```

### Discover User's Access Passes via Events

```typescript
const accessPassMintedAbi = parseAbiItem(
  'event AccessPassMinted(uint256 indexed tokenId, address indexed recipient, uint256 indexed tierId)'
)

async function getUserAccessPasses(
  accessPassNFTAddress: `0x${string}`,
  userAddress: `0x${string}`
) {
  // Get all mints to this user
  const logs = await publicClient.getLogs({
    address: accessPassNFTAddress,
    event: accessPassMintedAbi,
    args: {
      recipient: userAddress,
    },
    fromBlock: 0n,
    toBlock: 'latest',
  })

  // Verify current ownership (user might have transferred)
  const passes = await Promise.all(
    logs.map(async (log) => {
      const tokenId = log.args.tokenId!
      try {
        const owner = await publicClient.readContract({
          address: accessPassNFTAddress,
          abi: AccessPassNFTABI,
          functionName: 'ownerOf',
          args: [tokenId],
        })

        if (owner.toLowerCase() === userAddress.toLowerCase()) {
          const metadata = await getAccessPassMetadata(accessPassNFTAddress, tokenId)
          const transferable = await isAccessPassTransferable(accessPassNFTAddress, tokenId)

          return {
            tokenId,
            tierId: metadata.tierId,
            mintTimestamp: metadata.mintTimestamp,
            transferable,
          }
        }
      } catch {
        // Token might have been burned or doesn't exist
      }
      return null
    })
  )

  return passes.filter((p) => p !== null)
}
```

---

## 6. Marketplace Integration

### Create a Listing

```typescript
import { MarketplaceABI } from './config/abis'

async function createListing(
  eventAddress: `0x${string}`,
  tierId: bigint,
  quantity: bigint,
  pricePerUnit: bigint,
  expirationTime: bigint // Unix timestamp
) {
  const walletClient = getWalletClient()
  const [account] = await walletClient.getAddresses()

  // First, approve marketplace to transfer tickets
  const approvalHash = await walletClient.writeContract({
    address: eventAddress,
    abi: EventABI,
    functionName: 'setApprovalForAll',
    args: [CONTRACT_ADDRESSES.marketplace, true],
    account,
  })
  await publicClient.waitForTransactionReceipt({ hash: approvalHash })

  // Create listing
  const hash = await walletClient.writeContract({
    address: CONTRACT_ADDRESSES.marketplace,
    abi: MarketplaceABI,
    functionName: 'createListing',
    args: [eventAddress, tierId, quantity, pricePerUnit, expirationTime],
    account,
  })

  const receipt = await publicClient.waitForTransactionReceipt({ hash })

  return { hash, receipt }
}

// Example usage
const listing = await createListing(
  '0x...eventAddress',
  1n, // Tier ID
  2n, // 2 tickets
  parseEther('0.15'), // 0.15 QIE per ticket
  BigInt(Math.floor(Date.now() / 1000) + 7 * 24 * 60 * 60) // 7 days from now
)
```

### Get Listings

```typescript
interface Listing {
  seller: `0x${string}`
  eventContract: `0x${string}`
  tokenId: bigint
  quantity: bigint
  pricePerUnit: bigint
  expirationTime: bigint
  active: boolean
}

async function getListing(listingId: bigint): Promise<Listing> {
  const listing = await publicClient.readContract({
    address: CONTRACT_ADDRESSES.marketplace,
    abi: MarketplaceABI,
    functionName: 'getListing',
    args: [listingId],
  })

  return listing as Listing
}

async function getActiveListingsForEvent(eventAddress: `0x${string}`) {
  const listingIds = await publicClient.readContract({
    address: CONTRACT_ADDRESSES.marketplace,
    abi: MarketplaceABI,
    functionName: 'getActiveListingsForEvent',
    args: [eventAddress],
  })

  const listings = await Promise.all(
    (listingIds as bigint[]).map(async (id) => {
      const listing = await getListing(id)
      return { listingId: id, ...listing }
    })
  )

  return listings
}

async function getListingsBySeller(sellerAddress: `0x${string}`) {
  const listingIds = await publicClient.readContract({
    address: CONTRACT_ADDRESSES.marketplace,
    abi: MarketplaceABI,
    functionName: 'getListingsBySeller',
    args: [sellerAddress],
  })

  const listings = await Promise.all(
    (listingIds as bigint[]).map(async (id) => {
      const listing = await getListing(id)
      return { listingId: id, ...listing }
    })
  )

  return listings
}
```

### Buy from Marketplace

```typescript
async function buyListing(listingId: bigint, quantity: bigint) {
  const walletClient = getWalletClient()
  const [account] = await walletClient.getAddresses()

  // Get listing to calculate price
  const listing = await getListing(listingId)
  const totalPrice = listing.pricePerUnit * quantity

  const hash = await walletClient.writeContract({
    address: CONTRACT_ADDRESSES.marketplace,
    abi: MarketplaceABI,
    functionName: 'buyListing',
    args: [listingId, quantity],
    value: totalPrice,
    account,
  })

  const receipt = await publicClient.waitForTransactionReceipt({ hash })

  return { hash, receipt }
}
```

### Cancel/Update Listing

```typescript
async function cancelListing(listingId: bigint) {
  const walletClient = getWalletClient()
  const [account] = await walletClient.getAddresses()

  const hash = await walletClient.writeContract({
    address: CONTRACT_ADDRESSES.marketplace,
    abi: MarketplaceABI,
    functionName: 'cancelListing',
    args: [listingId],
    account,
  })

  const receipt = await publicClient.waitForTransactionReceipt({ hash })
  return { hash, receipt }
}

async function updateListingPrice(listingId: bigint, newPrice: bigint) {
  const walletClient = getWalletClient()
  const [account] = await walletClient.getAddresses()

  const hash = await walletClient.writeContract({
    address: CONTRACT_ADDRESSES.marketplace,
    abi: MarketplaceABI,
    functionName: 'updateListingPrice',
    args: [listingId, newPrice],
    account,
  })

  const receipt = await publicClient.waitForTransactionReceipt({ hash })
  return { hash, receipt }
}
```

### Watch Marketplace Events

```typescript
const listingCreatedAbi = parseAbiItem(
  'event ListingCreated(uint256 indexed listingId, address indexed seller, address indexed eventContract, uint256 tokenId, uint256 quantity, uint256 pricePerUnit, uint256 expirationTime)'
)

const listingPurchasedAbi = parseAbiItem(
  'event ListingPurchased(uint256 indexed listingId, address indexed buyer, uint256 quantity, uint256 totalPrice, uint256 royaltyPaid, address royaltyReceiver)'
)

async function watchMarketplaceActivity(
  onListingCreated: (listing: any) => void,
  onListingPurchased: (purchase: any) => void
) {
  const unwatchCreated = publicClient.watchEvent({
    address: CONTRACT_ADDRESSES.marketplace,
    event: listingCreatedAbi,
    onLogs: (logs) => logs.forEach((log) => onListingCreated(log.args)),
  })

  const unwatchPurchased = publicClient.watchEvent({
    address: CONTRACT_ADDRESSES.marketplace,
    event: listingPurchasedAbi,
    onLogs: (logs) => logs.forEach((log) => onListingPurchased(log.args)),
  })

  return () => {
    unwatchCreated()
    unwatchPurchased()
  }
}
```

---

## 7. Events Reference

### EventFactory Events

| Event | Parameters | When Emitted |
|-------|------------|--------------|
| `EventCreated` | `eventAddress`, `creator`, `name`, `eventId` | New event contract deployed |

### Event Contract Events

| Event | Parameters | When Emitted |
|-------|------------|--------------|
| `TierCreated` | `tierId`, `tierName`, `price`, `maxSupply` | New tier added |
| `TierUpdated` | `tierId`, `newPrice`, `newMaxSupply` | Tier price/supply changed |
| `TierActiveStatusChanged` | `tierId`, `active` | Tier enabled/disabled |
| `TicketsPurchased` | `buyer`, `tierId`, `quantity`, `totalPaid` | Tickets bought |
| `TicketRedeemed` | `ticketHolder`, `tierId`, `accessPassId` | Ticket redeemed for access pass |
| `GatekeeperAdded` | `gatekeeper` | New gatekeeper authorized |
| `GatekeeperRemoved` | `gatekeeper` | Gatekeeper removed |
| `FundsWithdrawn` | `to`, `amount` | Organizer withdrew funds |

### Marketplace Events

| Event | Parameters | When Emitted |
|-------|------------|--------------|
| `ListingCreated` | `listingId`, `seller`, `eventContract`, `tokenId`, `quantity`, `pricePerUnit`, `expirationTime` | New listing created |
| `ListingCancelled` | `listingId` | Listing cancelled |
| `ListingPriceUpdated` | `listingId`, `newPrice` | Listing price changed |
| `ListingPurchased` | `listingId`, `buyer`, `quantity`, `totalPrice`, `royaltyPaid`, `royaltyReceiver` | Tickets bought from listing |

### AccessPassNFT Events

| Event | Parameters | When Emitted |
|-------|------------|--------------|
| `AccessPassMinted` | `tokenId`, `recipient`, `tierId` | Access pass created on redemption |

---

## 8. Error Handling

### Custom Errors

The contracts use custom errors for gas-efficient error handling. Here's how to decode them:

```typescript
import { decodeErrorResult } from 'viem'

// Error definitions
const errors = {
  // Event Errors
  TierNotActive: 'Tier is not active for purchases',
  TierDoesNotExist: 'Tier ID does not exist',
  TierAlreadyExists: 'Tier ID already exists',
  ExceedsMaxSupply: 'Purchase would exceed max supply',
  IncorrectPayment: 'ETH amount sent is incorrect',
  CannotReduceBelowSupply: 'Cannot reduce max supply below current sold tickets',
  SignatureExpired: 'Signature deadline has passed',
  InvalidSignature: 'Signature verification failed',
  NotGatekeeper: 'Caller is not an authorized gatekeeper',
  InsufficientTickets: 'User does not own enough tickets',
  ZeroQuantity: 'Quantity must be greater than zero',
  ZeroMaxSupply: 'Max supply must be greater than zero',

  // AccessPassNFT Errors
  TransferLocked: 'Access pass is locked (24h not elapsed)',
  NotAuthorizedMinter: 'Only Event contract can mint',
  EventContractAlreadySet: 'Event contract already configured',

  // Marketplace Errors
  ListingDoesNotExist: 'Listing ID not found',
  ListingNotActive: 'Listing is not active',
  ListingExpired: 'Listing has expired',
  InsufficientQuantity: 'Not enough tickets in listing',
  NotSeller: 'Only seller can modify listing',
  InvalidExpiration: 'Expiration must be in the future',
  ZeroPrice: 'Price must be greater than zero',

  // General Errors
  TransferFailed: 'ETH transfer failed',
  ZeroAddress: 'Address cannot be zero',
}
```

### Error Handling Example

```typescript
async function safeBuyTickets(
  eventAddress: `0x${string}`,
  tierId: bigint,
  quantity: bigint
) {
  try {
    return await buyTickets(eventAddress, tierId, quantity)
  } catch (error: any) {
    // Check for specific error types
    if (error.message?.includes('TierNotActive')) {
      throw new Error('This ticket tier is currently not available for purchase')
    }
    if (error.message?.includes('ExceedsMaxSupply')) {
      throw new Error('Not enough tickets available')
    }
    if (error.message?.includes('IncorrectPayment')) {
      throw new Error('Please send the exact payment amount')
    }
    // Re-throw unknown errors
    throw error
  }
}
```

### Simulating Transactions

Use viem's `simulateContract` to check for errors before sending:

```typescript
async function simulateBuyTickets(
  eventAddress: `0x${string}`,
  tierId: bigint,
  quantity: bigint,
  userAddress: `0x${string}`
) {
  const tier = await getTier(eventAddress, tierId)
  const totalPrice = tier.price * quantity

  try {
    const { request } = await publicClient.simulateContract({
      address: eventAddress,
      abi: EventABI,
      functionName: 'buyTickets',
      args: [tierId, quantity],
      value: totalPrice,
      account: userAddress,
    })

    return { success: true, request }
  } catch (error: any) {
    return { success: false, error: error.message }
  }
}
```

---

## Appendix: Complete Type Definitions

```typescript
// types.ts
export interface EventConfig {
  name: string
  symbol: string
  baseURI: string
  royaltyBps: bigint
}

export interface TierConfig {
  tierId: bigint
  tierName: string
  price: bigint
  maxSupply: bigint
}

export interface Tier {
  price: bigint
  maxSupply: bigint
  tierName: string
  active: boolean
}

export interface Listing {
  seller: `0x${string}`
  eventContract: `0x${string}`
  tokenId: bigint
  quantity: bigint
  pricePerUnit: bigint
  expirationTime: bigint
  active: boolean
}

export interface PassMetadata {
  tierId: bigint
  mintTimestamp: bigint
}

export interface EventDetails {
  name: string
  symbol: string
  accessPassNFT: `0x${string}`
}

export interface UserTicket {
  tierId: bigint
  tierName: string
  balance: bigint
}

export interface UserAccessPass {
  tokenId: bigint
  tierId: bigint
  mintTimestamp: bigint
  transferable: boolean
}
```
