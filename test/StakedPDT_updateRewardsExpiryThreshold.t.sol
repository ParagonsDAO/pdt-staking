// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Forge imports
import {console} from "forge-std/Test.sol";

// Contract imports
import {StakedPDTTestBase} from "./StakedPDT_base.sol";

contract StakedPDTUpdateRewardsExpiryThresholdTest is StakedPDTTestBase {
    function test_updateRewardExpiryAfterStake() public {
        /// EPOCH 0

        uint256 POOL_SIZE = 1e18;
        uint256 initialBalance = 1e18;
        bPDTOFT.mint(staker1, initialBalance * 2);
        bPDTOFT.mint(staker2, initialBalance * 2);
        bPDTOFT.mint(staker3, initialBalance * 2);

        //advance to epoch1
        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(0);

        /// EPOCH 1

        //staker1 stake at epoch1, reward expiry threshold is 24
        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, initialBalance * 2);
        bStakedPDT.stake(staker1, initialBalance);
        vm.stopPrank();
        //as the only staker in this epoch, staker1 should get all the epoch1 rewards.

        //advance to epoch2
        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(1);

        /// EPOCH 2

        //staker2 and staker3 stake at epoch2
        vm.startPrank(staker2);
        bPDTOFT.approve(bStakedPDTAddress, initialBalance * 2);
        bStakedPDT.stake(staker2, initialBalance);
        vm.stopPrank();

        vm.startPrank(staker3);
        bPDTOFT.approve(bStakedPDTAddress, initialBalance * 2);
        bStakedPDT.stake(staker3, initialBalance);
        vm.stopPrank();

        //new reward expiry threshold should be greater than 1
        vm.startPrank(owner);

        vm.expectRevert(InvalidRewardsExpiryThreshold.selector);
        bStakedPDT.updateRewardsExpiryThreshold(1);

        bStakedPDT.updateRewardsExpiryThreshold(2);

        vm.stopPrank();

        //advance to epoch3
        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(2);

        /// EPOCH 3

        //all stakers claim
        vm.startPrank(staker1);
        bStakedPDT.claim(staker1);
        vm.stopPrank();

        vm.startPrank(staker2);
        bStakedPDT.claim(staker2);
        vm.stopPrank();

        vm.startPrank(staker3);
        bStakedPDT.claim(staker3);
        vm.stopPrank();

        //showing that all claimed rewards are equal
        console.log("Staker1 PRIME Reward Tokens:", bPRIME.balanceOf(staker1));
        console.log("Staker2 PRIME Reward Tokens:", bPRIME.balanceOf(staker2));
        console.log("Staker3 PRIME Reward Tokens:", bPRIME.balanceOf(staker3));
    }
}
