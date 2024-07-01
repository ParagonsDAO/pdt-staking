// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Contract imports
import {StakedPDTTestBase} from "./StakedPDT_base.sol";

contract StakedPDTTest is StakedPDTTestBase {
    function testFuzz_michael() public {
        uint256 primesForEpoch = 1000 ether;
        uint256 promptsForEpoch = 2000 ether;
        uint256 pdtInitialBalance = 1000 ether;

        bPDTOFT.mint(staker1, pdtInitialBalance);
        bPDTOFT.mint(staker2, pdtInitialBalance);
        bPDTOFT.mint(staker3, pdtInitialBalance);

        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, 2 ** 255);
        vm.stopPrank();

        vm.startPrank(staker2);
        bPDTOFT.approve(bStakedPDTAddress, 2 ** 255);
        vm.stopPrank();

        vm.startPrank(staker3);
        bPDTOFT.approve(bStakedPDTAddress, 2 ** 255);
        vm.stopPrank();

        /// EPOCH 0

        _creditPRIMERewardPool(primesForEpoch);
        _moveToNextEpoch(0);

        /// EPOCH 1

        assertEq(bStakedPDT.balanceOf(staker1), 0);

        uint256 epoch1StakingAmount = pdtInitialBalance / 9;
        vm.startPrank(staker1);
        bStakedPDT.stake(staker1, epoch1StakingAmount);

        // can't transfer stPDT to non-whitelisted addresses
        vm.expectRevert(InvalidStakesTransfer.selector);
        bStakedPDT.transfer(staker2, epoch1StakingAmount);
        vm.stopPrank();

        vm.startPrank(staker2);
        bStakedPDT.stake(staker2, epoch1StakingAmount);
        vm.stopPrank();

        assertEq(bStakedPDT.balanceOf(staker1), epoch1StakingAmount);
        assertEq(bStakedPDT.balanceOf(staker2), epoch1StakingAmount);
        assertEq(bStakedPDT.totalSupply(), bPDTOFT.balanceOf(bStakedPDTAddress));
    }
}
