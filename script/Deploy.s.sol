// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {EventFactory} from "../src/EventFactory.sol";
import {Event} from "../src/Event.sol";
import {Marketplace} from "../src/Marketplace.sol";

/// @title Deploy
/// @notice Deployment script for the event ticketing system
contract Deploy is Script {
    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Event implementation
        Event eventImplementation = new Event();
        console.log("Event Implementation deployed at:", address(eventImplementation));

        // 2. Deploy EventFactory with implementation
        EventFactory factory = new EventFactory(address(eventImplementation));
        console.log("EventFactory deployed at:", address(factory));

        // 3. Deploy Marketplace
        Marketplace marketplace = new Marketplace();
        console.log("Marketplace deployed at:", address(marketplace));

        vm.stopBroadcast();

        // Summary
        console.log("\n=== Deployment Summary ===");
        console.log("Event Implementation:", address(eventImplementation));
        console.log("EventFactory:", address(factory));
        console.log("Marketplace:", address(marketplace));
    }
}

/// @title DeployLocal
/// @notice Deployment script for local development (Anvil)
contract DeployLocal is Script {
    function run() external {
        // Use default Anvil account
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Event implementation
        Event eventImplementation = new Event();
        console.log("Event Implementation deployed at:", address(eventImplementation));

        // 2. Deploy EventFactory with implementation
        EventFactory factory = new EventFactory(address(eventImplementation));
        console.log("EventFactory deployed at:", address(factory));

        // 3. Deploy Marketplace
        Marketplace marketplace = new Marketplace();
        console.log("Marketplace deployed at:", address(marketplace));

        vm.stopBroadcast();

        // Summary
        console.log("\n=== Deployment Summary ===");
        console.log("Event Implementation:", address(eventImplementation));
        console.log("EventFactory:", address(factory));
        console.log("Marketplace:", address(marketplace));
    }
}
