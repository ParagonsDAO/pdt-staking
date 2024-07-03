// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Contract imports
import {StakedPDTTestBase} from "./StakedPDT_base.sol";

contract StakedPDTStakeTest is StakedPDTTestBase {
    function testFuzz_stake_RevertIf_StakeMoreThanBalance(uint128 _amount) public {
        /// EPOCH 0

        _creditPRIMERewardPool(1 ether);
        _moveToNextEpoch(0);

        /// EPOCH 1

        uint256 initialBalance = uint256(_amount) + 1;
        bPDTOFT.mint(staker1, initialBalance);
        assertEq(bPDTOFT.balanceOf(staker1), initialBalance);

        vm.startPrank(staker1);
        vm.expectRevert();
        bStakedPDT.stake(staker1, initialBalance + 1);
        vm.stopPrank();
    }

    function testFuzz_stake_SetDetailsAfterStake(uint64 _stakeAmount) public {
        /// EPOCH 0

        _creditPRIMERewardPool(1 ether);
        _moveToNextEpoch(0);

        /// EPOCH 1

        uint256 stakeAmount = uint256(_stakeAmount) + 1; // prevent zero stake by adding 1

        assertEq(bPDTOFT.balanceOf(staker1), 0);
        assertEq(bStakedPDT.totalSupply(), 0);
        assertEq(bStakedPDT.balanceOf(staker1), 0);
        assertEq(bPDTOFT.balanceOf(bStakedPDTAddress), 0);

        bPDTOFT.mint(staker1, stakeAmount * 3);

        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, stakeAmount);
        vm.expectEmit();
        emit Stake(staker1, stakeAmount, 1);
        bStakedPDT.stake(staker1, stakeAmount);
        vm.stopPrank();

        assertEq(bPDTOFT.balanceOf(staker1), stakeAmount * 2);
        assertEq(bStakedPDT.totalSupply(), stakeAmount);
        assertEq(bStakedPDT.balanceOf(staker1), stakeAmount);
        assertEq(bPDTOFT.balanceOf(bStakedPDTAddress), stakeAmount);
    }

    function testFuzz_stake_StakerWeightEqualsToContractWeightWhenOnlyStaker(
        uint64 _stakeAmount
    ) public {
        /// EPOCH 0

        _creditPRIMERewardPool(1 ether);
        _moveToNextEpoch(0);

        /// EPOCH 1

        uint256 stakeAmount = uint256(_stakeAmount) + 1;
        bPDTOFT.mint(staker1, stakeAmount * 3);

        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, stakeAmount);
        bStakedPDT.stake(staker1, stakeAmount);
        vm.stopPrank();

        _creditPRIMERewardPool(1 ether);
        _moveToNextEpoch(1);

        assertEq(bStakedPDT.contractWeightAtEpoch(0), bStakedPDT.userWeightAtEpoch(staker1, 0));
    }

    function testFuzz_stake_SumOfStakerWeightEqualsToContractWeight(
        uint64 _stakeAmount1,
        uint64 _stakeAmount2
    ) public {
        /// EPOCH 0

        _creditPRIMERewardPool(1 ether);
        _moveToNextEpoch(0);

        /// EPOCH 1

        uint256 stakeAmount1 = uint256(_stakeAmount1) + 1;
        uint256 stakeAmount2 = uint256(_stakeAmount2) + 1;
        bPDTOFT.mint(staker1, stakeAmount1);
        bPDTOFT.mint(staker2, stakeAmount2);

        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, stakeAmount1);
        bStakedPDT.stake(staker1, stakeAmount1);
        vm.stopPrank();

        vm.startPrank(staker2);
        bPDTOFT.approve(bStakedPDTAddress, stakeAmount2);
        bStakedPDT.stake(staker2, stakeAmount2);
        vm.stopPrank();

        assertEq(
            bStakedPDT.totalSupply(),
            bStakedPDT.balanceOf(staker1) + bStakedPDT.balanceOf(staker2)
        );

        _creditPRIMERewardPool(1 ether);
        _moveToNextEpoch(1);

        /// EPOCH 2

        assertEq(
            bStakedPDT.contractWeightAtEpoch(1),
            bStakedPDT.userWeightAtEpoch(staker1, 1) + bStakedPDT.userWeightAtEpoch(staker2, 1)
        );
    }
}
