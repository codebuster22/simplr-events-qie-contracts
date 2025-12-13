// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import {Script, console} from "forge-std/Script.sol";
import {Multicall3} from "../src/Multicall3.sol";

/// @notice Minimal interface for EventFactory verification
interface IEventFactoryMinimal {
    function totalEvents() external view returns (uint256);
    function implementation() external view returns (address);
    function accessPassNFTImplementation() external view returns (address);
}

/// @title DeployMulticall3
/// @notice Deployment script for Multicall3 contract
contract DeployMulticall3 is Script {
    function run() external returns (address) {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Multicall3
        Multicall3 multicall3 = new Multicall3();
        console.log("Multicall3 deployed at:", address(multicall3));

        vm.stopBroadcast();

        // Verify Multicall3 deployment by calling aggregate3
        _verifyMulticall3(multicall3);

        // Return the deployed address
        return address(multicall3);
    }

    /// @notice Verify Multicall3 deployment by making aggregate3 calls to EventFactory
    /// @param multicall3 The deployed Multicall3 instance
    function _verifyMulticall3(Multicall3 multicall3) internal {
        // Get EventFactory address from environment or use a known deployed address
        address eventFactoryAddress = vm.envOr("FACTORY_ADDRESS", address(0x9aF4D4D674E3B405f0FC1f78554FEAeECCE80342));
        
        if (eventFactoryAddress == address(0)) {
            console.log("Skipping verification: FACTORY_ADDRESS not set");
            return;
        }

        console.log("\n=== Verifying Multicall3 Deployment ===");
        console.log("Using EventFactory at:", eventFactoryAddress);

        // Prepare 3 calls to EventFactory
        Multicall3.Call3[] memory calls = new Multicall3.Call3[](3);

        // Call 1: totalEvents()
        calls[0] = Multicall3.Call3({
            target: eventFactoryAddress,
            allowFailure: false,
            callData: abi.encodeWithSelector(IEventFactoryMinimal.totalEvents.selector)
        });

        // Call 2: implementation()
        calls[1] = Multicall3.Call3({
            target: eventFactoryAddress,
            allowFailure: false,
            callData: abi.encodeWithSelector(IEventFactoryMinimal.implementation.selector)
        });

        // Call 3: accessPassNFTImplementation()
        calls[2] = Multicall3.Call3({
            target: eventFactoryAddress,
            allowFailure: false,
            callData: abi.encodeWithSelector(IEventFactoryMinimal.accessPassNFTImplementation.selector)
        });

        // Execute aggregate3 call
        Multicall3.Result[] memory results = multicall3.aggregate3(calls);

        // Decode and log results
        uint256 totalEvents = abi.decode(results[0].returnData, (uint256));
        address implementation = abi.decode(results[1].returnData, (address));
        address accessPassNFTImpl = abi.decode(results[2].returnData, (address));

        console.log("\nMulticall3 Verification Results:");
        console.log("- Total Events:", totalEvents);
        console.log("- Event Implementation:", implementation);
        console.log("- AccessPassNFT Implementation:", accessPassNFTImpl);
        console.log("\nMulticall3 verification successful!");
    }
}

/// @title DeployMulticall3Local
/// @notice Deployment script for Multicall3 on local development (Anvil)
contract DeployMulticall3Local is Script {
    function run() external returns (address) {
        // Use default Anvil account
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Multicall3
        Multicall3 multicall3 = new Multicall3();
        console.log("Multicall3 deployed at:", address(multicall3));

        vm.stopBroadcast();

        // Verify Multicall3 deployment by calling aggregate3
        _verifyMulticall3(multicall3);

        // Return the deployed address
        return address(multicall3);
    }

    /// @notice Verify Multicall3 deployment by making aggregate3 calls to EventFactory
    /// @param multicall3 The deployed Multicall3 instance
    function _verifyMulticall3(Multicall3 multicall3) internal {
        // Get EventFactory address from environment or use a known deployed address
        address eventFactoryAddress = vm.envOr("EVENT_FACTORY_ADDRESS", address(0x8C4556d5d06A7A5C41FbC8C24A8c570E118840DA));
        
        if (eventFactoryAddress == address(0)) {
            console.log("Skipping verification: EVENT_FACTORY_ADDRESS not set");
            return;
        }

        console.log("\n=== Verifying Multicall3 Deployment ===");
        console.log("Using EventFactory at:", eventFactoryAddress);

        // Prepare 3 calls to EventFactory
        Multicall3.Call3[] memory calls = new Multicall3.Call3[](3);

        // Call 1: totalEvents()
        calls[0] = Multicall3.Call3({
            target: eventFactoryAddress,
            allowFailure: false,
            callData: abi.encodeWithSelector(IEventFactoryMinimal.totalEvents.selector)
        });

        // Call 2: implementation()
        calls[1] = Multicall3.Call3({
            target: eventFactoryAddress,
            allowFailure: false,
            callData: abi.encodeWithSelector(IEventFactoryMinimal.implementation.selector)
        });

        // Call 3: accessPassNFTImplementation()
        calls[2] = Multicall3.Call3({
            target: eventFactoryAddress,
            allowFailure: false,
            callData: abi.encodeWithSelector(IEventFactoryMinimal.accessPassNFTImplementation.selector)
        });

        // Execute aggregate3 call
        Multicall3.Result[] memory results = multicall3.aggregate3(calls);

        // Decode and log results
        uint256 totalEvents = abi.decode(results[0].returnData, (uint256));
        address implementation = abi.decode(results[1].returnData, (address));
        address accessPassNFTImpl = abi.decode(results[2].returnData, (address));

        console.log("\nMulticall3 Verification Results:");
        console.log("- Total Events:", totalEvents);
        console.log("- Event Implementation:", implementation);
        console.log("- AccessPassNFT Implementation:", accessPassNFTImpl);
        console.log("\nMulticall3 verification successful!");
    }
}
