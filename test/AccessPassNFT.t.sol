// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AccessPassNFT} from "../src/AccessPassNFT.sol";
import {IAccessPassNFT} from "../src/interfaces/IAccessPassNFT.sol";
import {SimplrErrors} from "../src/libraries/SimplrErrors.sol";

contract AccessPassNFTTest is Test {
    AccessPassNFT public accessPass;

    address public eventContract;
    address public user1;
    address public user2;

    string constant NAME = "Event Access Pass";
    string constant SYMBOL = "EAP";
    string constant BASE_URI = "https://api.example.com/metadata/";

    function setUp() public {
        eventContract = makeAddr("eventContract");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy AccessPassNFT
        accessPass = new AccessPassNFT(NAME, SYMBOL, BASE_URI);

        // Link to event contract
        accessPass.setEventContract(eventContract);
    }

    // ============ Constructor Tests ============

    function test_constructor_setsNameCorrectly() public view {
        assertEq(accessPass.name(), NAME);
    }

    function test_constructor_setsSymbolCorrectly() public view {
        assertEq(accessPass.symbol(), SYMBOL);
    }

    function test_setEventContract_setsEventContractCorrectly() public view {
        assertEq(accessPass.eventContract(), eventContract);
    }

    function test_setEventContract_revertsOnSecondCall() public {
        vm.expectRevert(SimplrErrors.EventContractAlreadySet.selector);
        accessPass.setEventContract(user1);
    }

    function test_setEventContract_revertsOnZeroAddress() public {
        // Deploy new AccessPassNFT without setting event contract
        AccessPassNFT newAccessPass = new AccessPassNFT(NAME, SYMBOL, BASE_URI);

        vm.expectRevert(SimplrErrors.ZeroAddress.selector);
        newAccessPass.setEventContract(address(0));
    }

    function test_constructor_setsLockDurationTo24Hours() public view {
        assertEq(accessPass.lockDuration(), 24 hours);
    }

    // ============ Mint Tests ============

    function test_mint_mintsTokenToRecipient() public {
        uint256 tierId = 1;

        vm.prank(eventContract);
        uint256 tokenId = accessPass.mint(user1, tierId);

        assertEq(accessPass.ownerOf(tokenId), user1);
    }

    function test_mint_returnsIncrementingTokenIds() public {
        vm.startPrank(eventContract);

        uint256 tokenId1 = accessPass.mint(user1, 1);
        uint256 tokenId2 = accessPass.mint(user2, 2);

        vm.stopPrank();

        assertEq(tokenId1, 1);
        assertEq(tokenId2, 2);
    }

    function test_mint_storesCorrectMetadata() public {
        uint256 tierId = 5;
        uint256 mintTime = block.timestamp;

        vm.prank(eventContract);
        uint256 tokenId = accessPass.mint(user1, tierId);

        IAccessPassNFT.PassMetadata memory metadata = accessPass.getMetadata(tokenId);
        assertEq(metadata.tierId, tierId);
        assertEq(metadata.mintTimestamp, mintTime);
    }

    function test_mint_emitsAccessPassMintedEvent() public {
        uint256 tierId = 3;

        vm.prank(eventContract);
        vm.expectEmit(true, true, true, true);
        emit IAccessPassNFT.AccessPassMinted(1, user1, tierId);
        accessPass.mint(user1, tierId);
    }

    function test_mint_revertsWhenCalledByNonEventContract() public {
        vm.prank(user1);
        vm.expectRevert(SimplrErrors.NotAuthorizedMinter.selector);
        accessPass.mint(user1, 1);
    }

    // ============ Transfer Lock Tests ============

    function test_isTransferable_returnsFalseImmediatelyAfterMint() public {
        vm.prank(eventContract);
        uint256 tokenId = accessPass.mint(user1, 1);

        assertFalse(accessPass.isTransferable(tokenId));
    }

    function test_isTransferable_returnsTrueAfter24Hours() public {
        vm.prank(eventContract);
        uint256 tokenId = accessPass.mint(user1, 1);

        // Warp 24 hours + 1 second
        vm.warp(block.timestamp + 24 hours + 1);

        assertTrue(accessPass.isTransferable(tokenId));
    }

    function test_transfer_revertsWhenLockedViaTransferFrom() public {
        vm.prank(eventContract);
        uint256 tokenId = accessPass.mint(user1, 1);

        vm.prank(user1);
        vm.expectRevert(SimplrErrors.TransferLocked.selector);
        accessPass.transferFrom(user1, user2, tokenId);
    }

    function test_transfer_revertsWhenLockedViaSafeTransferFrom() public {
        vm.prank(eventContract);
        uint256 tokenId = accessPass.mint(user1, 1);

        vm.prank(user1);
        vm.expectRevert(SimplrErrors.TransferLocked.selector);
        accessPass.safeTransferFrom(user1, user2, tokenId);
    }

    function test_transfer_succeedsAfter24Hours() public {
        vm.prank(eventContract);
        uint256 tokenId = accessPass.mint(user1, 1);

        // Warp 24 hours + 1 second
        vm.warp(block.timestamp + 24 hours + 1);

        vm.prank(user1);
        accessPass.transferFrom(user1, user2, tokenId);

        assertEq(accessPass.ownerOf(tokenId), user2);
    }

    function test_transferUnlockTime_returnsCorrectTime() public {
        uint256 mintTime = block.timestamp;

        vm.prank(eventContract);
        uint256 tokenId = accessPass.mint(user1, 1);

        assertEq(accessPass.transferUnlockTime(tokenId), mintTime + 24 hours);
    }

    // ============ TokenURI Tests ============

    function test_tokenURI_returnsCorrectURI() public {
        vm.prank(eventContract);
        uint256 tokenId = accessPass.mint(user1, 1);

        string memory expectedURI = string(abi.encodePacked(BASE_URI, "1"));
        assertEq(accessPass.tokenURI(tokenId), expectedURI);
    }
}
