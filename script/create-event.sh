#!/bin/bash

# Create Event Script
# Usage: ./script/create-event.sh

set -e

FACTORY_ADDRESS="0x5120F677C9a453AC960eCA1fb274D25D96aAAdC5"
RPC_URL="https://rpc1testnet.qie.digital"

# Check if PRIVATE_KEY is set
if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY environment variable not set"
    exit 1
fi

echo "=== Creating Event ==="
echo "Factory: $FACTORY_ADDRESS"
echo "RPC: $RPC_URL"

# Encode the createEvent call
# createEvent((string,string,string,uint96),(uint256,string,uint256,uint256)[],address[])
CALLDATA=$(cast calldata \
    "createEvent((string,string,string,uint96),(uint256,string,uint256,uint256)[],address[])" \
    "(Test Event,TE,https://api.example.com/,500)" \
    "[(1,VIP,100000000000000000,100)]" \
    "[]")

echo "Calldata: $CALLDATA"

# Send transaction
echo ""
echo "Sending transaction..."
TX_HASH=$(cast send \
    --private-key $PRIVATE_KEY \
    --rpc-url $RPC_URL \
    --gas-limit 4000000 \
    --legacy \
    $FACTORY_ADDRESS \
    $CALLDATA)

echo "Transaction sent!"
echo "$TX_HASH"

# Wait and get receipt
echo ""
echo "Waiting for confirmation..."
sleep 5

cast receipt $TX_HASH --rpc-url $RPC_URL

# Get the created event address from factory
echo ""
echo "=== Getting Event Details ==="
TOTAL_EVENTS=$(cast call $FACTORY_ADDRESS "totalEvents()" --rpc-url $RPC_URL)
echo "Total events: $TOTAL_EVENTS"

# Get latest event (index = totalEvents - 1)
EVENT_ID=$((TOTAL_EVENTS - 1))
EVENT_ADDRESS=$(cast call $FACTORY_ADDRESS "getEvent(uint256)" $EVENT_ID --rpc-url $RPC_URL)
echo "Event address: $EVENT_ADDRESS"

# Get AccessPassNFT from event
ACCESS_PASS=$(cast call $EVENT_ADDRESS "accessPassNFT()" --rpc-url $RPC_URL)
echo "AccessPassNFT: $ACCESS_PASS"
