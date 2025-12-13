// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155SupplyUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IAccessPassNFT} from "./interfaces/IAccessPassNFT.sol";
import {IEvent} from "./interfaces/IEvent.sol";
import {SimplrErrors} from "./libraries/SimplrErrors.sol";

/// @title Event
/// @notice ERC-1155 contract for event tickets where token IDs represent tiers
/// @dev Supports ticket purchase, EIP-712 signature redemption, and royalties
contract Event is
    Initializable,
    ERC1155Upgradeable,
    ERC1155SupplyUpgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable,
    EIP712Upgradeable,
    NoncesUpgradeable,
    ReentrancyGuardUpgradeable,
    IEvent
{
    using ECDSA for bytes32;

    // ============ Constants ============

    /// @notice EIP-712 typehash for ticket redemption
    bytes32 public constant REDEMPTION_TYPEHASH =
        keccak256("RedeemTicket(address ticketHolder,uint256 tierId,uint256 nonce,uint256 deadline)");

    // ============ State Variables ============

    /// @notice Event name
    string private _name;

    /// @notice Event symbol
    string private _symbol;

    /// @notice The AccessPassNFT contract for this event
    address public accessPassNFT;

    /// @notice Mapping from tier ID to tier data
    mapping(uint256 => Tier) private _tiers;

    /// @notice Mapping to track if a tier exists
    mapping(uint256 => bool) private _tierExists;

    /// @notice Mapping of gatekeeper addresses
    mapping(address => bool) private _gatekeepers;

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initialization ============

    /// @inheritdoc IEvent
    function initialize(
        EventConfig calldata eventConfig,
        TierConfig[] calldata tiers,
        address[] calldata initialGatekeepers,
        address admin,
        address accessPassNFT_
    ) external initializer {
        __ERC1155_init("");
        __ERC1155Supply_init();
        __ERC2981_init();
        __Ownable_init(admin);
        __EIP712_init("EventTicket", "1");
        __Nonces_init();
        __ReentrancyGuard_init();

        _name = eventConfig.name;
        _symbol = eventConfig.symbol;
        accessPassNFT = accessPassNFT_;

        // Setup gatekeepers
        for (uint256 i = 0; i < initialGatekeepers.length; i++) {
            _gatekeepers[initialGatekeepers[i]] = true;
            emit GatekeeperAdded(initialGatekeepers[i]);
        }

        // Create tiers
        for (uint256 i = 0; i < tiers.length; i++) {
            _createTier(tiers[i].tierId, tiers[i].tierName, tiers[i].price, tiers[i].maxSupply);
        }

        // Set default royalty
        _setDefaultRoyalty(admin, eventConfig.royaltyBps);
    }

    // ============ Admin Functions - Tier Management ============

    /// @inheritdoc IEvent
    function createTier(uint256 tierId, string calldata tierName, uint256 price, uint256 maxSupply)
        external
        onlyOwner
    {
        _createTier(tierId, tierName, price, maxSupply);
    }

    /// @inheritdoc IEvent
    function updateTier(uint256 tierId, uint256 newPrice, uint256 newMaxSupply) external onlyOwner {
        if (!_tierExists[tierId]) {
            revert SimplrErrors.TierDoesNotExist();
        }

        uint256 currentSupply = totalSupply(tierId);
        if (newMaxSupply < currentSupply) {
            revert SimplrErrors.CannotReduceBelowSupply();
        }

        _tiers[tierId].price = newPrice;
        _tiers[tierId].maxSupply = newMaxSupply;

        emit TierUpdated(tierId, newPrice, newMaxSupply);
    }

    /// @inheritdoc IEvent
    function setTierActive(uint256 tierId, bool active) external onlyOwner {
        if (!_tierExists[tierId]) {
            revert SimplrErrors.TierDoesNotExist();
        }

        _tiers[tierId].active = active;

        emit TierActiveStatusChanged(tierId, active);
    }

    // ============ Admin Functions - Gatekeeper Management ============

    /// @inheritdoc IEvent
    function addGatekeeper(address gatekeeper) external onlyOwner {
        _gatekeepers[gatekeeper] = true;
        emit GatekeeperAdded(gatekeeper);
    }

    /// @inheritdoc IEvent
    function removeGatekeeper(address gatekeeper) external onlyOwner {
        _gatekeepers[gatekeeper] = false;
        emit GatekeeperRemoved(gatekeeper);
    }

    // ============ Admin Functions - Withdraw ============

    /// @inheritdoc IEvent
    function withdraw(address to) external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        (bool success,) = to.call{value: balance}("");
        if (!success) {
            revert SimplrErrors.TransferFailed();
        }
        emit FundsWithdrawn(to, balance);
    }

    // ============ User Functions ============

    /// @inheritdoc IEvent
    function buyTickets(uint256 tierId, uint256 quantity) external payable nonReentrant {
        if (quantity == 0) {
            revert SimplrErrors.ZeroQuantity();
        }

        if (!_tierExists[tierId]) {
            revert SimplrErrors.TierDoesNotExist();
        }

        Tier storage tier = _tiers[tierId];

        if (!tier.active) {
            revert SimplrErrors.TierNotActive();
        }

        if (totalSupply(tierId) + quantity > tier.maxSupply) {
            revert SimplrErrors.ExceedsMaxSupply();
        }

        uint256 totalPrice = tier.price * quantity;
        if (msg.value != totalPrice) {
            revert SimplrErrors.IncorrectPayment();
        }

        _mint(msg.sender, tierId, quantity, "");

        emit TicketsPurchased(msg.sender, tierId, quantity, totalPrice);
    }

    // ============ Gatekeeper Functions ============

    /// @inheritdoc IEvent
    function redeemTicket(address ticketHolder, uint256 tierId, uint256 deadline, bytes calldata signature)
        external
        nonReentrant
    {
        if (!_gatekeepers[msg.sender]) {
            revert SimplrErrors.NotGatekeeper();
        }

        if (block.timestamp > deadline) {
            revert SimplrErrors.SignatureExpired();
        }

        if (balanceOf(ticketHolder, tierId) < 1) {
            revert SimplrErrors.InsufficientTickets();
        }

        // Verify signature
        bytes32 structHash =
            keccak256(abi.encode(REDEMPTION_TYPEHASH, ticketHolder, tierId, _useNonce(ticketHolder), deadline));

        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);

        if (signer != ticketHolder) {
            revert SimplrErrors.InvalidSignature();
        }

        // Burn ticket
        _burn(ticketHolder, tierId, 1);

        // Mint access pass
        uint256 accessPassId = IAccessPassNFT(accessPassNFT).mint(ticketHolder, tierId);

        emit TicketRedeemed(ticketHolder, tierId, accessPassId);
    }

    // ============ View Functions ============

    /// @inheritdoc IEvent
    function getTier(uint256 tierId) external view returns (Tier memory) {
        return _tiers[tierId];
    }

    /// @inheritdoc IEvent
    function isGatekeeper(address account) external view returns (bool) {
        return _gatekeepers[account];
    }

    /// @inheritdoc IEvent
    function name() external view returns (string memory) {
        return _name;
    }

    /// @inheritdoc IEvent
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /// @notice Returns the EIP-712 domain separator
    /// @return The domain separator
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ============ Internal Functions ============

    /// @notice Creates a new tier
    function _createTier(uint256 tierId, string memory tierName, uint256 price, uint256 maxSupply) internal {
        if (_tierExists[tierId]) {
            revert SimplrErrors.TierAlreadyExists();
        }

        if (maxSupply == 0) {
            revert SimplrErrors.ZeroMaxSupply();
        }

        _tierExists[tierId] = true;
        _tiers[tierId] = Tier({price: price, maxSupply: maxSupply, tierName: tierName, active: true});

        emit TierCreated(tierId, tierName, price, maxSupply);
    }

    // ============ Override Functions ============

    /// @notice Required override for ERC1155SupplyUpgradeable
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        super._update(from, to, ids, values);
    }

    /// @notice Required override for ERC1155 and ERC2981
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
