// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Marketplace} from "../src/Marketplace.sol";
import {Event} from "../src/Event.sol";
import {EventFactory} from "../src/EventFactory.sol";
import {IMarketplace} from "../src/interfaces/IMarketplace.sol";
import {IEvent} from "../src/interfaces/IEvent.sol";
import {SimplrErrors} from "../src/libraries/SimplrErrors.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

contract MarketplaceTest is Test, IERC1155Receiver {
    Marketplace public marketplace;
    EventFactory public factory;
    Event public eventContract;

    address public owner;
    address public seller;
    address public buyer;
    address public organizer;

    uint256 constant TIER_ID = 1;
    uint256 constant TICKET_PRICE = 1 ether;
    uint256 constant LISTING_PRICE = 2 ether;
    uint256 constant ROYALTY_BPS = 500; // 5%

    function setUp() public {
        owner = makeAddr("owner");
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        organizer = makeAddr("organizer");

        // Fund accounts
        vm.deal(seller, 100 ether);
        vm.deal(buyer, 100 ether);

        // Deploy factory and marketplace
        Event implementation = new Event();
        vm.prank(owner);
        factory = new EventFactory(address(implementation));

        vm.prank(owner);
        marketplace = new Marketplace();

        // Create an event
        IEvent.EventConfig memory eventConfig = IEvent.EventConfig({
            name: "Test Event",
            symbol: "TE",
            baseURI: "https://api.example.com/",
            royaltyBps: uint96(ROYALTY_BPS)
        });

        IEvent.TierConfig[] memory tiers = new IEvent.TierConfig[](1);
        tiers[0] = IEvent.TierConfig({
            tierId: TIER_ID,
            tierName: "VIP",
            price: TICKET_PRICE,
            maxSupply: 100
        });

        address[] memory gatekeepers = new address[](0);

        vm.prank(organizer);
        address eventAddress = factory.createEvent(eventConfig, tiers, gatekeepers);
        eventContract = Event(eventAddress);

        // Seller buys tickets
        vm.prank(seller);
        eventContract.buyTickets{value: TICKET_PRICE * 5}(TIER_ID, 5);

        // Seller approves marketplace
        vm.prank(seller);
        eventContract.setApprovalForAll(address(marketplace), true);
    }

    // ============ IERC1155Receiver Implementation ============

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    // ============ Create Listing Tests ============

    function test_createListing_createsListing() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(
            address(eventContract),
            TIER_ID,
            3,
            LISTING_PRICE,
            expiration
        );

        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(listing.seller, seller);
        assertEq(listing.eventContract, address(eventContract));
        assertEq(listing.tokenId, TIER_ID);
        assertEq(listing.quantity, 3);
        assertEq(listing.pricePerUnit, LISTING_PRICE);
        assertEq(listing.expirationTime, expiration);
        assertTrue(listing.active);
    }

    function test_createListing_emitsEvent() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        vm.expectEmit(true, true, true, true);
        emit IMarketplace.ListingCreated(0, seller, address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);
        marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);
    }

    function test_createListing_incrementsListingId() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 id1 = marketplace.createListing(address(eventContract), TIER_ID, 1, LISTING_PRICE, expiration);

        vm.prank(seller);
        uint256 id2 = marketplace.createListing(address(eventContract), TIER_ID, 1, LISTING_PRICE, expiration);

        assertEq(id1, 0);
        assertEq(id2, 1);
    }

    function test_createListing_revertsIfZeroQuantity() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        vm.expectRevert(SimplrErrors.ZeroQuantity.selector);
        marketplace.createListing(address(eventContract), TIER_ID, 0, LISTING_PRICE, expiration);
    }

    function test_createListing_revertsIfZeroPrice() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        vm.expectRevert(SimplrErrors.ZeroPrice.selector);
        marketplace.createListing(address(eventContract), TIER_ID, 1, 0, expiration);
    }

    function test_createListing_revertsIfExpiredExpiration() public {
        uint256 expiration = block.timestamp - 1; // Past

        vm.prank(seller);
        vm.expectRevert(SimplrErrors.InvalidExpiration.selector);
        marketplace.createListing(address(eventContract), TIER_ID, 1, LISTING_PRICE, expiration);
    }

    // ============ Cancel Listing Tests ============

    function test_cancelListing_cancelsListing() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        vm.prank(seller);
        marketplace.cancelListing(listingId);

        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertFalse(listing.active);
    }

    function test_cancelListing_emitsEvent() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        vm.prank(seller);
        vm.expectEmit(true, false, false, false);
        emit IMarketplace.ListingCancelled(listingId);
        marketplace.cancelListing(listingId);
    }

    function test_cancelListing_revertsIfNotSeller() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        vm.prank(buyer);
        vm.expectRevert(SimplrErrors.NotSeller.selector);
        marketplace.cancelListing(listingId);
    }

    function test_cancelListing_revertsIfListingDoesNotExist() public {
        vm.prank(seller);
        vm.expectRevert(SimplrErrors.ListingDoesNotExist.selector);
        marketplace.cancelListing(999);
    }

    // ============ Update Listing Price Tests ============

    function test_updateListingPrice_updatesPrice() public {
        uint256 expiration = block.timestamp + 1 days;
        uint256 newPrice = 3 ether;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        vm.prank(seller);
        marketplace.updateListingPrice(listingId, newPrice);

        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(listing.pricePerUnit, newPrice);
    }

    function test_updateListingPrice_emitsEvent() public {
        uint256 expiration = block.timestamp + 1 days;
        uint256 newPrice = 3 ether;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        vm.prank(seller);
        vm.expectEmit(true, false, false, true);
        emit IMarketplace.ListingPriceUpdated(listingId, newPrice);
        marketplace.updateListingPrice(listingId, newPrice);
    }

    function test_updateListingPrice_revertsIfNotSeller() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        vm.prank(buyer);
        vm.expectRevert(SimplrErrors.NotSeller.selector);
        marketplace.updateListingPrice(listingId, 3 ether);
    }

    function test_updateListingPrice_revertsIfZeroPrice() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        vm.prank(seller);
        vm.expectRevert(SimplrErrors.ZeroPrice.selector);
        marketplace.updateListingPrice(listingId, 0);
    }

    // ============ Buy Listing Tests ============

    function test_buyListing_transfersTickets() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        uint256 quantity = 2;
        uint256 totalPrice = LISTING_PRICE * quantity;

        vm.prank(buyer);
        marketplace.buyListing{value: totalPrice}(listingId, quantity);

        assertEq(eventContract.balanceOf(buyer, TIER_ID), quantity);
    }

    function test_buyListing_distributesPaymentWithRoyalty() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        uint256 quantity = 2;
        uint256 totalPrice = LISTING_PRICE * quantity;
        uint256 royaltyAmount = totalPrice * ROYALTY_BPS / 10000;
        uint256 sellerProceeds = totalPrice - royaltyAmount;

        uint256 sellerBalanceBefore = seller.balance;
        uint256 organizerBalanceBefore = organizer.balance;

        vm.prank(buyer);
        marketplace.buyListing{value: totalPrice}(listingId, quantity);

        assertEq(seller.balance, sellerBalanceBefore + sellerProceeds);
        assertEq(organizer.balance, organizerBalanceBefore + royaltyAmount);
    }

    function test_buyListing_emitsEvent() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        uint256 quantity = 2;
        uint256 totalPrice = LISTING_PRICE * quantity;
        uint256 royaltyAmount = totalPrice * ROYALTY_BPS / 10000;

        vm.prank(buyer);
        vm.expectEmit(true, true, false, true);
        emit IMarketplace.ListingPurchased(listingId, buyer, quantity, totalPrice, royaltyAmount, organizer);
        marketplace.buyListing{value: totalPrice}(listingId, quantity);
    }

    function test_buyListing_updatesListingQuantity() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        uint256 quantity = 2;
        uint256 totalPrice = LISTING_PRICE * quantity;

        vm.prank(buyer);
        marketplace.buyListing{value: totalPrice}(listingId, quantity);

        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(listing.quantity, 1);
        assertTrue(listing.active);
    }

    function test_buyListing_deactivatesWhenSoldOut() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        uint256 quantity = 3;
        uint256 totalPrice = LISTING_PRICE * quantity;

        vm.prank(buyer);
        marketplace.buyListing{value: totalPrice}(listingId, quantity);

        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(listing.quantity, 0);
        assertFalse(listing.active);
    }

    function test_buyListing_revertsIfListingNotActive() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        vm.prank(seller);
        marketplace.cancelListing(listingId);

        vm.prank(buyer);
        vm.expectRevert(SimplrErrors.ListingNotActive.selector);
        marketplace.buyListing{value: LISTING_PRICE}(listingId, 1);
    }

    function test_buyListing_revertsIfListingExpired() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        // Warp past expiration
        vm.warp(expiration + 1);

        vm.prank(buyer);
        vm.expectRevert(SimplrErrors.ListingExpired.selector);
        marketplace.buyListing{value: LISTING_PRICE}(listingId, 1);
    }

    function test_buyListing_revertsIfInsufficientQuantity() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        vm.prank(buyer);
        vm.expectRevert(SimplrErrors.InsufficientQuantity.selector);
        marketplace.buyListing{value: LISTING_PRICE * 5}(listingId, 5);
    }

    function test_buyListing_revertsIfIncorrectPayment() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        vm.prank(buyer);
        vm.expectRevert(SimplrErrors.IncorrectPayment.selector);
        marketplace.buyListing{value: LISTING_PRICE - 1}(listingId, 1);
    }

    function test_buyListing_revertsIfZeroQuantity() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(eventContract), TIER_ID, 3, LISTING_PRICE, expiration);

        vm.prank(buyer);
        vm.expectRevert(SimplrErrors.ZeroQuantity.selector);
        marketplace.buyListing{value: 0}(listingId, 0);
    }

    // ============ View Functions Tests ============

    function test_totalListings_returnsCorrectCount() public {
        uint256 expiration = block.timestamp + 1 days;

        vm.startPrank(seller);
        marketplace.createListing(address(eventContract), TIER_ID, 1, LISTING_PRICE, expiration);
        marketplace.createListing(address(eventContract), TIER_ID, 1, LISTING_PRICE, expiration);
        vm.stopPrank();

        assertEq(marketplace.totalListings(), 2);
    }

    function test_getListing_returnsDefaultForNonExistent() public view {
        IMarketplace.Listing memory listing = marketplace.getListing(999);
        assertEq(listing.seller, address(0));
        assertFalse(listing.active);
    }
}
