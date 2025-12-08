// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IMarketplace} from "./interfaces/IMarketplace.sol";
import {Errors} from "./libraries/Errors.sol";

/// @title Marketplace
/// @notice Secondary market for trading ERC-1155 tickets with ERC-2981 royalty support
/// @dev No protocol fees - all proceeds go to seller minus royalties
contract Marketplace is Ownable, Pausable, ReentrancyGuard, IMarketplace {
    // ============ State Variables ============

    /// @notice Array of all listings
    Listing[] private _listings;

    // ============ Constructor ============

    /// @notice Deploys the Marketplace contract
    constructor() Ownable(msg.sender) {}

    // ============ External Functions ============

    /// @inheritdoc IMarketplace
    function createListing(
        address eventContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 pricePerUnit,
        uint256 expirationTime
    ) external whenNotPaused returns (uint256 listingId) {
        if (quantity == 0) {
            revert Errors.ZeroQuantity();
        }
        if (pricePerUnit == 0) {
            revert Errors.ZeroPrice();
        }
        if (expirationTime <= block.timestamp) {
            revert Errors.InvalidExpiration();
        }

        listingId = _listings.length;

        _listings.push(Listing({
            seller: msg.sender,
            eventContract: eventContract,
            tokenId: tokenId,
            quantity: quantity,
            pricePerUnit: pricePerUnit,
            expirationTime: expirationTime,
            active: true
        }));

        emit ListingCreated(
            listingId,
            msg.sender,
            eventContract,
            tokenId,
            quantity,
            pricePerUnit,
            expirationTime
        );
    }

    /// @inheritdoc IMarketplace
    function cancelListing(uint256 listingId) external {
        if (listingId >= _listings.length) {
            revert Errors.ListingDoesNotExist();
        }

        Listing storage listing = _listings[listingId];

        if (listing.seller != msg.sender) {
            revert Errors.NotSeller();
        }

        listing.active = false;

        emit ListingCancelled(listingId);
    }

    /// @inheritdoc IMarketplace
    function updateListingPrice(uint256 listingId, uint256 newPrice) external {
        if (listingId >= _listings.length) {
            revert Errors.ListingDoesNotExist();
        }

        Listing storage listing = _listings[listingId];

        if (listing.seller != msg.sender) {
            revert Errors.NotSeller();
        }

        if (newPrice == 0) {
            revert Errors.ZeroPrice();
        }

        listing.pricePerUnit = newPrice;

        emit ListingPriceUpdated(listingId, newPrice);
    }

    /// @inheritdoc IMarketplace
    function buyListing(
        uint256 listingId,
        uint256 quantity
    ) external payable whenNotPaused nonReentrant {
        if (listingId >= _listings.length) {
            revert Errors.ListingDoesNotExist();
        }

        if (quantity == 0) {
            revert Errors.ZeroQuantity();
        }

        Listing storage listing = _listings[listingId];

        if (!listing.active) {
            revert Errors.ListingNotActive();
        }

        if (block.timestamp >= listing.expirationTime) {
            revert Errors.ListingExpired();
        }

        if (quantity > listing.quantity) {
            revert Errors.InsufficientQuantity();
        }

        uint256 totalPrice = listing.pricePerUnit * quantity;
        if (msg.value != totalPrice) {
            revert Errors.IncorrectPayment();
        }

        // Update listing
        listing.quantity -= quantity;
        if (listing.quantity == 0) {
            listing.active = false;
        }

        // Get royalty info
        (address royaltyReceiver, uint256 royaltyAmount) = IERC2981(listing.eventContract)
            .royaltyInfo(listing.tokenId, totalPrice);

        // Calculate seller proceeds
        uint256 sellerProceeds = totalPrice - royaltyAmount;

        // Transfer tickets from seller to buyer
        IERC1155(listing.eventContract).safeTransferFrom(
            listing.seller,
            msg.sender,
            listing.tokenId,
            quantity,
            ""
        );

        // Transfer royalty to receiver
        if (royaltyAmount > 0 && royaltyReceiver != address(0)) {
            (bool royaltySuccess,) = royaltyReceiver.call{value: royaltyAmount}("");
            if (!royaltySuccess) {
                revert Errors.TransferFailed();
            }
        }

        // Transfer proceeds to seller
        (bool sellerSuccess,) = listing.seller.call{value: sellerProceeds}("");
        if (!sellerSuccess) {
            revert Errors.TransferFailed();
        }

        emit ListingPurchased(
            listingId,
            msg.sender,
            quantity,
            totalPrice,
            royaltyAmount,
            royaltyReceiver
        );
    }

    // ============ Admin Functions ============

    /// @notice Pauses the marketplace
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the marketplace
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ View Functions ============

    /// @inheritdoc IMarketplace
    function getListing(uint256 listingId) external view returns (Listing memory) {
        if (listingId >= _listings.length) {
            return Listing({
                seller: address(0),
                eventContract: address(0),
                tokenId: 0,
                quantity: 0,
                pricePerUnit: 0,
                expirationTime: 0,
                active: false
            });
        }
        return _listings[listingId];
    }

    /// @inheritdoc IMarketplace
    function getActiveListingsForEvent(address eventContract) external view returns (uint256[] memory) {
        uint256 count = 0;

        // Count active listings for this event
        for (uint256 i = 0; i < _listings.length; i++) {
            if (_listings[i].eventContract == eventContract && _listings[i].active) {
                count++;
            }
        }

        // Populate array
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < _listings.length; i++) {
            if (_listings[i].eventContract == eventContract && _listings[i].active) {
                result[index] = i;
                index++;
            }
        }

        return result;
    }

    /// @inheritdoc IMarketplace
    function getListingsBySeller(address seller) external view returns (uint256[] memory) {
        uint256 count = 0;

        // Count listings by seller
        for (uint256 i = 0; i < _listings.length; i++) {
            if (_listings[i].seller == seller) {
                count++;
            }
        }

        // Populate array
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < _listings.length; i++) {
            if (_listings[i].seller == seller) {
                result[index] = i;
                index++;
            }
        }

        return result;
    }

    /// @inheritdoc IMarketplace
    function totalListings() external view returns (uint256) {
        return _listings.length;
    }
}
