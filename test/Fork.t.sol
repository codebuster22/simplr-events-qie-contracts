// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {EventFactory} from "../src/EventFactory.sol";
import {Event} from "../src/Event.sol";
import {IEvent} from "../src/interfaces/IEvent.sol";

/// @title ForkTest
/// @notice Test creating an event on a forked testnet
contract ForkTest is Test {
    EventFactory public factory;

    address constant FACTORY_ADDRESS = 0x5120F677C9a453AC960eCA1fb274D25D96aAAdC5;
    address public deployer;

    function setUp() public {
        // Create fork
        vm.createSelectFork("https://rpc1testnet.qie.digital");

        factory = EventFactory(FACTORY_ADDRESS);
        deployer = makeAddr("deployer");

        // Fund deployer
        vm.deal(deployer, 10 ether);
    }

    function test_fork_createEvent() public {
        // Log factory info
        console.log("Factory address:", address(factory));
        console.log("Factory implementation:", factory.implementation());
        console.log("Factory owner:", factory.owner());
        console.log("Total events before:", factory.totalEvents());

        // Setup event config
        IEvent.EventConfig memory eventConfig = IEvent.EventConfig({
            name: "Fork Test Event",
            symbol: "FTE",
            baseURI: "https://api.example.com/metadata/",
            royaltyBps: 500
        });

        // Setup tier configs
        IEvent.TierConfig[] memory tiers = new IEvent.TierConfig[](2);
        tiers[0] = IEvent.TierConfig({tierId: 1, tierName: "VIP", price: 0.1 ether, maxSupply: 100});
        tiers[1] = IEvent.TierConfig({tierId: 2, tierName: "General Admission", price: 0.01 ether, maxSupply: 1000});

        // No initial gatekeepers
        address[] memory gatekeepers = new address[](0);

        // Create event
        vm.prank(deployer);
        address eventAddress = factory.createEvent(eventConfig, tiers, gatekeepers);

        // Verify
        console.log("\n=== Event Created ===");
        console.log("Event address:", eventAddress);

        assertTrue(eventAddress != address(0), "Event address should not be zero");
        assertTrue(factory.isEvent(eventAddress), "Should be registered as event");
        assertEq(factory.totalEvents(), 1, "Total events should be 1");

        // Check event details
        Event eventContract = Event(eventAddress);
        console.log("Event name:", eventContract.name());
        console.log("Event symbol:", eventContract.symbol());
        console.log("Event owner:", eventContract.owner());
        console.log("AccessPassNFT:", eventContract.accessPassNFT());

        assertEq(eventContract.name(), "Fork Test Event");
        assertEq(eventContract.symbol(), "FTE");
        assertEq(eventContract.owner(), deployer);
        assertTrue(eventContract.accessPassNFT() != address(0), "AccessPassNFT should be deployed");

        // Check tiers
        IEvent.Tier memory vipTier = eventContract.getTier(1);
        assertEq(vipTier.price, 0.1 ether);
        assertEq(vipTier.maxSupply, 100);
        assertTrue(vipTier.active);

        IEvent.Tier memory gaTier = eventContract.getTier(2);
        assertEq(gaTier.price, 0.01 ether);
        assertEq(gaTier.maxSupply, 1000);
        assertTrue(gaTier.active);
    }
}
