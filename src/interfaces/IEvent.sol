// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IEvent
/// @notice Interface for the Event contract
/// @dev ERC-1155 contract where token IDs represent ticket tiers
interface IEvent {
    // ============ Structs ============

    /// @notice Configuration for creating an event
    struct EventConfig {
        string name;
        string symbol;
        string baseURI;
        uint96 royaltyBps;
    }

    /// @notice Configuration for creating a tier
    struct TierConfig {
        uint256 tierId;
        string tierName;
        uint256 price;
        uint256 maxSupply;
    }

    /// @notice Stored tier data
    struct Tier {
        uint256 price;
        uint256 maxSupply;
        string tierName;
        bool active;
    }

    // ============ Events ============

    /// @notice Emitted when a new tier is created
    event TierCreated(
        uint256 indexed tierId,
        string tierName,
        uint256 price,
        uint256 maxSupply
    );

    /// @notice Emitted when a tier is updated
    event TierUpdated(
        uint256 indexed tierId,
        uint256 newPrice,
        uint256 newMaxSupply
    );

    /// @notice Emitted when a tier's active status is changed
    event TierActiveStatusChanged(uint256 indexed tierId, bool active);

    /// @notice Emitted when tickets are purchased
    event TicketsPurchased(
        address indexed buyer,
        uint256 indexed tierId,
        uint256 quantity,
        uint256 totalPaid
    );

    /// @notice Emitted when a ticket is redeemed for an access pass
    event TicketRedeemed(
        address indexed ticketHolder,
        uint256 indexed tierId,
        uint256 accessPassId
    );

    /// @notice Emitted when a gatekeeper is added
    event GatekeeperAdded(address indexed gatekeeper);

    /// @notice Emitted when a gatekeeper is removed
    event GatekeeperRemoved(address indexed gatekeeper);

    /// @notice Emitted when funds are withdrawn
    event FundsWithdrawn(address indexed to, uint256 amount);

    // ============ Initialization ============

    /// @notice Initializes the Event contract
    /// @param eventConfig The event configuration
    /// @param tiers Array of tier configurations
    /// @param initialGatekeepers Array of initial gatekeeper addresses
    /// @param admin The admin address (event organizer)
    /// @param accessPassNFT_ The AccessPassNFT contract address
    function initialize(
        EventConfig calldata eventConfig,
        TierConfig[] calldata tiers,
        address[] calldata initialGatekeepers,
        address admin,
        address accessPassNFT_
    ) external;

    // ============ Admin Functions - Tier Management ============

    /// @notice Creates a new tier
    /// @param tierId The tier ID
    /// @param tierName The tier name
    /// @param price The price in wei
    /// @param maxSupply The maximum supply
    function createTier(
        uint256 tierId,
        string calldata tierName,
        uint256 price,
        uint256 maxSupply
    ) external;

    /// @notice Updates tier price and max supply
    /// @param tierId The tier ID to update
    /// @param newPrice The new price in wei
    /// @param newMaxSupply The new max supply (cannot be less than current supply)
    function updateTier(
        uint256 tierId,
        uint256 newPrice,
        uint256 newMaxSupply
    ) external;

    /// @notice Sets a tier's active status
    /// @param tierId The tier ID
    /// @param active Whether the tier should be active
    function setTierActive(uint256 tierId, bool active) external;

    // ============ Admin Functions - Gatekeeper Management ============

    /// @notice Adds a gatekeeper
    /// @param gatekeeper The address to add as gatekeeper
    function addGatekeeper(address gatekeeper) external;

    /// @notice Removes a gatekeeper
    /// @param gatekeeper The address to remove as gatekeeper
    function removeGatekeeper(address gatekeeper) external;

    // ============ Admin Functions - Withdraw ============

    /// @notice Withdraws accumulated ETH to specified address
    /// @param to The address to send ETH to
    function withdraw(address to) external;

    // ============ User Functions ============

    /// @notice Buys tickets for a specific tier
    /// @param tierId The tier to buy tickets for
    /// @param quantity The number of tickets to buy
    function buyTickets(uint256 tierId, uint256 quantity) external payable;

    // ============ Gatekeeper Functions ============

    /// @notice Redeems a ticket for an access pass using a signed message
    /// @param ticketHolder The address that owns the ticket
    /// @param tierId The tier ID of the ticket
    /// @param deadline The signature expiration timestamp
    /// @param signature The EIP-712 signature from the ticket holder
    function redeemTicket(
        address ticketHolder,
        uint256 tierId,
        uint256 deadline,
        bytes calldata signature
    ) external;

    // ============ View Functions ============

    /// @notice Returns tier information
    /// @param tierId The tier ID to query
    /// @return The tier data
    function getTier(uint256 tierId) external view returns (Tier memory);

    /// @notice Checks if an address is a gatekeeper
    /// @param account The address to check
    /// @return True if the address is a gatekeeper
    function isGatekeeper(address account) external view returns (bool);

    /// @notice Returns the AccessPassNFT contract address
    /// @return The AccessPassNFT contract address
    function accessPassNFT() external view returns (address);

    /// @notice Returns the event name
    /// @return The event name
    function name() external view returns (string memory);

    /// @notice Returns the event symbol
    /// @return The event symbol
    function symbol() external view returns (string memory);
}
