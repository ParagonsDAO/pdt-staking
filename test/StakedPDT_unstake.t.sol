// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Forge imports
import {console} from "forge-std/Test.sol";

// Contract imports
import {StakedPDTTestBase} from "./StakedPDT_base.sol";

contract StakedPDTUnstakeTest is StakedPDTTestBase {
    function test_unstakeAtEpochEnd() public {
        /// EPOCH 0

        uint256 POOL_SIZE = 1e18;
        uint256 initialBalance = 1e18;
        bPDTOFT.mint(staker1, initialBalance);
        bPDTOFT.mint(staker2, initialBalance);

        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(0);

        /// EPOCH 1

        // users stake
        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, initialBalance);
        bStakedPDT.stake(staker1, initialBalance);
        vm.stopPrank();

        vm.startPrank(staker2);
        bPDTOFT.approve(bStakedPDTAddress, initialBalance);
        bStakedPDT.stake(staker2, initialBalance);
        vm.stopPrank();

        // advance time to the end of epoch 1
        (, uint256 epochEndTime, ) = bStakedPDT.epoch(1);
        vm.warp(epochEndTime);

        //staker1 unstakes at epoch end
        vm.startPrank(staker1);
        bStakedPDT.unstake(staker1, initialBalance);
        vm.stopPrank();

        // move to epoch 2
        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(1);

        /// EPOCH 2

        // stakers claim rewards
        vm.startPrank(staker1);
        bStakedPDT.claim(staker1);
        vm.stopPrank();

        vm.startPrank(staker2);
        bStakedPDT.claim(staker2);
        vm.stopPrank();

        // logs
        console.log("Staker1 Reward Tokens:", bPRIME.balanceOf(staker1));
        console.log("Staker2 Reward Tokens:", bPRIME.balanceOf(staker2));
        console.log("Reward tokens in the contract:", bPRIME.balanceOf(bStakedPDTAddress));
    }
}
