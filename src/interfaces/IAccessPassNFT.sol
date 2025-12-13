// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IAccessPassNFT
/// @notice Interface for the AccessPassNFT contract
/// @dev ERC-721 NFT that represents venue access, non-transferable for 24 hours after mint
interface IAccessPassNFT {
    // ============ Structs ============

    /// @notice Metadata stored for each access pass
    struct PassMetadata {
        uint256 tierId;
        uint256 mintTimestamp;
    }

    // ============ Events ============

    /// @notice Emitted when an access pass is minted
    /// @param tokenId The ID of the minted token
    /// @param recipient The address receiving the access pass
    /// @param tierId The tier ID from the original ticket
    event AccessPassMinted(uint256 indexed tokenId, address indexed recipient, uint256 indexed tierId);

    // ============ Functions ============

    /// @notice Initializes the AccessPassNFT clone
    /// @dev Can only be called once during deployment by the factory
    /// @param name_ The name of the NFT collection
    /// @param symbol_ The symbol of the NFT collection
    /// @param baseURI_ The base URI for token metadata
    /// @param eventContract_ The Event contract address that can mint
    function initialize(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        address eventContract_
    ) external;

    /// @notice Mints a new access pass
    /// @dev Only callable by the parent Event contract
    /// @param to The address to mint the access pass to
    /// @param tierId The tier ID from the burned ticket
    /// @return tokenId The ID of the newly minted token
    function mint(address to, uint256 tierId) external returns (uint256 tokenId);

    /// @notice Returns the metadata for an access pass
    /// @param tokenId The token ID to query
    /// @return metadata The pass metadata (tierId, mintTimestamp)
    function getMetadata(uint256 tokenId) external view returns (PassMetadata memory metadata);

    /// @notice Checks if a token is currently transferable
    /// @param tokenId The token ID to check
    /// @return True if the token can be transferred
    function isTransferable(uint256 tokenId) external view returns (bool);

    /// @notice Returns the timestamp when transfer becomes unlocked
    /// @param tokenId The token ID to query
    /// @return The unlock timestamp
    function transferUnlockTime(uint256 tokenId) external view returns (uint256);

    /// @notice Returns the lock duration for transfers
    /// @return The lock duration in seconds (default 24 hours)
    function lockDuration() external view returns (uint256);

    /// @notice Returns the Event contract that can mint access passes
    /// @return The Event contract address
    function eventContract() external view returns (address);
}
