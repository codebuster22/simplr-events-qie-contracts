// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SimplrErrors
/// @notice Custom errors for the Event Ticketing System
library SimplrErrors {
    // ============ Event Errors ============

    /// @notice Thrown when trying to buy tickets for an inactive tier
    error TierNotActive();

    /// @notice Thrown when trying to access a tier that doesn't exist
    error TierDoesNotExist();

    /// @notice Thrown when trying to create a tier that already exists
    error TierAlreadyExists();

    /// @notice Thrown when purchase would exceed tier's max supply
    error ExceedsMaxSupply();

    /// @notice Thrown when incorrect ETH amount is sent
    error IncorrectPayment();

    /// @notice Thrown when trying to reduce max supply below current supply
    error CannotReduceBelowSupply();

    /// @notice Thrown when signature has expired
    error SignatureExpired();

    /// @notice Thrown when signature is invalid
    error InvalidSignature();

    /// @notice Thrown when caller is not a gatekeeper
    error NotGatekeeper();

    /// @notice Thrown when user doesn't own the ticket
    error InsufficientTickets();

    /// @notice Thrown when contract is already initialized
    error AlreadyInitialized();

    /// @notice Thrown when quantity is zero
    error ZeroQuantity();

    /// @notice Thrown when max supply is zero
    error ZeroMaxSupply();

    // ============ AccessPassNFT Errors ============

    /// @notice Thrown when trying to transfer a locked token
    error TransferLocked();

    /// @notice Thrown when caller is not authorized to mint
    error NotAuthorizedMinter();

    /// @notice Thrown when event contract is already set
    error EventContractAlreadySet();

    // ============ Marketplace Errors ============

    /// @notice Thrown when listing doesn't exist
    error ListingDoesNotExist();

    /// @notice Thrown when listing is not active
    error ListingNotActive();

    /// @notice Thrown when listing has expired
    error ListingExpired();

    /// @notice Thrown when quantity exceeds available
    error InsufficientQuantity();

    /// @notice Thrown when caller is not the seller
    error NotSeller();

    /// @notice Thrown when expiration time is in the past
    error InvalidExpiration();

    /// @notice Thrown when price is zero
    error ZeroPrice();

    // ============ General Errors ============

    /// @notice Thrown when ETH transfer fails
    error TransferFailed();

    /// @notice Thrown when address is zero
    error ZeroAddress();
}
