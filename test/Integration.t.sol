// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {EventFactory} from "../src/EventFactory.sol";
import {Event} from "../src/Event.sol";
import {AccessPassNFT} from "../src/AccessPassNFT.sol";
import {Marketplace} from "../src/Marketplace.sol";
import {IEvent} from "../src/interfaces/IEvent.sol";
import {IAccessPassNFT} from "../src/interfaces/IAccessPassNFT.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/// @title Integration Tests
/// @notice Full flow integration tests for the event ticketing system
contract IntegrationTest is Test, IERC1155Receiver {
    EventFactory public factory;
    Marketplace public marketplace;
    Event public eventImplementation;

    address public owner;
    address public organizer;
    address public gatekeeper;
    address public buyer1;
    address public buyer2;

    uint256 constant VIP_TIER_ID = 1;
    uint256 constant GA_TIER_ID = 2;
    uint256 constant VIP_PRICE = 1 ether;
    uint256 constant GA_PRICE = 0.1 ether;
    uint256 constant ROYALTY_BPS = 500;

    function setUp() public {
        owner = makeAddr("owner");
        organizer = makeAddr("organizer");
        gatekeeper = makeAddr("gatekeeper");
        buyer1 = makeAddr("buyer1");
        buyer2 = makeAddr("buyer2");

        vm.deal(buyer1, 100 ether);
        vm.deal(buyer2, 100 ether);

        // Deploy infrastructure
        eventImplementation = new Event();

        vm.startPrank(owner);
        factory = new EventFactory(address(eventImplementation));
        marketplace = new Marketplace();
        vm.stopPrank();
    }

    // ============ IERC1155Receiver ============

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    // ============ Full Flow Tests ============

    /// @notice Test the complete flow: Create event -> Buy tickets -> Redeem -> Verify access pass
    function test_fullFlow_createEventBuyTicketsRedeemAtVenue() public {
        // 1. Create event
        IEvent.EventConfig memory eventConfig = IEvent.EventConfig({
            name: "Concert 2024",
            symbol: "C24",
            baseURI: "https://api.concert.com/",
            royaltyBps: uint96(ROYALTY_BPS)
        });

        IEvent.TierConfig[] memory tiers = new IEvent.TierConfig[](2);
        tiers[0] = IEvent.TierConfig({tierId: VIP_TIER_ID, tierName: "VIP", price: VIP_PRICE, maxSupply: 100});
        tiers[1] =
            IEvent.TierConfig({tierId: GA_TIER_ID, tierName: "General Admission", price: GA_PRICE, maxSupply: 1000});

        address[] memory gatekeepers = new address[](1);
        gatekeepers[0] = gatekeeper;

        vm.prank(organizer);
        address eventAddress = factory.createEvent(eventConfig, tiers, gatekeepers);
        Event eventContract = Event(eventAddress);

        // 2. Buyer purchases VIP ticket
        vm.prank(buyer1);
        eventContract.buyTickets{value: VIP_PRICE}(VIP_TIER_ID, 1);

        assertEq(eventContract.balanceOf(buyer1, VIP_TIER_ID), 1);

        // 3. Create signature for redemption
        (address signer, uint256 signerPk) = makeAddrAndKey("ticketHolder");
        vm.deal(signer, 10 ether);

        vm.prank(signer);
        eventContract.buyTickets{value: VIP_PRICE}(VIP_TIER_ID, 1);

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _getRedeemDigest(eventContract, signer, VIP_TIER_ID, eventContract.nonces(signer), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 4. Gatekeeper redeems ticket
        vm.prank(gatekeeper);
        eventContract.redeemTicket(signer, VIP_TIER_ID, deadline, signature);

        // 5. Verify ticket burned and access pass minted
        assertEq(eventContract.balanceOf(signer, VIP_TIER_ID), 0);

        AccessPassNFT accessPass = AccessPassNFT(eventContract.accessPassNFT());
        assertEq(accessPass.ownerOf(1), signer);

        // 6. Verify access pass is non-transferable
        IAccessPassNFT.PassMetadata memory metadata = accessPass.getMetadata(1);
        assertEq(metadata.tierId, VIP_TIER_ID);
        assertFalse(accessPass.isTransferable(1));

        // 7. After 24 hours, access pass becomes transferable
        vm.warp(block.timestamp + 24 hours + 1);
        assertTrue(accessPass.isTransferable(1));
    }

    /// @notice Test secondary market flow: Buy -> List -> Sell with royalties
    function test_fullFlow_secondaryMarketWithRoyalties() public {
        // 1. Create event
        IEvent.EventConfig memory eventConfig = IEvent.EventConfig({
            name: "Festival 2024",
            symbol: "F24",
            baseURI: "https://api.festival.com/",
            royaltyBps: uint96(ROYALTY_BPS)
        });

        IEvent.TierConfig[] memory tiers = new IEvent.TierConfig[](1);
        tiers[0] = IEvent.TierConfig({tierId: VIP_TIER_ID, tierName: "VIP", price: VIP_PRICE, maxSupply: 100});

        address[] memory gatekeepers = new address[](0);

        vm.prank(organizer);
        address eventAddress = factory.createEvent(eventConfig, tiers, gatekeepers);
        Event eventContract = Event(eventAddress);

        // 2. Buyer1 purchases tickets
        vm.prank(buyer1);
        eventContract.buyTickets{value: VIP_PRICE * 3}(VIP_TIER_ID, 3);

        // 3. Buyer1 lists tickets on marketplace
        vm.prank(buyer1);
        eventContract.setApprovalForAll(address(marketplace), true);

        uint256 listingPrice = 2 ether;
        uint256 expiration = block.timestamp + 7 days;

        vm.prank(buyer1);
        uint256 listingId = marketplace.createListing(eventAddress, VIP_TIER_ID, 3, listingPrice, expiration);

        // 4. Buyer2 purchases from marketplace
        uint256 quantity = 2;
        uint256 totalPrice = listingPrice * quantity;
        uint256 royaltyAmount = (totalPrice * ROYALTY_BPS) / 10000;
        uint256 sellerProceeds = totalPrice - royaltyAmount;

        uint256 buyer1BalanceBefore = buyer1.balance;
        uint256 organizerBalanceBefore = organizer.balance;

        vm.prank(buyer2);
        marketplace.buyListing{value: totalPrice}(listingId, quantity);

        // 5. Verify ticket transfer
        assertEq(eventContract.balanceOf(buyer2, VIP_TIER_ID), quantity);
        assertEq(eventContract.balanceOf(buyer1, VIP_TIER_ID), 1);

        // 6. Verify royalty distribution
        assertEq(buyer1.balance, buyer1BalanceBefore + sellerProceeds);
        assertEq(organizer.balance, organizerBalanceBefore + royaltyAmount);
    }

    /// @notice Test organizer managing event: Update tiers, add gatekeepers, withdraw funds
    function test_fullFlow_organizerManagement() public {
        // 1. Create event
        IEvent.EventConfig memory eventConfig = IEvent.EventConfig({
            name: "Conference 2024",
            symbol: "CONF",
            baseURI: "https://api.conference.com/",
            royaltyBps: uint96(ROYALTY_BPS)
        });

        IEvent.TierConfig[] memory tiers = new IEvent.TierConfig[](1);
        tiers[0] = IEvent.TierConfig({tierId: VIP_TIER_ID, tierName: "Early Bird", price: VIP_PRICE, maxSupply: 100});

        address[] memory gatekeepers = new address[](0);

        vm.prank(organizer);
        address eventAddress = factory.createEvent(eventConfig, tiers, gatekeepers);
        Event eventContract = Event(eventAddress);

        // 2. Organizer adds a gatekeeper
        vm.prank(organizer);
        eventContract.addGatekeeper(gatekeeper);
        assertTrue(eventContract.isGatekeeper(gatekeeper));

        // 3. Organizer creates a new tier
        vm.prank(organizer);
        eventContract.createTier(GA_TIER_ID, "Regular", GA_PRICE, 500);

        IEvent.Tier memory gaTier = eventContract.getTier(GA_TIER_ID);
        assertEq(gaTier.price, GA_PRICE);
        assertEq(gaTier.maxSupply, 500);

        // 4. Buyers purchase tickets
        vm.prank(buyer1);
        eventContract.buyTickets{value: VIP_PRICE * 5}(VIP_TIER_ID, 5);

        vm.prank(buyer2);
        eventContract.buyTickets{value: GA_PRICE * 10}(GA_TIER_ID, 10);

        // 5. Organizer increases tier price
        vm.prank(organizer);
        eventContract.updateTier(VIP_TIER_ID, 1.5 ether, 100);

        IEvent.Tier memory updatedTier = eventContract.getTier(VIP_TIER_ID);
        assertEq(updatedTier.price, 1.5 ether);

        // 6. Organizer withdraws funds
        uint256 expectedBalance = VIP_PRICE * 5 + GA_PRICE * 10;
        uint256 organizerBalanceBefore = organizer.balance;

        vm.prank(organizer);
        eventContract.withdraw(organizer);

        assertEq(organizer.balance, organizerBalanceBefore + expectedBalance);
        assertEq(address(eventContract).balance, 0);
    }

    /// @notice Test multiple events from same organizer
    function test_fullFlow_multipleEvents() public {
        // Create first event
        IEvent.EventConfig memory config1 =
            IEvent.EventConfig({name: "Event 1", symbol: "E1", baseURI: "https://api.event1.com/", royaltyBps: 500});

        IEvent.TierConfig[] memory tiers = new IEvent.TierConfig[](1);
        tiers[0] = IEvent.TierConfig({tierId: 1, tierName: "Standard", price: 0.5 ether, maxSupply: 100});

        address[] memory gatekeepers = new address[](0);

        vm.prank(organizer);
        address event1 = factory.createEvent(config1, tiers, gatekeepers);

        // Create second event
        IEvent.EventConfig memory config2 =
            IEvent.EventConfig({name: "Event 2", symbol: "E2", baseURI: "https://api.event2.com/", royaltyBps: 1000});

        vm.prank(organizer);
        address event2 = factory.createEvent(config2, tiers, gatekeepers);

        // Verify both events exist
        assertEq(factory.totalEvents(), 2);
        assertEq(factory.getEvent(0), event1);
        assertEq(factory.getEvent(1), event2);

        address[] memory organizerEvents = factory.getEventsByCreator(organizer);
        assertEq(organizerEvents.length, 2);

        // Buy tickets from both events
        vm.prank(buyer1);
        Event(event1).buyTickets{value: 0.5 ether}(1, 1);

        vm.prank(buyer1);
        Event(event2).buyTickets{value: 0.5 ether}(1, 1);

        assertEq(Event(event1).balanceOf(buyer1, 1), 1);
        assertEq(Event(event2).balanceOf(buyer1, 1), 1);
    }

    /// @notice Test edge case: Tier deactivation
    function test_fullFlow_tierDeactivation() public {
        IEvent.EventConfig memory eventConfig = IEvent.EventConfig({
            name: "Limited Event",
            symbol: "LE",
            baseURI: "https://api.limited.com/",
            royaltyBps: 500
        });

        IEvent.TierConfig[] memory tiers = new IEvent.TierConfig[](1);
        tiers[0] =
            IEvent.TierConfig({tierId: VIP_TIER_ID, tierName: "Limited Edition", price: VIP_PRICE, maxSupply: 10});

        address[] memory gatekeepers = new address[](0);

        vm.prank(organizer);
        address eventAddress = factory.createEvent(eventConfig, tiers, gatekeepers);
        Event eventContract = Event(eventAddress);

        // Buyer1 purchases tickets
        vm.prank(buyer1);
        eventContract.buyTickets{value: VIP_PRICE * 5}(VIP_TIER_ID, 5);

        // Organizer deactivates tier
        vm.prank(organizer);
        eventContract.setTierActive(VIP_TIER_ID, false);

        // Buyer2 cannot purchase (tier deactivated)
        vm.prank(buyer2);
        vm.expectRevert();
        eventContract.buyTickets{value: VIP_PRICE}(VIP_TIER_ID, 1);

        // Organizer reactivates tier
        vm.prank(organizer);
        eventContract.setTierActive(VIP_TIER_ID, true);

        // Now buyer2 can purchase
        vm.prank(buyer2);
        eventContract.buyTickets{value: VIP_PRICE}(VIP_TIER_ID, 1);

        assertEq(eventContract.balanceOf(buyer2, VIP_TIER_ID), 1);
    }

    // ============ Helper Functions ============

    function _getRedeemDigest(
        Event eventContract,
        address ticketHolder,
        uint256 tierId,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 REDEMPTION_TYPEHASH =
            keccak256("RedeemTicket(address ticketHolder,uint256 tierId,uint256 nonce,uint256 deadline)");

        bytes32 structHash = keccak256(abi.encode(REDEMPTION_TYPEHASH, ticketHolder, tierId, nonce, deadline));

        bytes32 domainSeparator = eventContract.DOMAIN_SEPARATOR();
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
