// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Contract imports
import {StakedPDTTestBase} from "./StakedPDT_base.sol";

contract StakedPDTUnregisterRewardTokenTest is StakedPDTTestBase {
    function test_unregisterRewardToken() public {
        // only TOKEN_MANAGER role should unregister reward token
        vm.startPrank(tokenManager);
        bStakedPDT.registerNewRewardToken(bPROMPTAddress);
        vm.stopPrank();

        vm.startPrank(epochManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                epochManager,
                TOKEN_MANAGER
            )
        );
        bStakedPDT.unregisterRewardToken(1);
        vm.stopPrank();

        vm.startPrank(staker1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                staker1,
                TOKEN_MANAGER
            )
        );
        bStakedPDT.unregisterRewardToken(1);
        vm.stopPrank();

        // should revert if unregistering token index is out of range
        vm.startPrank(tokenManager);
        vm.expectRevert("Index out of bounds");
        bStakedPDT.unregisterRewardToken(2);
        vm.stopPrank();

        // rewardTokenList size should be deducted after unregister
        vm.expectRevert();
        bStakedPDT.rewardTokenList(2);
        assertEq(bStakedPDT.rewardTokenList(1), bPROMPTAddress);

        vm.startPrank(tokenManager);
        // should emit {UnregisterRewardToken} event
        vm.expectEmit();
        emit UnregisterRewardToken(bStakedPDT.currentEpochId(), bPROMPTAddress);
        bStakedPDT.unregisterRewardToken(1);
        vm.stopPrank();

        vm.expectRevert();
        bStakedPDT.rewardTokenList(1);
        assertEq(bStakedPDT.rewardTokenList(0), bPRIMEAddress);
    }

    // should be able to remove any reward token
    function test_unregisterRewardToken_RemoveAnyRewardToken() public {
        vm.startPrank(tokenManager);

        bStakedPDT.registerNewRewardToken(bPROMPTAddress);
        bStakedPDT.unregisterRewardToken(0);
        assertEq(bStakedPDT.rewardTokenList(0), bPROMPTAddress);

        vm.expectRevert();
        bStakedPDT.rewardTokenList(1);

        bStakedPDT.unregisterRewardToken(0);
        vm.expectRevert();
        bStakedPDT.rewardTokenList(0);

        vm.stopPrank();
    }
}
