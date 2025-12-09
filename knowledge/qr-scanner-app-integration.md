# QR Scanner App Integration Guide

This guide is for frontend developers building the QR code scanner application for ticket redemption at event venues.

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [QR Code Generation (User Wallet)](#2-qr-code-generation-user-wallet)
3. [QR Code Scanning & Redemption (Gatekeeper App)](#3-qr-code-scanning--redemption-gatekeeper-app)
4. [Gatekeeper Management](#4-gatekeeper-management)
5. [AccessPassNFT Verification](#5-accesspassnft-verification)
6. [Complete Code Examples](#6-complete-code-examples)
7. [Error Handling](#7-error-handling)

---

## 1. System Overview

### How Ticket Redemption Works

```
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│   User's Wallet     │     │   QR Scanner App    │     │   Event Contract    │
│      (Mobile)       │     │    (Gatekeeper)     │     │    (Blockchain)     │
└──────────┬──────────┘     └──────────┬──────────┘     └──────────┬──────────┘
           │                           │                           │
           │ 1. Sign EIP-712 message   │                           │
           │    (offline capable)      │                           │
           │                           │                           │
           │ 2. Generate QR code       │                           │
           │    with signature         │                           │
           ├──────────────────────────>│                           │
           │ 3. Scan QR code           │                           │
           │                           │                           │
           │                           │ 4. Verify ticket balance  │
           │                           ├──────────────────────────>│
           │                           │<──────────────────────────┤
           │                           │                           │
           │                           │ 5. Call redeemTicket()    │
           │                           ├──────────────────────────>│
           │                           │                           │
           │                           │ 6. Ticket burned,         │
           │                           │    AccessPass minted      │
           │                           │<──────────────────────────┤
           │                           │                           │
           │ 7. Entry granted          │                           │
           │<──────────────────────────┤                           │
           │                           │                           │
```

### Key Concepts

| Term | Description |
|------|-------------|
| **Gatekeeper** | Authorized address that can call `redeemTicket()` |
| **EIP-712 Signature** | Typed structured data signature for secure redemption |
| **Nonce** | Per-user counter preventing replay attacks |
| **Deadline** | Signature expiration timestamp |
| **AccessPassNFT** | ERC-721 token minted upon successful redemption |

---

## 2. QR Code Generation (User Wallet)

The user's wallet app generates the QR code containing the signed redemption message.

### EIP-712 Domain Configuration

```typescript
import { createWalletClient, custom } from 'viem'
import { qieTestnet } from './config/chains'

// Domain must match the Event contract's EIP-712 configuration
function getEIP712Domain(eventAddress: `0x${string}`) {
  return {
    name: 'EventTicket',
    version: '1',
    chainId: 1983, // QIE Testnet
    verifyingContract: eventAddress,
  }
}
```

### Message Type Definition

```typescript
// The REDEMPTION_TYPEHASH from the contract:
// keccak256("RedeemTicket(address ticketHolder,uint256 tierId,uint256 nonce,uint256 deadline)")

const REDEMPTION_TYPES = {
  RedeemTicket: [
    { name: 'ticketHolder', type: 'address' },
    { name: 'tierId', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
  ],
} as const
```

### Get User's Current Nonce

```typescript
import { EventABI } from './config/abis'
import { publicClient } from './config/client'

async function getUserNonce(
  eventAddress: `0x${string}`,
  userAddress: `0x${string}`
): Promise<bigint> {
  // The nonces function is inherited from NoncesUpgradeable
  const nonce = await publicClient.readContract({
    address: eventAddress,
    abi: EventABI,
    functionName: 'nonces',
    args: [userAddress],
  })

  return nonce
}
```

### Generate Signed QR Code Data

```typescript
interface QRCodeData {
  eventAddress: `0x${string}`
  ticketHolder: `0x${string}`
  tierId: bigint
  deadline: bigint
  signature: `0x${string}`
}

async function generateRedemptionQRData(
  eventAddress: `0x${string}`,
  tierId: bigint,
  validityMinutes: number = 5 // How long the QR code is valid
): Promise<QRCodeData> {
  const walletClient = createWalletClient({
    chain: qieTestnet,
    transport: custom(window.ethereum),
  })

  const [ticketHolder] = await walletClient.getAddresses()

  // Get current nonce
  const nonce = await getUserNonce(eventAddress, ticketHolder)

  // Set deadline (e.g., 5 minutes from now)
  const deadline = BigInt(Math.floor(Date.now() / 1000) + validityMinutes * 60)

  // Prepare the message
  const message = {
    ticketHolder,
    tierId,
    nonce,
    deadline,
  }

  // Sign with EIP-712
  const signature = await walletClient.signTypedData({
    account: ticketHolder,
    domain: getEIP712Domain(eventAddress),
    types: REDEMPTION_TYPES,
    primaryType: 'RedeemTicket',
    message,
  })

  return {
    eventAddress,
    ticketHolder,
    tierId,
    deadline,
    signature,
  }
}
```

### Encode QR Code

```typescript
// Convert QR data to JSON string for QR encoding
function encodeQRData(data: QRCodeData): string {
  return JSON.stringify({
    e: data.eventAddress,      // event address
    h: data.ticketHolder,      // ticket holder
    t: data.tierId.toString(), // tier ID (as string for JSON)
    d: data.deadline.toString(), // deadline (as string)
    s: data.signature,         // signature
  })
}

// Example: Generate QR code
async function showRedemptionQR(eventAddress: `0x${string}`, tierId: bigint) {
  const qrData = await generateRedemptionQRData(eventAddress, tierId, 5)
  const qrString = encodeQRData(qrData)

  // Use your preferred QR code library (e.g., qrcode, react-qr-code)
  // QRCode.toCanvas(canvas, qrString)

  return qrString
}
```

### Display Remaining Time

```typescript
function getRemainingTime(deadline: bigint): number {
  const now = BigInt(Math.floor(Date.now() / 1000))
  const remaining = Number(deadline - now)
  return Math.max(0, remaining)
}

// Show countdown in UI
function formatCountdown(seconds: number): string {
  const mins = Math.floor(seconds / 60)
  const secs = seconds % 60
  return `${mins}:${secs.toString().padStart(2, '0')}`
}
```

---

## 3. QR Code Scanning & Redemption (Gatekeeper App)

The gatekeeper app scans QR codes and processes redemptions.

### Parse QR Code Data

```typescript
interface ParsedQRData {
  eventAddress: `0x${string}`
  ticketHolder: `0x${string}`
  tierId: bigint
  deadline: bigint
  signature: `0x${string}`
}

function parseQRCode(qrString: string): ParsedQRData {
  const data = JSON.parse(qrString)

  return {
    eventAddress: data.e as `0x${string}`,
    ticketHolder: data.h as `0x${string}`,
    tierId: BigInt(data.t),
    deadline: BigInt(data.d),
    signature: data.s as `0x${string}`,
  }
}
```

### Pre-Redemption Validation

Before calling the contract, validate locally:

```typescript
import { EventABI } from './config/abis'

interface ValidationResult {
  valid: boolean
  error?: string
  ticketBalance?: bigint
  tierName?: string
}

async function validateRedemption(data: ParsedQRData): Promise<ValidationResult> {
  const now = BigInt(Math.floor(Date.now() / 1000))

  // 1. Check if signature expired
  if (data.deadline < now) {
    return { valid: false, error: 'QR code has expired. Ask user to generate a new one.' }
  }

  // 2. Check ticket ownership
  const balance = await publicClient.readContract({
    address: data.eventAddress,
    abi: EventABI,
    functionName: 'balanceOf',
    args: [data.ticketHolder, data.tierId],
  })

  if (balance === 0n) {
    return { valid: false, error: 'User does not own any tickets for this tier.' }
  }

  // 3. Get tier info for display
  const tier = await publicClient.readContract({
    address: data.eventAddress,
    abi: EventABI,
    functionName: 'getTier',
    args: [data.tierId],
  })

  return {
    valid: true,
    ticketBalance: balance,
    tierName: (tier as any).tierName,
  }
}
```

### Execute Redemption

```typescript
import { getWalletClient, publicClient } from './config/client'
import { EventABI } from './config/abis'
import { parseAbiItem } from 'viem'

interface RedemptionResult {
  success: boolean
  transactionHash?: `0x${string}`
  accessPassId?: bigint
  error?: string
}

async function redeemTicket(data: ParsedQRData): Promise<RedemptionResult> {
  try {
    // Validate first
    const validation = await validateRedemption(data)
    if (!validation.valid) {
      return { success: false, error: validation.error }
    }

    const walletClient = getWalletClient()
    const [gatekeeperAddress] = await walletClient.getAddresses()

    // Check if caller is gatekeeper
    const isGatekeeper = await publicClient.readContract({
      address: data.eventAddress,
      abi: EventABI,
      functionName: 'isGatekeeper',
      args: [gatekeeperAddress],
    })

    if (!isGatekeeper) {
      return { success: false, error: 'Your wallet is not authorized as a gatekeeper.' }
    }

    // Execute redemption
    const hash = await walletClient.writeContract({
      address: data.eventAddress,
      abi: EventABI,
      functionName: 'redeemTicket',
      args: [data.ticketHolder, data.tierId, data.deadline, data.signature],
      account: gatekeeperAddress,
    })

    // Wait for confirmation
    const receipt = await publicClient.waitForTransactionReceipt({ hash })

    // Extract AccessPassId from TicketRedeemed event
    const ticketRedeemedAbi = parseAbiItem(
      'event TicketRedeemed(address indexed ticketHolder, uint256 indexed tierId, uint256 accessPassId)'
    )

    const redeemedLog = receipt.logs.find((log) => {
      try {
        // Check if this log matches TicketRedeemed event
        return log.topics[0] === '0x...' // Use actual topic hash
      } catch {
        return false
      }
    })

    // Parse accessPassId from logs (simplified - use proper decoding)
    let accessPassId: bigint | undefined
    for (const log of receipt.logs) {
      // Look for AccessPassMinted event
      if (log.data && log.data.length > 2) {
        // The accessPassId would be in the log data
        // This is simplified - use proper ABI decoding
      }
    }

    return {
      success: true,
      transactionHash: hash,
      accessPassId,
    }
  } catch (error: any) {
    // Parse error message
    if (error.message?.includes('SignatureExpired')) {
      return { success: false, error: 'Signature has expired. Ask user to generate a new QR.' }
    }
    if (error.message?.includes('InvalidSignature')) {
      return { success: false, error: 'Invalid signature. QR code may be corrupted.' }
    }
    if (error.message?.includes('InsufficientTickets')) {
      return { success: false, error: 'User no longer owns this ticket.' }
    }
    if (error.message?.includes('NotGatekeeper')) {
      return { success: false, error: 'You are not authorized to redeem tickets.' }
    }

    return { success: false, error: error.message || 'Unknown error occurred' }
  }
}
```

### Complete Scan-to-Redemption Flow

```typescript
async function handleQRScan(qrString: string) {
  // 1. Parse QR
  let data: ParsedQRData
  try {
    data = parseQRCode(qrString)
  } catch {
    showError('Invalid QR code format')
    return
  }

  // 2. Show validation status
  showLoading('Validating ticket...')

  const validation = await validateRedemption(data)
  if (!validation.valid) {
    showError(validation.error!)
    return
  }

  // 3. Show ticket info and confirm
  const confirmed = await showConfirmation({
    ticketHolder: data.ticketHolder,
    tierName: validation.tierName,
    ticketCount: validation.ticketBalance,
  })

  if (!confirmed) return

  // 4. Execute redemption
  showLoading('Processing redemption...')

  const result = await redeemTicket(data)

  if (result.success) {
    showSuccess({
      message: 'Ticket redeemed successfully!',
      accessPassId: result.accessPassId,
      transactionHash: result.transactionHash,
    })
  } else {
    showError(result.error!)
  }
}
```

---

## 4. Gatekeeper Management

### Check Gatekeeper Status

```typescript
async function isAddressGatekeeper(
  eventAddress: `0x${string}`,
  address: `0x${string}`
): Promise<boolean> {
  const isGatekeeper = await publicClient.readContract({
    address: eventAddress,
    abi: EventABI,
    functionName: 'isGatekeeper',
    args: [address],
  })

  return isGatekeeper as boolean
}

// Check current wallet
async function checkCurrentWalletIsGatekeeper(eventAddress: `0x${string}`) {
  const walletClient = getWalletClient()
  const [address] = await walletClient.getAddresses()

  return isAddressGatekeeper(eventAddress, address)
}
```

### Admin: Add/Remove Gatekeepers

Only the event owner can manage gatekeepers:

```typescript
// Add gatekeeper (event owner only)
async function addGatekeeper(
  eventAddress: `0x${string}`,
  gatekeeperAddress: `0x${string}`
) {
  const walletClient = getWalletClient()
  const [account] = await walletClient.getAddresses()

  const hash = await walletClient.writeContract({
    address: eventAddress,
    abi: EventABI,
    functionName: 'addGatekeeper',
    args: [gatekeeperAddress],
    account,
  })

  return publicClient.waitForTransactionReceipt({ hash })
}

// Remove gatekeeper (event owner only)
async function removeGatekeeper(
  eventAddress: `0x${string}`,
  gatekeeperAddress: `0x${string}`
) {
  const walletClient = getWalletClient()
  const [account] = await walletClient.getAddresses()

  const hash = await walletClient.writeContract({
    address: eventAddress,
    abi: EventABI,
    functionName: 'removeGatekeeper',
    args: [gatekeeperAddress],
    account,
  })

  return publicClient.waitForTransactionReceipt({ hash })
}
```

### Watch Gatekeeper Events

```typescript
const gatekeeperAddedAbi = parseAbiItem('event GatekeeperAdded(address indexed gatekeeper)')
const gatekeeperRemovedAbi = parseAbiItem('event GatekeeperRemoved(address indexed gatekeeper)')

async function getGatekeeperHistory(eventAddress: `0x${string}`) {
  const [addedLogs, removedLogs] = await Promise.all([
    publicClient.getLogs({
      address: eventAddress,
      event: gatekeeperAddedAbi,
      fromBlock: 0n,
      toBlock: 'latest',
    }),
    publicClient.getLogs({
      address: eventAddress,
      event: gatekeeperRemovedAbi,
      fromBlock: 0n,
      toBlock: 'latest',
    }),
  ])

  // Build current gatekeeper set
  const gatekeepers = new Set<string>()

  // Process in chronological order
  const allEvents = [
    ...addedLogs.map((l) => ({ type: 'add', address: l.args.gatekeeper, block: l.blockNumber })),
    ...removedLogs.map((l) => ({ type: 'remove', address: l.args.gatekeeper, block: l.blockNumber })),
  ].sort((a, b) => Number(a.block! - b.block!))

  for (const event of allEvents) {
    if (event.type === 'add') {
      gatekeepers.add(event.address!.toLowerCase())
    } else {
      gatekeepers.delete(event.address!.toLowerCase())
    }
  }

  return Array.from(gatekeepers)
}
```

---

## 5. AccessPassNFT Verification

After redemption, verify access passes at additional checkpoints.

### Check Access Pass Ownership

```typescript
import { AccessPassNFTABI } from './config/abis'

async function verifyAccessPass(
  accessPassNFTAddress: `0x${string}`,
  userAddress: `0x${string}`
): Promise<{ hasAccess: boolean; passCount: bigint }> {
  const balance = await publicClient.readContract({
    address: accessPassNFTAddress,
    abi: AccessPassNFTABI,
    functionName: 'balanceOf',
    args: [userAddress],
  })

  return {
    hasAccess: balance > 0n,
    passCount: balance,
  }
}
```

### Get Access Pass Details

```typescript
interface AccessPassDetails {
  tokenId: bigint
  owner: `0x${string}`
  tierId: bigint
  mintTimestamp: bigint
  transferable: boolean
  transferUnlockTime: bigint
}

async function getAccessPassDetails(
  accessPassNFTAddress: `0x${string}`,
  tokenId: bigint
): Promise<AccessPassDetails> {
  const [owner, metadata, transferable, unlockTime] = await Promise.all([
    publicClient.readContract({
      address: accessPassNFTAddress,
      abi: AccessPassNFTABI,
      functionName: 'ownerOf',
      args: [tokenId],
    }),
    publicClient.readContract({
      address: accessPassNFTAddress,
      abi: AccessPassNFTABI,
      functionName: 'getMetadata',
      args: [tokenId],
    }),
    publicClient.readContract({
      address: accessPassNFTAddress,
      abi: AccessPassNFTABI,
      functionName: 'isTransferable',
      args: [tokenId],
    }),
    publicClient.readContract({
      address: accessPassNFTAddress,
      abi: AccessPassNFTABI,
      functionName: 'transferUnlockTime',
      args: [tokenId],
    }),
  ])

  const typedMetadata = metadata as { tierId: bigint; mintTimestamp: bigint }

  return {
    tokenId,
    owner: owner as `0x${string}`,
    tierId: typedMetadata.tierId,
    mintTimestamp: typedMetadata.mintTimestamp,
    transferable: transferable as boolean,
    transferUnlockTime: unlockTime as bigint,
  }
}
```

### Verify Access Pass for Specific Tier

```typescript
async function verifyAccessForTier(
  accessPassNFTAddress: `0x${string}`,
  userAddress: `0x${string}`,
  requiredTierId: bigint
): Promise<{ valid: boolean; tokenId?: bigint }> {
  // Get user's access passes via events
  const accessPassMintedAbi = parseAbiItem(
    'event AccessPassMinted(uint256 indexed tokenId, address indexed recipient, uint256 indexed tierId)'
  )

  const logs = await publicClient.getLogs({
    address: accessPassNFTAddress,
    event: accessPassMintedAbi,
    args: {
      recipient: userAddress,
      tierId: requiredTierId,
    },
    fromBlock: 0n,
    toBlock: 'latest',
  })

  // Check if user still owns any of these passes
  for (const log of logs) {
    const tokenId = log.args.tokenId!
    try {
      const owner = await publicClient.readContract({
        address: accessPassNFTAddress,
        abi: AccessPassNFTABI,
        functionName: 'ownerOf',
        args: [tokenId],
      })

      if ((owner as string).toLowerCase() === userAddress.toLowerCase()) {
        return { valid: true, tokenId }
      }
    } catch {
      // Token doesn't exist or was burned
    }
  }

  return { valid: false }
}
```

---

## 6. Complete Code Examples

### User App: Full QR Generation Flow

```typescript
// UserQRGenerator.tsx
import { useState, useEffect } from 'react'
import QRCode from 'qrcode'

interface Props {
  eventAddress: `0x${string}`
  tierId: bigint
}

export function UserQRGenerator({ eventAddress, tierId }: Props) {
  const [qrDataUrl, setQrDataUrl] = useState<string>('')
  const [expiresIn, setExpiresIn] = useState<number>(0)
  const [error, setError] = useState<string>('')

  const generateQR = async () => {
    try {
      setError('')

      // Generate signed QR data
      const qrData = await generateRedemptionQRData(eventAddress, tierId, 5)
      const qrString = encodeQRData(qrData)

      // Generate QR code image
      const dataUrl = await QRCode.toDataURL(qrString, {
        width: 300,
        margin: 2,
        color: { dark: '#000000', light: '#ffffff' },
      })

      setQrDataUrl(dataUrl)
      setExpiresIn(getRemainingTime(qrData.deadline))
    } catch (err: any) {
      setError(err.message || 'Failed to generate QR code')
    }
  }

  // Countdown timer
  useEffect(() => {
    if (expiresIn <= 0) return

    const timer = setInterval(() => {
      setExpiresIn((prev) => {
        if (prev <= 1) {
          clearInterval(timer)
          return 0
        }
        return prev - 1
      })
    }, 1000)

    return () => clearInterval(timer)
  }, [expiresIn])

  return (
    <div>
      {error && <div className="error">{error}</div>}

      {qrDataUrl && expiresIn > 0 ? (
        <div>
          <img src={qrDataUrl} alt="Redemption QR Code" />
          <p>Expires in: {formatCountdown(expiresIn)}</p>
        </div>
      ) : (
        <button onClick={generateQR}>Generate QR Code</button>
      )}

      {expiresIn === 0 && qrDataUrl && (
        <div>
          <p>QR code expired</p>
          <button onClick={generateQR}>Generate New QR</button>
        </div>
      )}
    </div>
  )
}
```

### Gatekeeper App: Full Scanner Flow

```typescript
// GatekeeperScanner.tsx
import { useState } from 'react'
import { Html5QrcodeScanner } from 'html5-qrcode'

interface Props {
  eventAddress: `0x${string}`
}

export function GatekeeperScanner({ eventAddress }: Props) {
  const [status, setStatus] = useState<'idle' | 'validating' | 'confirming' | 'processing'>('idle')
  const [ticketInfo, setTicketInfo] = useState<any>(null)
  const [result, setResult] = useState<any>(null)

  const handleScan = async (qrString: string) => {
    try {
      // Parse QR
      const data = parseQRCode(qrString)

      // Verify it's for the correct event
      if (data.eventAddress.toLowerCase() !== eventAddress.toLowerCase()) {
        setResult({ success: false, error: 'QR code is for a different event' })
        return
      }

      // Validate
      setStatus('validating')
      const validation = await validateRedemption(data)

      if (!validation.valid) {
        setResult({ success: false, error: validation.error })
        setStatus('idle')
        return
      }

      // Show confirmation
      setTicketInfo({
        holder: data.ticketHolder,
        tier: validation.tierName,
        balance: validation.ticketBalance,
        data,
      })
      setStatus('confirming')
    } catch (err: any) {
      setResult({ success: false, error: 'Invalid QR code' })
      setStatus('idle')
    }
  }

  const confirmRedemption = async () => {
    setStatus('processing')
    const redemptionResult = await redeemTicket(ticketInfo.data)
    setResult(redemptionResult)
    setStatus('idle')
    setTicketInfo(null)
  }

  const cancelRedemption = () => {
    setTicketInfo(null)
    setStatus('idle')
  }

  return (
    <div>
      {status === 'idle' && !result && (
        <div id="qr-reader" />
        // Initialize Html5QrcodeScanner on mount
      )}

      {status === 'validating' && <div>Validating ticket...</div>}

      {status === 'confirming' && ticketInfo && (
        <div>
          <h3>Confirm Redemption</h3>
          <p>Holder: {ticketInfo.holder}</p>
          <p>Tier: {ticketInfo.tier}</p>
          <p>Tickets: {ticketInfo.balance.toString()}</p>
          <button onClick={confirmRedemption}>Confirm Entry</button>
          <button onClick={cancelRedemption}>Cancel</button>
        </div>
      )}

      {status === 'processing' && <div>Processing redemption...</div>}

      {result && (
        <div className={result.success ? 'success' : 'error'}>
          {result.success ? (
            <div>
              <h3>Entry Granted!</h3>
              <p>Access Pass ID: {result.accessPassId?.toString()}</p>
              <button onClick={() => setResult(null)}>Scan Next</button>
            </div>
          ) : (
            <div>
              <h3>Error</h3>
              <p>{result.error}</p>
              <button onClick={() => setResult(null)}>Try Again</button>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
```

---

## 7. Error Handling

### Error Reference

| Error | Cause | User Message |
|-------|-------|--------------|
| `SignatureExpired` | Deadline passed | "QR code expired. Please generate a new one." |
| `InvalidSignature` | Signature doesn't match | "Invalid QR code. Please regenerate." |
| `InsufficientTickets` | User sold/transferred ticket | "No ticket found. User may have transferred it." |
| `NotGatekeeper` | Caller not authorized | "You are not authorized to scan tickets." |
| `TierDoesNotExist` | Invalid tier ID | "Invalid ticket tier." |

### Error Handling Utility

```typescript
function getRedemptionErrorMessage(error: any): string {
  const errorMessages: Record<string, string> = {
    SignatureExpired: 'QR code has expired. Ask the user to generate a new one.',
    InvalidSignature: 'Invalid QR code. It may be corrupted or tampered with.',
    InsufficientTickets: 'User does not own this ticket anymore.',
    NotGatekeeper: 'Your wallet is not authorized as a gatekeeper for this event.',
    TierDoesNotExist: 'Invalid ticket tier in QR code.',
  }

  for (const [key, message] of Object.entries(errorMessages)) {
    if (error.message?.includes(key)) {
      return message
    }
  }

  return 'An unexpected error occurred. Please try again.'
}
```

---

## Appendix: Security Considerations

### For User Wallet App

1. **Short expiry times**: Keep deadline short (5-10 minutes) to minimize risk if QR is photographed
2. **Single-use**: Each QR code uses a nonce, so it can only be used once
3. **No private keys in QR**: Only the signature is encoded, not the private key

### For Gatekeeper App

1. **Verify event address**: Always check QR code is for the correct event
2. **Check ticket balance before confirming**: User might have transferred the ticket
3. **Network verification**: Ensure connected to QIE Testnet (chain ID 1983)
4. **Secure wallet**: Gatekeeper wallet should be secured and dedicated to this purpose

### For Both Apps

1. **HTTPS only**: All RPC calls should be over HTTPS
2. **Error handling**: Never expose raw error messages to users
3. **Transaction monitoring**: Watch for transaction failures and handle appropriately
