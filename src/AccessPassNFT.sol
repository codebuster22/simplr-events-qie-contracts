// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IAccessPassNFT} from "./interfaces/IAccessPassNFT.sol";
import {SimplrErrors} from "./libraries/SimplrErrors.sol";

/// @title AccessPassNFT
/// @notice ERC-721 NFT representing venue access after ticket redemption
/// @dev Non-transferable for 24 hours after mint (soulbound period)
contract AccessPassNFT is ERC721, IAccessPassNFT {
    using Strings for uint256;

    // ============ State Variables ============

    /// @notice The Event contract that can mint access passes
    address public eventContract;

    /// @notice Whether the event contract has been set
    bool private _eventContractSet;

    /// @notice The lock duration for transfers (24 hours)
    uint256 public constant lockDuration = 24 hours;

    /// @notice The base URI for token metadata
    string private _baseTokenURI;

    /// @notice Counter for token IDs
    uint256 private _tokenIdCounter;

    /// @notice Mapping from token ID to metadata
    mapping(uint256 => PassMetadata) private _metadata;

    // ============ Constructor ============

    /// @notice Deploys the AccessPassNFT contract
    /// @param name_ The name of the NFT collection
    /// @param symbol_ The symbol of the NFT collection
    /// @param baseURI_ The base URI for token metadata
    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseURI_
    ) ERC721(name_, symbol_) {
        _baseTokenURI = baseURI_;
    }

    // ============ External Functions ============

    /// @inheritdoc IAccessPassNFT
    function setEventContract(address eventContract_) external {
        if (_eventContractSet) {
            revert SimplrErrors.EventContractAlreadySet();
        }
        if (eventContract_ == address(0)) {
            revert SimplrErrors.ZeroAddress();
        }
        eventContract = eventContract_;
        _eventContractSet = true;
    }

    /// @inheritdoc IAccessPassNFT
    function mint(address to, uint256 tierId) external returns (uint256 tokenId) {
        if (msg.sender != eventContract) {
            revert SimplrErrors.NotAuthorizedMinter();
        }

        unchecked {
            tokenId = ++_tokenIdCounter;
        }

        _metadata[tokenId] = PassMetadata({
            tierId: tierId,
            mintTimestamp: block.timestamp
        });

        _safeMint(to, tokenId);

        emit AccessPassMinted(tokenId, to, tierId);
    }

    // ============ View Functions ============

    /// @inheritdoc IAccessPassNFT
    function getMetadata(uint256 tokenId) external view returns (PassMetadata memory) {
        return _metadata[tokenId];
    }

    /// @inheritdoc IAccessPassNFT
    function isTransferable(uint256 tokenId) external view returns (bool) {
        return block.timestamp >= _metadata[tokenId].mintTimestamp + lockDuration;
    }

    /// @inheritdoc IAccessPassNFT
    function transferUnlockTime(uint256 tokenId) external view returns (uint256) {
        return _metadata[tokenId].mintTimestamp + lockDuration;
    }

    /// @notice Returns the token URI for a given token ID
    /// @param tokenId The token ID
    /// @return The token URI
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return string(abi.encodePacked(_baseTokenURI, tokenId.toString()));
    }

    // ============ Internal Functions ============

    /// @notice Override to enforce transfer lock
    /// @dev Allows minting (from == 0) and burning (to == 0) but blocks transfers during lock period
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);

        // Allow minting and burning, but block transfers during lock period
        if (from != address(0) && to != address(0)) {
            if (block.timestamp < _metadata[tokenId].mintTimestamp + lockDuration) {
                revert SimplrErrors.TransferLocked();
            }
        }

        return super._update(to, tokenId, auth);
    }
}
