// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Event} from "../src/Event.sol";
import {AccessPassNFT} from "../src/AccessPassNFT.sol";
import {IEvent} from "../src/interfaces/IEvent.sol";
import {IAccessPassNFT} from "../src/interfaces/IAccessPassNFT.sol";
import {SimplrErrors} from "../src/libraries/SimplrErrors.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract EventTest is Test, IERC1155Receiver {
    Event public eventImplementation;
    Event public eventContract;
    AccessPassNFT public accessPassImplementation;
    AccessPassNFT public accessPass;

    address public admin;
    address public gatekeeper1;
    address public gatekeeper2;
    address public user1;
    address public user2;

    IEvent.EventConfig public eventConfig;
    IEvent.TierConfig[] public tierConfigs;
    address[] public initialGatekeepers;

    uint256 constant VIP_TIER_ID = 1;
    uint256 constant GA_TIER_ID = 2;
    uint256 constant VIP_PRICE = 1 ether;
    uint256 constant GA_PRICE = 0.1 ether;
    uint256 constant VIP_MAX_SUPPLY = 100;
    uint256 constant GA_MAX_SUPPLY = 1000;

    function setUp() public {
        admin = makeAddr("admin");
        gatekeeper1 = makeAddr("gatekeeper1");
        gatekeeper2 = makeAddr("gatekeeper2");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Fund users
        vm.deal(user1, 200 ether);
        vm.deal(user2, 200 ether);

        // Setup event config
        eventConfig = IEvent.EventConfig({
            name: "Test Event",
            symbol: "TE",
            baseURI: "https://api.example.com/",
            royaltyBps: 500 // 5%
        });

        // Setup tier configs
        tierConfigs.push(
            IEvent.TierConfig({tierId: VIP_TIER_ID, tierName: "VIP", price: VIP_PRICE, maxSupply: VIP_MAX_SUPPLY})
        );
        tierConfigs.push(
            IEvent.TierConfig({
                tierId: GA_TIER_ID,
                tierName: "General Admission",
                price: GA_PRICE,
                maxSupply: GA_MAX_SUPPLY
            })
        );

        // Setup initial gatekeepers
        initialGatekeepers.push(gatekeeper1);

        // Deploy implementations
        eventImplementation = new Event();
        accessPassImplementation = new AccessPassNFT();

        // Clone the Event implementation (like the factory does)
        address eventAddress = Clones.clone(address(eventImplementation));
        eventContract = Event(eventAddress);

        // Clone AccessPassNFT implementation and initialize
        accessPass = AccessPassNFT(Clones.clone(address(accessPassImplementation)));
        accessPass.initialize("Test Event Access Pass", "TE-AP", "https://api.example.com/", eventAddress);

        // Initialize Event contract
        eventContract.initialize(eventConfig, tierConfigs, initialGatekeepers, admin, address(accessPass));
    }

    // ============ IERC1155Receiver Implementation ============

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

    // ============ Initialization Tests ============

    function test_initialize_setsNameCorrectly() public view {
        assertEq(eventContract.name(), eventConfig.name);
    }

    function test_initialize_setsSymbolCorrectly() public view {
        assertEq(eventContract.symbol(), eventConfig.symbol);
    }

    function test_initialize_setsAccessPassNFT() public view {
        assertEq(eventContract.accessPassNFT(), address(accessPass));
    }

    function test_initialize_setsOwner() public view {
        assertEq(eventContract.owner(), admin);
    }

    function test_initialize_setsGatekeeperRole() public view {
        assertTrue(eventContract.isGatekeeper(gatekeeper1));
    }

    function test_initialize_createsTiers() public view {
        IEvent.Tier memory vipTier = eventContract.getTier(VIP_TIER_ID);
        assertEq(vipTier.price, VIP_PRICE);
        assertEq(vipTier.maxSupply, VIP_MAX_SUPPLY);
        assertEq(vipTier.tierName, "VIP");
        assertTrue(vipTier.active);

        IEvent.Tier memory gaTier = eventContract.getTier(GA_TIER_ID);
        assertEq(gaTier.price, GA_PRICE);
        assertEq(gaTier.maxSupply, GA_MAX_SUPPLY);
        assertEq(gaTier.tierName, "General Admission");
        assertTrue(gaTier.active);
    }

    function test_initialize_revertsOnSecondCall() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        eventContract.initialize(eventConfig, tierConfigs, initialGatekeepers, admin, address(accessPass));
    }

    // ============ Tier Management Tests ============

    function test_createTier_createsNewTier() public {
        uint256 newTierId = 3;
        string memory tierName = "Premium";
        uint256 price = 0.5 ether;
        uint256 maxSupply = 500;

        vm.prank(admin);
        eventContract.createTier(newTierId, tierName, price, maxSupply);

        IEvent.Tier memory tier = eventContract.getTier(newTierId);
        assertEq(tier.price, price);
        assertEq(tier.maxSupply, maxSupply);
        assertEq(tier.tierName, tierName);
        assertTrue(tier.active);
    }

    function test_createTier_emitsTierCreatedEvent() public {
        uint256 newTierId = 3;
        string memory tierName = "Premium";
        uint256 price = 0.5 ether;
        uint256 maxSupply = 500;

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IEvent.TierCreated(newTierId, tierName, price, maxSupply);
        eventContract.createTier(newTierId, tierName, price, maxSupply);
    }

    function test_createTier_revertsIfTierExists() public {
        vm.prank(admin);
        vm.expectRevert(SimplrErrors.TierAlreadyExists.selector);
        eventContract.createTier(VIP_TIER_ID, "VIP2", 2 ether, 50);
    }

    function test_createTier_revertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        eventContract.createTier(3, "Premium", 0.5 ether, 500);
    }

    function test_createTier_revertsIfZeroMaxSupply() public {
        vm.prank(admin);
        vm.expectRevert(SimplrErrors.ZeroMaxSupply.selector);
        eventContract.createTier(3, "Premium", 0.5 ether, 0);
    }

    function test_updateTier_updatesPriceAndMaxSupply() public {
        uint256 newPrice = 2 ether;
        uint256 newMaxSupply = 200;

        vm.prank(admin);
        eventContract.updateTier(VIP_TIER_ID, newPrice, newMaxSupply);

        IEvent.Tier memory tier = eventContract.getTier(VIP_TIER_ID);
        assertEq(tier.price, newPrice);
        assertEq(tier.maxSupply, newMaxSupply);
    }

    function test_updateTier_emitsTierUpdatedEvent() public {
        uint256 newPrice = 2 ether;
        uint256 newMaxSupply = 200;

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IEvent.TierUpdated(VIP_TIER_ID, newPrice, newMaxSupply);
        eventContract.updateTier(VIP_TIER_ID, newPrice, newMaxSupply);
    }

    function test_updateTier_revertsIfTierDoesNotExist() public {
        vm.prank(admin);
        vm.expectRevert(SimplrErrors.TierDoesNotExist.selector);
        eventContract.updateTier(999, 1 ether, 100);
    }

    function test_updateTier_revertsIfReducingBelowSupply() public {
        // First, buy some tickets
        vm.prank(user1);
        eventContract.buyTickets{value: VIP_PRICE * 10}(VIP_TIER_ID, 10);

        // Try to reduce max supply below current supply
        vm.prank(admin);
        vm.expectRevert(SimplrErrors.CannotReduceBelowSupply.selector);
        eventContract.updateTier(VIP_TIER_ID, VIP_PRICE, 5);
    }

    function test_setTierActive_deactivatesTier() public {
        vm.prank(admin);
        eventContract.setTierActive(VIP_TIER_ID, false);

        IEvent.Tier memory tier = eventContract.getTier(VIP_TIER_ID);
        assertFalse(tier.active);
    }

    function test_setTierActive_reactivatesTier() public {
        vm.prank(admin);
        eventContract.setTierActive(VIP_TIER_ID, false);

        vm.prank(admin);
        eventContract.setTierActive(VIP_TIER_ID, true);

        IEvent.Tier memory tier = eventContract.getTier(VIP_TIER_ID);
        assertTrue(tier.active);
    }

    function test_setTierActive_emitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IEvent.TierActiveStatusChanged(VIP_TIER_ID, false);
        eventContract.setTierActive(VIP_TIER_ID, false);
    }

    // ============ Gatekeeper Management Tests ============

    function test_addGatekeeper_addsGatekeeper() public {
        vm.prank(admin);
        eventContract.addGatekeeper(gatekeeper2);

        assertTrue(eventContract.isGatekeeper(gatekeeper2));
    }

    function test_addGatekeeper_emitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit IEvent.GatekeeperAdded(gatekeeper2);
        eventContract.addGatekeeper(gatekeeper2);
    }

    function test_removeGatekeeper_removesGatekeeper() public {
        vm.prank(admin);
        eventContract.removeGatekeeper(gatekeeper1);

        assertFalse(eventContract.isGatekeeper(gatekeeper1));
    }

    function test_removeGatekeeper_emitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit IEvent.GatekeeperRemoved(gatekeeper1);
        eventContract.removeGatekeeper(gatekeeper1);
    }

    // ============ Buy Tickets Tests ============

    function test_buyTickets_mintsTickets() public {
        uint256 quantity = 5;

        vm.prank(user1);
        eventContract.buyTickets{value: VIP_PRICE * quantity}(VIP_TIER_ID, quantity);

        assertEq(eventContract.balanceOf(user1, VIP_TIER_ID), quantity);
    }

    function test_buyTickets_emitsEvent() public {
        uint256 quantity = 5;

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit IEvent.TicketsPurchased(user1, VIP_TIER_ID, quantity, VIP_PRICE * quantity);
        eventContract.buyTickets{value: VIP_PRICE * quantity}(VIP_TIER_ID, quantity);
    }

    function test_buyTickets_revertsIfTierNotActive() public {
        vm.prank(admin);
        eventContract.setTierActive(VIP_TIER_ID, false);

        vm.prank(user1);
        vm.expectRevert(SimplrErrors.TierNotActive.selector);
        eventContract.buyTickets{value: VIP_PRICE}(VIP_TIER_ID, 1);
    }

    function test_buyTickets_revertsIfExceedsMaxSupply() public {
        vm.prank(user1);
        vm.expectRevert(SimplrErrors.ExceedsMaxSupply.selector);
        eventContract.buyTickets{value: VIP_PRICE * (VIP_MAX_SUPPLY + 1)}(VIP_TIER_ID, VIP_MAX_SUPPLY + 1);
    }

    function test_buyTickets_revertsIfIncorrectPayment() public {
        vm.prank(user1);
        vm.expectRevert(SimplrErrors.IncorrectPayment.selector);
        eventContract.buyTickets{value: VIP_PRICE - 1}(VIP_TIER_ID, 1);
    }

    function test_buyTickets_revertsIfZeroQuantity() public {
        vm.prank(user1);
        vm.expectRevert(SimplrErrors.ZeroQuantity.selector);
        eventContract.buyTickets{value: 0}(VIP_TIER_ID, 0);
    }

    function test_buyTickets_revertsIfTierDoesNotExist() public {
        vm.prank(user1);
        vm.expectRevert(SimplrErrors.TierDoesNotExist.selector);
        eventContract.buyTickets{value: 1 ether}(999, 1);
    }

    // ============ Redeem Ticket Tests ============

    function test_redeemTicket_burnsTicketAndMintsAccessPass() public {
        // Use vm.createWallet for signing
        (address signer, uint256 signerPk) = makeAddrAndKey("signer");

        // Buy ticket for signer
        vm.deal(signer, 10 ether);
        vm.prank(signer);
        eventContract.buyTickets{value: VIP_PRICE}(VIP_TIER_ID, 1);

        // Create proper signature
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _getRedeemDigest(signer, VIP_TIER_ID, eventContract.nonces(signer), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Check initial state
        assertEq(eventContract.balanceOf(signer, VIP_TIER_ID), 1);

        // Redeem
        vm.prank(gatekeeper1);
        eventContract.redeemTicket(signer, VIP_TIER_ID, deadline, signature);

        // Check final state
        assertEq(eventContract.balanceOf(signer, VIP_TIER_ID), 0);

        // Check access pass was minted
        assertEq(accessPass.ownerOf(1), signer);
    }

    function test_redeemTicket_emitsEvent() public {
        (address signer, uint256 signerPk) = makeAddrAndKey("signer2");

        vm.deal(signer, 10 ether);
        vm.prank(signer);
        eventContract.buyTickets{value: VIP_PRICE}(VIP_TIER_ID, 1);

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _getRedeemDigest(signer, VIP_TIER_ID, eventContract.nonces(signer), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(gatekeeper1);
        vm.expectEmit(true, true, false, true);
        emit IEvent.TicketRedeemed(signer, VIP_TIER_ID, 1);
        eventContract.redeemTicket(signer, VIP_TIER_ID, deadline, signature);
    }

    function test_redeemTicket_revertsIfNotGatekeeper() public {
        (address signer, uint256 signerPk) = makeAddrAndKey("signer3");

        vm.deal(signer, 10 ether);
        vm.prank(signer);
        eventContract.buyTickets{value: VIP_PRICE}(VIP_TIER_ID, 1);

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _getRedeemDigest(signer, VIP_TIER_ID, eventContract.nonces(signer), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(user2);
        vm.expectRevert(SimplrErrors.NotGatekeeper.selector);
        eventContract.redeemTicket(signer, VIP_TIER_ID, deadline, signature);
    }

    function test_redeemTicket_revertsIfSignatureExpired() public {
        (address signer, uint256 signerPk) = makeAddrAndKey("signer4");

        vm.deal(signer, 10 ether);
        vm.prank(signer);
        eventContract.buyTickets{value: VIP_PRICE}(VIP_TIER_ID, 1);

        uint256 deadline = block.timestamp - 1; // Expired
        bytes32 digest = _getRedeemDigest(signer, VIP_TIER_ID, eventContract.nonces(signer), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(gatekeeper1);
        vm.expectRevert(SimplrErrors.SignatureExpired.selector);
        eventContract.redeemTicket(signer, VIP_TIER_ID, deadline, signature);
    }

    function test_redeemTicket_revertsIfInvalidSignature() public {
        (address signer,) = makeAddrAndKey("signer5");
        (, uint256 wrongPk) = makeAddrAndKey("wrongSigner");

        vm.deal(signer, 10 ether);
        vm.prank(signer);
        eventContract.buyTickets{value: VIP_PRICE}(VIP_TIER_ID, 1);

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _getRedeemDigest(signer, VIP_TIER_ID, eventContract.nonces(signer), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(gatekeeper1);
        vm.expectRevert(SimplrErrors.InvalidSignature.selector);
        eventContract.redeemTicket(signer, VIP_TIER_ID, deadline, signature);
    }

    function test_redeemTicket_revertsIfNoTicket() public {
        (address signer, uint256 signerPk) = makeAddrAndKey("signer6");

        // Don't buy any tickets

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _getRedeemDigest(signer, VIP_TIER_ID, eventContract.nonces(signer), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(gatekeeper1);
        vm.expectRevert(SimplrErrors.InsufficientTickets.selector);
        eventContract.redeemTicket(signer, VIP_TIER_ID, deadline, signature);
    }

    // ============ Withdraw Tests ============

    function test_withdraw_sendsETHToRecipient() public {
        // Buy some tickets to accumulate funds
        vm.prank(user1);
        eventContract.buyTickets{value: VIP_PRICE * 10}(VIP_TIER_ID, 10);

        uint256 contractBalance = address(eventContract).balance;
        uint256 recipientBalanceBefore = admin.balance;

        vm.prank(admin);
        eventContract.withdraw(admin);

        assertEq(address(eventContract).balance, 0);
        assertEq(admin.balance, recipientBalanceBefore + contractBalance);
    }

    function test_withdraw_emitsEvent() public {
        vm.prank(user1);
        eventContract.buyTickets{value: VIP_PRICE * 10}(VIP_TIER_ID, 10);

        uint256 contractBalance = address(eventContract).balance;

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IEvent.FundsWithdrawn(admin, contractBalance);
        eventContract.withdraw(admin);
    }

    function test_withdraw_revertsIfNotOwner() public {
        vm.prank(user1);
        eventContract.buyTickets{value: VIP_PRICE}(VIP_TIER_ID, 1);

        vm.prank(user1);
        vm.expectRevert();
        eventContract.withdraw(user1);
    }

    // ============ Royalty Tests ============

    function test_royaltyInfo_returnsCorrectRoyalty() public view {
        uint256 salePrice = 1 ether;
        (address receiver, uint256 royaltyAmount) = eventContract.royaltyInfo(VIP_TIER_ID, salePrice);

        assertEq(receiver, admin);
        assertEq(royaltyAmount, (salePrice * 500) / 10000); // 5%
    }

    // ============ Helper Functions ============

    function _getRedeemDigest(address ticketHolder, uint256 tierId, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 REDEMPTION_TYPEHASH =
            keccak256("RedeemTicket(address ticketHolder,uint256 tierId,uint256 nonce,uint256 deadline)");

        bytes32 structHash = keccak256(abi.encode(REDEMPTION_TYPEHASH, ticketHolder, tierId, nonce, deadline));

        bytes32 domainSeparator = eventContract.DOMAIN_SEPARATOR();
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
