// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {EventFactory} from "../src/EventFactory.sol";
import {Event} from "../src/Event.sol";
import {IEventFactory} from "../src/interfaces/IEventFactory.sol";
import {IEvent} from "../src/interfaces/IEvent.sol";
import {SimplrErrors} from "../src/libraries/SimplrErrors.sol";

contract EventFactoryTest is Test {
    EventFactory public factory;
    Event public eventImplementation;

    address public owner;
    address public organizer1;
    address public organizer2;
    address public gatekeeper1;

    IEvent.EventConfig public eventConfig;
    IEvent.TierConfig[] public tierConfigs;
    address[] public initialGatekeepers;

    function setUp() public {
        owner = makeAddr("owner");
        organizer1 = makeAddr("organizer1");
        organizer2 = makeAddr("organizer2");
        gatekeeper1 = makeAddr("gatekeeper1");

        // Deploy implementation
        eventImplementation = new Event();

        // Deploy factory
        vm.prank(owner);
        factory = new EventFactory(address(eventImplementation));

        // Setup event config
        eventConfig =
            IEvent.EventConfig({name: "Test Event", symbol: "TE", baseURI: "https://api.example.com/", royaltyBps: 500});

        // Setup tier configs
        tierConfigs.push(IEvent.TierConfig({tierId: 1, tierName: "VIP", price: 1 ether, maxSupply: 100}));

        // Setup initial gatekeepers
        initialGatekeepers.push(gatekeeper1);
    }

    // ============ Constructor Tests ============

    function test_constructor_setsImplementation() public view {
        assertEq(factory.implementation(), address(eventImplementation));
    }

    function test_constructor_setsOwner() public view {
        assertEq(factory.owner(), owner);
    }

    function test_constructor_initializesTotalEventsAtZero() public view {
        assertEq(factory.totalEvents(), 0);
    }

    // ============ Create Event Tests ============

    function test_createEvent_deploysEventContract() public {
        vm.prank(organizer1);
        address eventAddress = factory.createEvent(eventConfig, tierConfigs, initialGatekeepers);

        assertTrue(eventAddress != address(0));
        assertTrue(factory.isEvent(eventAddress));
    }

    function test_createEvent_incrementsTotalEvents() public {
        vm.prank(organizer1);
        factory.createEvent(eventConfig, tierConfigs, initialGatekeepers);

        assertEq(factory.totalEvents(), 1);
    }

    function test_createEvent_storesEventAddress() public {
        vm.prank(organizer1);
        address eventAddress = factory.createEvent(eventConfig, tierConfigs, initialGatekeepers);

        assertEq(factory.getEvent(0), eventAddress);
    }

    function test_createEvent_tracksEventsByCreator() public {
        vm.prank(organizer1);
        address eventAddress1 = factory.createEvent(eventConfig, tierConfigs, initialGatekeepers);

        eventConfig.name = "Second Event";
        vm.prank(organizer1);
        address eventAddress2 = factory.createEvent(eventConfig, tierConfigs, initialGatekeepers);

        address[] memory events = factory.getEventsByCreator(organizer1);
        assertEq(events.length, 2);
        assertEq(events[0], eventAddress1);
        assertEq(events[1], eventAddress2);
    }

    function test_createEvent_emitsEventCreatedEvent() public {
        vm.prank(organizer1);
        vm.expectEmit(false, false, true, false);
        emit IEventFactory.EventCreated(address(0), organizer1, eventConfig.name, 0, address(0));
        factory.createEvent(eventConfig, tierConfigs, initialGatekeepers);
    }

    function test_createEvent_initializesEventCorrectly() public {
        vm.prank(organizer1);
        address eventAddress = factory.createEvent(eventConfig, tierConfigs, initialGatekeepers);

        Event eventContract = Event(eventAddress);

        // Check name and symbol
        assertEq(eventContract.name(), eventConfig.name);
        assertEq(eventContract.symbol(), eventConfig.symbol);

        // Check owner (organizer is the owner)
        assertEq(eventContract.owner(), organizer1);

        // Check gatekeeper role
        assertTrue(eventContract.isGatekeeper(gatekeeper1));

        // Check tier was created
        IEvent.Tier memory tier = eventContract.getTier(1);
        assertEq(tier.price, 1 ether);
        assertEq(tier.maxSupply, 100);
        assertTrue(tier.active);

        // Check AccessPassNFT was deployed and linked
        assertTrue(eventContract.accessPassNFT() != address(0));
    }

    function test_createEvent_multipleOrganizers() public {
        vm.prank(organizer1);
        address event1 = factory.createEvent(eventConfig, tierConfigs, initialGatekeepers);

        eventConfig.name = "Event 2";
        vm.prank(organizer2);
        address event2 = factory.createEvent(eventConfig, tierConfigs, initialGatekeepers);

        assertEq(factory.getEventsByCreator(organizer1).length, 1);
        assertEq(factory.getEventsByCreator(organizer2).length, 1);
        assertEq(factory.getEventsByCreator(organizer1)[0], event1);
        assertEq(factory.getEventsByCreator(organizer2)[0], event2);
    }

    function test_createEvent_withMultipleTiers() public {
        tierConfigs.push(IEvent.TierConfig({tierId: 2, tierName: "GA", price: 0.1 ether, maxSupply: 1000}));

        vm.prank(organizer1);
        address eventAddress = factory.createEvent(eventConfig, tierConfigs, initialGatekeepers);

        Event eventContract = Event(eventAddress);

        IEvent.Tier memory vipTier = eventContract.getTier(1);
        assertEq(vipTier.price, 1 ether);

        IEvent.Tier memory gaTier = eventContract.getTier(2);
        assertEq(gaTier.price, 0.1 ether);
        assertEq(gaTier.maxSupply, 1000);
    }

    function test_createEvent_withNoInitialGatekeepers() public {
        address[] memory noGatekeepers = new address[](0);

        vm.prank(organizer1);
        address eventAddress = factory.createEvent(eventConfig, tierConfigs, noGatekeepers);

        Event eventContract = Event(eventAddress);
        assertFalse(eventContract.isGatekeeper(gatekeeper1));
    }

    // ============ View Functions Tests ============

    function test_getEvent_returnsCorrectAddress() public {
        vm.prank(organizer1);
        address eventAddress = factory.createEvent(eventConfig, tierConfigs, initialGatekeepers);

        assertEq(factory.getEvent(0), eventAddress);
    }

    function test_getEvent_returnsZeroForNonExistent() public view {
        assertEq(factory.getEvent(999), address(0));
    }

    function test_isEvent_returnsTrueForValidEvent() public {
        vm.prank(organizer1);
        address eventAddress = factory.createEvent(eventConfig, tierConfigs, initialGatekeepers);

        assertTrue(factory.isEvent(eventAddress));
    }

    function test_isEvent_returnsFalseForInvalidAddress() public view {
        assertFalse(factory.isEvent(address(0x123)));
    }

    function test_getEventsByCreator_returnsEmptyForNoEvents() public view {
        address[] memory events = factory.getEventsByCreator(organizer1);
        assertEq(events.length, 0);
    }
}
