// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IEvent} from "./IEvent.sol";

/// @title IEventFactory
/// @notice Interface for the EventFactory contract
/// @dev Factory for deploying Event contracts using EIP-1167 Clones
interface IEventFactory {
    // ============ Events ============

    /// @notice Emitted when a new event is created
    event EventCreated(
        address indexed eventAddress,
        address accessPassNFT,
        address indexed creator,
        string name,
        uint256 indexed eventId
    );

    /// @notice Emitted when the implementation is updated
    event ImplementationUpdated(address indexed newImplementation);

    // ============ Functions ============

    /// @notice Creates a new Event contract
    /// @param eventConfig The event configuration (name, symbol, baseURI, royaltyBps)
    /// @param tiers Array of tier configurations
    /// @param initialGatekeepers Array of initial gatekeeper addresses
    /// @return eventAddress The address of the newly created Event contract
    function createEvent(
        IEvent.EventConfig calldata eventConfig,
        IEvent.TierConfig[] calldata tiers,
        address[] calldata initialGatekeepers
    ) external returns (address eventAddress);

    /// @notice Returns the address of an event by ID
    /// @param eventId The event ID
    /// @return The event contract address
    function getEvent(uint256 eventId) external view returns (address);

    /// @notice Returns all events created by a specific address
    /// @param creator The creator address
    /// @return Array of event contract addresses
    function getEventsByCreator(address creator) external view returns (address[] memory);

    /// @notice Returns the total number of events created
    /// @return The total event count
    function totalEvents() external view returns (uint256);

    /// @notice Returns the Event implementation contract address
    /// @return The implementation address
    function implementation() external view returns (address);

    /// @notice Checks if an address is a valid Event contract created by this factory
    /// @param eventAddress The address to check
    /// @return True if the address is a valid Event contract
    function isEvent(address eventAddress) external view returns (bool);
}
