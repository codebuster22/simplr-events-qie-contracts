// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessPassNFT} from "./AccessPassNFT.sol";
import {IEvent} from "./interfaces/IEvent.sol";
import {Errors} from "./libraries/Errors.sol";

/// @title Event
/// @notice ERC-1155 contract for event tickets where token IDs represent tiers
/// @dev Supports ticket purchase, EIP-712 signature redemption, and royalties
contract Event is ERC1155, ERC1155Supply, ERC2981, AccessControl, EIP712, Nonces, ReentrancyGuard, IEvent {
    using ECDSA for bytes32;

    // ============ Constants ============

    /// @notice Role identifier for gatekeepers
    bytes32 public constant GATEKEEPER_ROLE = keccak256("GATEKEEPER_ROLE");

    /// @notice EIP-712 typehash for ticket redemption
    bytes32 public constant REDEMPTION_TYPEHASH = keccak256(
        "RedeemTicket(address ticketHolder,uint256 tierId,uint256 nonce,uint256 deadline)"
    );

    // ============ State Variables ============

    /// @notice Event name
    string private _name;

    /// @notice Event symbol
    string private _symbol;

    /// @notice Whether the contract has been initialized
    bool private _initialized;

    /// @notice The AccessPassNFT contract for this event
    address public accessPassNFT;

    /// @notice Mapping from tier ID to tier data
    mapping(uint256 => Tier) private _tiers;

    /// @notice Mapping to track if a tier exists
    mapping(uint256 => bool) private _tierExists;

    // ============ Constructor ============

    /// @notice Constructor sets up ERC1155 with empty URI and EIP712 domain
    constructor() ERC1155("") EIP712("EventTicket", "1") {}

    // ============ Initialization ============

    /// @inheritdoc IEvent
    function initialize(
        EventConfig calldata eventConfig,
        TierConfig[] calldata tiers,
        address[] calldata initialGatekeepers,
        address admin
    ) external {
        if (_initialized) {
            revert Errors.AlreadyInitialized();
        }
        _initialized = true;

        _name = eventConfig.name;
        _symbol = eventConfig.symbol;

        // Deploy AccessPassNFT
        accessPassNFT = address(new AccessPassNFT(
            string(abi.encodePacked(eventConfig.name, " Access Pass")),
            string(abi.encodePacked(eventConfig.symbol, "-AP")),
            eventConfig.baseURI
        ));

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        // Setup gatekeepers
        for (uint256 i = 0; i < initialGatekeepers.length; i++) {
            _grantRole(GATEKEEPER_ROLE, initialGatekeepers[i]);
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
    function createTier(
        uint256 tierId,
        string calldata tierName,
        uint256 price,
        uint256 maxSupply
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _createTier(tierId, tierName, price, maxSupply);
    }

    /// @inheritdoc IEvent
    function updateTier(
        uint256 tierId,
        uint256 newPrice,
        uint256 newMaxSupply
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_tierExists[tierId]) {
            revert Errors.TierDoesNotExist();
        }

        uint256 currentSupply = totalSupply(tierId);
        if (newMaxSupply < currentSupply) {
            revert Errors.CannotReduceBelowSupply();
        }

        _tiers[tierId].price = newPrice;
        _tiers[tierId].maxSupply = newMaxSupply;

        emit TierUpdated(tierId, newPrice, newMaxSupply);
    }

    /// @inheritdoc IEvent
    function setTierActive(uint256 tierId, bool active) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_tierExists[tierId]) {
            revert Errors.TierDoesNotExist();
        }

        _tiers[tierId].active = active;

        emit TierActiveStatusChanged(tierId, active);
    }

    // ============ Admin Functions - Gatekeeper Management ============

    /// @inheritdoc IEvent
    function addGatekeeper(address gatekeeper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(GATEKEEPER_ROLE, gatekeeper);
        emit GatekeeperAdded(gatekeeper);
    }

    /// @inheritdoc IEvent
    function removeGatekeeper(address gatekeeper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(GATEKEEPER_ROLE, gatekeeper);
        emit GatekeeperRemoved(gatekeeper);
    }

    // ============ Admin Functions - Withdraw ============

    /// @inheritdoc IEvent
    function withdraw(address to) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        uint256 balance = address(this).balance;
        (bool success,) = to.call{value: balance}("");
        if (!success) {
            revert Errors.TransferFailed();
        }
        emit FundsWithdrawn(to, balance);
    }

    // ============ User Functions ============

    /// @inheritdoc IEvent
    function buyTickets(uint256 tierId, uint256 quantity) external payable nonReentrant {
        if (quantity == 0) {
            revert Errors.ZeroQuantity();
        }

        if (!_tierExists[tierId]) {
            revert Errors.TierDoesNotExist();
        }

        Tier storage tier = _tiers[tierId];

        if (!tier.active) {
            revert Errors.TierNotActive();
        }

        if (totalSupply(tierId) + quantity > tier.maxSupply) {
            revert Errors.ExceedsMaxSupply();
        }

        uint256 totalPrice = tier.price * quantity;
        if (msg.value != totalPrice) {
            revert Errors.IncorrectPayment();
        }

        _mint(msg.sender, tierId, quantity, "");

        emit TicketsPurchased(msg.sender, tierId, quantity, totalPrice);
    }

    // ============ Gatekeeper Functions ============

    /// @inheritdoc IEvent
    function redeemTicket(
        address ticketHolder,
        uint256 tierId,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        if (!hasRole(GATEKEEPER_ROLE, msg.sender)) {
            revert Errors.NotGatekeeper();
        }

        if (block.timestamp > deadline) {
            revert Errors.SignatureExpired();
        }

        if (balanceOf(ticketHolder, tierId) < 1) {
            revert Errors.InsufficientTickets();
        }

        // Verify signature
        bytes32 structHash = keccak256(abi.encode(
            REDEMPTION_TYPEHASH,
            ticketHolder,
            tierId,
            _useNonce(ticketHolder),
            deadline
        ));

        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);

        if (signer != ticketHolder) {
            revert Errors.InvalidSignature();
        }

        // Burn ticket
        _burn(ticketHolder, tierId, 1);

        // Mint access pass
        uint256 accessPassId = AccessPassNFT(accessPassNFT).mint(ticketHolder, tierId);

        emit TicketRedeemed(ticketHolder, tierId, accessPassId);
    }

    // ============ View Functions ============

    /// @inheritdoc IEvent
    function getTier(uint256 tierId) external view returns (Tier memory) {
        return _tiers[tierId];
    }

    /// @inheritdoc IEvent
    function isGatekeeper(address account) external view returns (bool) {
        return hasRole(GATEKEEPER_ROLE, account);
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
    function _createTier(
        uint256 tierId,
        string memory tierName,
        uint256 price,
        uint256 maxSupply
    ) internal {
        if (_tierExists[tierId]) {
            revert Errors.TierAlreadyExists();
        }

        if (maxSupply == 0) {
            revert Errors.ZeroMaxSupply();
        }

        _tierExists[tierId] = true;
        _tiers[tierId] = Tier({
            price: price,
            maxSupply: maxSupply,
            tierName: tierName,
            active: true
        });

        emit TierCreated(tierId, tierName, price, maxSupply);
    }

    // ============ Override Functions ============

    /// @notice Required override for ERC1155Supply
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155, ERC1155Supply) {
        super._update(from, to, ids, values);
    }

    /// @notice Required override for AccessControl and ERC1155
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, ERC2981, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
