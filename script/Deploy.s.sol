// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {EventFactory} from "../src/EventFactory.sol";
import {Event} from "../src/Event.sol";
import {Marketplace} from "../src/Marketplace.sol";
import {IEvent} from "../src/interfaces/IEvent.sol";
import {IMarketplace} from "../src/interfaces/IMarketplace.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// @title Deploy
/// @notice Deployment script for the event ticketing system
contract Deploy is Script {
    string name = "Sample Event";
    string symbol = "SE";
    string baseURI = "https://api.example.com/metadata/";
    uint96 royaltyBps = 500; // 5%

    // tier 1: VIP
    uint256 vipTierId = 1;
    string vipTierName = "VIP";
    uint256 vipTierPrice = 0.001 ether;
    uint256 vipTierMaxSupply = 100;

    // tier 2: GA
    uint256 gaTierId = 2;
    string gaTierName = "General Admission";
    uint256 gaTierPrice = 0.0001 ether;
    uint256 gaTierMaxSupply = 1000;

    uint256 buyQuantity = 1;

    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // ============ 1. Deploy Core Infrastructure ============

        // Deploy Event implementation (upgradeable)
        Event eventImplementation = new Event();
        console.log("Event Implementation deployed at:", address(eventImplementation));

        // Deploy EventFactory with implementation
        EventFactory factory = new EventFactory(address(eventImplementation));
        console.log("EventFactory deployed at:", address(factory));

        // Deploy Marketplace
        Marketplace marketplace = new Marketplace();
        console.log("Marketplace deployed at:", address(marketplace));

        // ============ 2. Create Sample Event ============

        // Setup event config
        IEvent.EventConfig memory eventConfig = IEvent.EventConfig({
            name: name,
            symbol: symbol,
            baseURI: baseURI,
            royaltyBps: royaltyBps // 5%
        });

        // Setup tier configs
        IEvent.TierConfig[] memory tiers = new IEvent.TierConfig[](2);
        tiers[0] = IEvent.TierConfig({
            tierId: vipTierId,
            tierName: vipTierName,
            price: vipTierPrice,
            maxSupply: vipTierMaxSupply
        });
        tiers[1] =
            IEvent.TierConfig({tierId: gaTierId, tierName: gaTierName, price: gaTierPrice, maxSupply: gaTierMaxSupply});

        // No initial gatekeepers (deployer is owner and can add later)
        address[] memory gatekeepers = new address[](0);

        // Create the event
        address eventAddress = factory.createEvent(eventConfig, tiers, gatekeepers);
        Event eventContract = Event(eventAddress);
        console.log("Event created at:", eventAddress);
        console.log("AccessPassNFT deployed at:", eventContract.accessPassNFT());

        // ============ 3. Buy a General Admission Ticket ============

        eventContract.buyTickets{value: gaTierPrice}(gaTierId, buyQuantity);
        console.log("Bought %d General Admission ticket", buyQuantity);

        // ============ 4. List Ticket on Marketplace ============

        // Approve marketplace to transfer tickets
        IERC1155(eventAddress).setApprovalForAll(address(marketplace), true);
        console.log("Approved marketplace for ticket transfers");

        // Create listing: 1 GA ticket for 0.02 ETH, expires in 30 days
        uint256 listingPrice = gaTierPrice * 2;
        uint256 listingExpiration = block.timestamp + 30 days;

        uint256 listingId =
            marketplace.createListing(eventAddress, gaTierId, buyQuantity, listingPrice, listingExpiration);
        console.log("Created listing ID:", listingId);

        vm.stopBroadcast();

        // ============ Summary ============

        console.log("\n=== Deployment Summary ===");
        console.log("Event Implementation:", address(eventImplementation));
        console.log("EventFactory:", address(factory));
        console.log("Marketplace:", address(marketplace));
        console.log("\n=== Sample Event ===");
        console.log("Event:", eventAddress);
        console.log("AccessPassNFT:", eventContract.accessPassNFT());
        console.log("\n=== Marketplace Listing ===");
        console.log("Listing ID:", listingId);
        console.log("Token ID (Tier):", gaTierId);
        console.log("Price:", listingPrice);
        console.log("Seller:", deployer);
    }
}

/// @title DeployLocal
/// @notice Deployment script for local development (Anvil)
contract DeployLocal is Script {
    function run() external {
        // Use default Anvil account
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // ============ 1. Deploy Core Infrastructure ============

        Event eventImplementation = new Event();
        console.log("Event Implementation:", address(eventImplementation));

        EventFactory factory = new EventFactory(address(eventImplementation));
        console.log("EventFactory:", address(factory));

        Marketplace marketplace = new Marketplace();
        console.log("Marketplace:", address(marketplace));

        // ============ 2. Create Sample Event ============

        IEvent.EventConfig memory eventConfig = IEvent.EventConfig({
            name: "Local Test Event",
            symbol: "LTE",
            baseURI: "https://localhost/metadata/",
            royaltyBps: 500
        });

        IEvent.TierConfig[] memory tiers = new IEvent.TierConfig[](2);
        tiers[0] = IEvent.TierConfig({tierId: 1, tierName: "VIP", price: 0.1 ether, maxSupply: 100});
        tiers[1] = IEvent.TierConfig({tierId: 2, tierName: "General Admission", price: 0.01 ether, maxSupply: 1000});

        address[] memory gatekeepers = new address[](1);
        gatekeepers[0] = deployer;

        address eventAddress = factory.createEvent(eventConfig, tiers, gatekeepers);
        Event eventContract = Event(eventAddress);
        console.log("Event:", eventAddress);
        console.log("AccessPassNFT:", eventContract.accessPassNFT());

        // ============ 3. Buy a General Admission Ticket ============

        uint256 gaTierId = 2;
        eventContract.buyTickets{value: 0.01 ether}(gaTierId, 1);
        console.log("Bought 1 GA ticket");

        // ============ 4. List Ticket on Marketplace ============

        IERC1155(eventAddress).setApprovalForAll(address(marketplace), true);

        uint256 listingId = marketplace.createListing(eventAddress, gaTierId, 1, 0.02 ether, block.timestamp + 30 days);
        console.log("Listed ticket, ID:", listingId);

        vm.stopBroadcast();

        // Summary
        console.log("\n=== Summary ===");
        console.log("EventFactory:", address(factory));
        console.log("Marketplace:", address(marketplace));
        console.log("Event:", eventAddress);
        console.log("Listing ID:", listingId);
    }
}
