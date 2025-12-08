// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IMarketplace
/// @notice Interface for the Marketplace contract
/// @dev Secondary market for trading ERC-1155 tickets with ERC-2981 royalty support
interface IMarketplace {
    // ============ Structs ============

    /// @notice Listing information
    struct Listing {
        address seller;
        address eventContract;
        uint256 tokenId;
        uint256 quantity;
        uint256 pricePerUnit;
        uint256 expirationTime;
        bool active;
    }

    // ============ Events ============

    /// @notice Emitted when a new listing is created
    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        address indexed eventContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 pricePerUnit,
        uint256 expirationTime
    );

    /// @notice Emitted when a listing is cancelled
    event ListingCancelled(uint256 indexed listingId);

    /// @notice Emitted when a listing price is updated
    event ListingPriceUpdated(uint256 indexed listingId, uint256 newPrice);

    /// @notice Emitted when tickets are purchased from a listing
    event ListingPurchased(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 quantity,
        uint256 totalPrice,
        uint256 royaltyPaid,
        address royaltyReceiver
    );

    // ============ Functions ============

    /// @notice Creates a new listing
    /// @param eventContract The Event contract address
    /// @param tokenId The tier/token ID to list
    /// @param quantity The number of tickets to list
    /// @param pricePerUnit The price per ticket in wei
    /// @param expirationTime The listing expiration timestamp
    /// @return listingId The ID of the created listing
    function createListing(
        address eventContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 pricePerUnit,
        uint256 expirationTime
    ) external returns (uint256 listingId);

    /// @notice Cancels a listing
    /// @param listingId The listing ID to cancel
    function cancelListing(uint256 listingId) external;

    /// @notice Updates the price of a listing
    /// @param listingId The listing ID to update
    /// @param newPrice The new price per unit in wei
    function updateListingPrice(uint256 listingId, uint256 newPrice) external;

    /// @notice Purchases tickets from a listing
    /// @param listingId The listing ID to purchase from
    /// @param quantity The number of tickets to purchase
    function buyListing(uint256 listingId, uint256 quantity) external payable;

    // ============ View Functions ============

    /// @notice Returns listing information
    /// @param listingId The listing ID to query
    /// @return The listing data
    function getListing(uint256 listingId) external view returns (Listing memory);

    /// @notice Returns active listings for an event
    /// @param eventContract The Event contract address
    /// @return Array of listing IDs
    function getActiveListingsForEvent(address eventContract) external view returns (uint256[] memory);

    /// @notice Returns listings by a seller
    /// @param seller The seller address
    /// @return Array of listing IDs
    function getListingsBySeller(address seller) external view returns (uint256[] memory);

    /// @notice Returns the total number of listings created
    /// @return The listing count
    function totalListings() external view returns (uint256);
}
