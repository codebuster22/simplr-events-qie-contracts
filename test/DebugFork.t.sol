// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {EventFactory} from "../src/EventFactory.sol";
import {Event} from "../src/Event.sol";
import {IEvent} from "../src/interfaces/IEvent.sol";

contract DebugForkTest is Test {
    function setUp() public {
        vm.createSelectFork("https://rpc1testnet.qie.digital");
    }

    function test_clonesLibraryWorks() public {
        // Clones uses CREATE opcode, not a pre-deployed contract
        SimpleImpl impl = new SimpleImpl();
        console.log("Implementation deployed at:", address(impl));

        address clone = Clones.clone(address(impl));
        console.log("Clone deployed at:", clone);

        SimpleImpl(clone).initialize(42);
        assertEq(SimpleImpl(clone).value(), 42);

        console.log("Clones library works correctly!");
    }

    function test_debugFactoryCall() public {
        EventFactory factory = EventFactory(0x5120F677C9a453AC960eCA1fb274D25D96aAAdC5);

        console.log("Factory implementation:", factory.implementation());

        // Check implementation bytecode exists
        address impl = factory.implementation();
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(impl)
        }
        console.log("Implementation code size:", codeSize);

        // Try to manually clone and initialize
        address eventClone = Clones.clone(impl);
        console.log("Manual clone created at:", eventClone);

        // Check clone bytecode
        uint256 cloneCodeSize;
        assembly {
            cloneCodeSize := extcodesize(eventClone)
        }
        console.log("Clone code size:", cloneCodeSize);
    }

    function test_fullCreateEventDebug() public {
        EventFactory factory = EventFactory(0x5120F677C9a453AC960eCA1fb274D25D96aAAdC5);

        address deployer = makeAddr("deployer");
        vm.deal(deployer, 10 ether);

        IEvent.EventConfig memory eventConfig = IEvent.EventConfig({
            name: "Debug Event",
            symbol: "DBG",
            baseURI: "https://test.com/",
            royaltyBps: 500
        });

        IEvent.TierConfig[] memory tiers = new IEvent.TierConfig[](1);
        tiers[0] = IEvent.TierConfig({
            tierId: 1,
            tierName: "Standard",
            price: 0.01 ether,
            maxSupply: 100
        });

        address[] memory gatekeepers = new address[](0);

        console.log("About to create event...");
        console.log("Deployer:", deployer);
        console.log("Factory:", address(factory));

        vm.prank(deployer);
        address eventAddress = factory.createEvent(eventConfig, tiers, gatekeepers);

        console.log("Event created at:", eventAddress);
        console.log("AccessPassNFT:", Event(eventAddress).accessPassNFT());
    }
}

contract SimpleImpl {
    uint256 public value;
    bool private initialized;

    function initialize(uint256 _value) external {
        require(!initialized, "Already initialized");
        initialized = true;
        value = _value;
    }
}
