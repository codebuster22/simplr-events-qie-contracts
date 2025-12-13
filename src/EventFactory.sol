// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IEventFactory} from "./interfaces/IEventFactory.sol";
import {IEvent} from "./interfaces/IEvent.sol";
import {IAccessPassNFT} from "./interfaces/IAccessPassNFT.sol";
import {Event} from "./Event.sol";

/// @title EventFactory
/// @notice Factory for deploying Event contracts using EIP-1167 minimal proxies
/// @dev Uses Clones library for gas-efficient Event deployment
contract EventFactory is Ownable, IEventFactory {
    // ============ State Variables ============

    /// @notice The Event implementation contract address
    address public immutable implementation;

    /// @notice The AccessPassNFT implementation contract address
    address public immutable accessPassNFTImplementation;

    /// @notice Array of all created event addresses
    address[] private _events;

    /// @notice Mapping to check if an address is a valid event
    mapping(address => bool) private _isEvent;

    /// @notice Mapping from creator to their event addresses
    mapping(address => address[]) private _eventsByCreator;

    // ============ Constructor ============

    /// @notice Deploys the EventFactory with Event and AccessPassNFT implementations
    /// @param implementation_ The Event implementation contract address
    /// @param accessPassNFTImplementation_ The AccessPassNFT implementation contract address
    constructor(address implementation_, address accessPassNFTImplementation_) Ownable(msg.sender) {
        implementation = implementation_;
        accessPassNFTImplementation = accessPassNFTImplementation_;
    }

    // ============ External Functions ============

    /// @inheritdoc IEventFactory
    function createEvent(
        IEvent.EventConfig calldata eventConfig,
        IEvent.TierConfig[] calldata tiers,
        address[] calldata initialGatekeepers
    ) external returns (address eventAddress) {
        // 1. Clone the Event implementation
        eventAddress = Clones.clone(implementation);

        // 2. Clone AccessPassNFT implementation
        address accessPassAddress = Clones.clone(accessPassNFTImplementation);

        // 3. Initialize AccessPassNFT with Event address
        IAccessPassNFT(accessPassAddress).initialize(
            string(abi.encodePacked(eventConfig.name, " Access Pass")),
            string(abi.encodePacked(eventConfig.symbol, "-AP")),
            eventConfig.baseURI,
            eventAddress
        );

        // 4. Initialize the Event with AccessPassNFT address
        Event(eventAddress).initialize(eventConfig, tiers, initialGatekeepers, msg.sender, accessPassAddress);

        // Track the event
        uint256 eventId = _events.length;
        _events.push(eventAddress);
        _isEvent[eventAddress] = true;
        _eventsByCreator[msg.sender].push(eventAddress);

        emit EventCreated(eventAddress, msg.sender, eventConfig.name, eventId, accessPassAddress);
    }

    // ============ View Functions ============

    /// @inheritdoc IEventFactory
    function getEvent(uint256 eventId) external view returns (address) {
        if (eventId >= _events.length) {
            return address(0);
        }
        return _events[eventId];
    }

    /// @inheritdoc IEventFactory
    function getEventsByCreator(address creator) external view returns (address[] memory) {
        return _eventsByCreator[creator];
    }

    /// @inheritdoc IEventFactory
    function totalEvents() external view returns (uint256) {
        return _events.length;
    }

    /// @inheritdoc IEventFactory
    function isEvent(address eventAddress) external view returns (bool) {
        return _isEvent[eventAddress];
    }
}
