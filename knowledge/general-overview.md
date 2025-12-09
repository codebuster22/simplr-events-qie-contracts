# Event Ticketing System - General Overview

## Introduction

This document provides a high-level overview of the Event Ticketing smart contract system for frontend engineers. The system enables event creation, ticket sales, secondary marketplace trading, and secure ticket redemption using blockchain technology.

---

## System Architecture

```
                                    +------------------+
                                    |   EventFactory   |
                                    |  (Deployer)      |
                                    +--------+---------+
                                             |
                         creates (via Clone) |
                    +------------------------+------------------------+
                    |                                                 |
                    v                                                 v
          +-----------------+                               +------------------+
          |     Event       |  <------------------------->  |  AccessPassNFT   |
          |   (ERC-1155)    |       mints on redemption     |    (ERC-721)     |
          |   Tickets       |                               |   Access Pass    |
          +-----------------+                               +------------------+
                    |
                    | listed for sale
                    v
          +-----------------+
          |   Marketplace   |
          | (Secondary Mkt) |
          +-----------------+
```

---

## Contract Overview

| Contract | Type | Purpose |
|----------|------|---------|
| **EventFactory** | Singleton | Deploys new Event contracts, tracks all events |
| **Event** | Clone (per event) | ERC-1155 ticket sales, tier management, redemption |
| **AccessPassNFT** | Instance (per event) | ERC-721 access passes issued on redemption |
| **Marketplace** | Singleton | Secondary market for ticket trading |

---

## Deployed Contract Addresses (QIE Testnet)

| Contract | Address |
|----------|---------|
| EventFactory | `0x0efc2cc2a4ccd3F897076f7526951914362e1e5F` |
| Marketplace | `0x5715D2CF651DF22032CfCF041bc90a9AA68Dd03f` |
| Event Implementation | `0xa6Dc66Fce6147E78abb50F3a9Ed6A14069a0c7D1` |

---

## Network Configuration

### QIE Testnet

| Property | Value |
|----------|-------|
| Network Name | QIE Testnet |
| Chain ID | `1983` |
| RPC URL | `https://rpc1testnet.qie.digital` |
| Block Explorer | `https://testnet.qie.digital/` |
| Currency Symbol | QIE |

### viem Configuration

```typescript
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

---

## High-Level User Flows

### 1. Event Creation Flow
```
Organizer -> EventFactory.createEvent() -> New Event Contract + AccessPassNFT
```

### 2. Primary Ticket Purchase Flow
```
User -> Event.buyTickets() + ETH -> ERC-1155 Ticket Minted to User
```

### 3. Secondary Market Flow
```
Seller -> Marketplace.createListing()
Buyer -> Marketplace.buyListing() + ETH -> Ticket transferred, royalties paid
```

### 4. Ticket Redemption Flow (At Venue)
```
User signs EIP-712 message -> QR Code generated
Gatekeeper scans QR -> Event.redeemTicket()
Ticket burned -> AccessPassNFT minted to user
```

---

## Token Standards

| Token | Standard | Description |
|-------|----------|-------------|
| Event Tickets | ERC-1155 | Semi-fungible. Token ID = Tier ID. Quantity = ticket count |
| Access Pass | ERC-721 | Non-fungible. Unique per redemption. 24h transfer lock |

---

## Key Features

- **Tiered Ticketing**: Multiple ticket tiers per event (VIP, General, etc.)
- **Dynamic Pricing**: Event owners can update tier prices
- **Royalties**: ERC-2981 standard royalties on secondary sales
- **Secure Redemption**: EIP-712 signatures prevent unauthorized redemption
- **Soulbound Period**: AccessPassNFT is non-transferable for 24 hours after minting

---

## ABI Files

Frontend developers will receive JSON ABI files for all contracts:

1. `EventFactory.json` - Factory contract ABI
2. `Event.json` - Event contract ABI (includes ERC-1155)
3. `Marketplace.json` - Marketplace contract ABI
4. `AccessPassNFT.json` - Access pass contract ABI (includes ERC-721)
5. `SimplrErrors.json` - Custom errors ABI

---

## Documentation Index

| Document | Audience | Purpose |
|----------|----------|---------|
| [Main App Integration](./main-app-integration.md) | Main app developers | Create events, buy tickets, marketplace |
| [QR Scanner Integration](./qr-scanner-app-integration.md) | Scanner app developers | Ticket redemption, access verification |

---

## Quick Reference: Key Functions

### EventFactory
- `createEvent()` - Create a new event
- `getEvent(eventId)` - Get event address by ID
- `getEventsByCreator(address)` - Get all events by creator
- `totalEvents()` - Total events created

### Event
- `buyTickets(tierId, quantity)` - Purchase tickets
- `getTier(tierId)` - Get tier information
- `balanceOf(address, tierId)` - Check ticket balance
- `redeemTicket(...)` - Redeem ticket (gatekeeper only)

### Marketplace
- `createListing(...)` - List tickets for sale
- `buyListing(listingId, quantity)` - Buy from listing
- `getActiveListingsForEvent(eventContract)` - Browse event listings
- `getListing(listingId)` - Get listing details

### AccessPassNFT
- `ownerOf(tokenId)` - Check access pass owner
- `getMetadata(tokenId)` - Get pass metadata
- `isTransferable(tokenId)` - Check if transfer lock expired
