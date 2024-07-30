// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Contract imports
import {StakedPDTTestBase} from "./StakedPDT_base.sol";

contract StakedPDTUpdateEpochLengthTest is StakedPDTTestBase {
    function test_RevertIf_ZeroNewEpochLength() public {
        vm.expectRevert();
        bStakedPDT.updateEpochLength(0);
    }

    function test_RevertIf_NonAdminUpdateEpochLength() public {
        uint256 newEpochLength = 1000000;

        vm.startPrank(staker1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                staker1,
                EPOCH_MANAGER
            )
        );
        bStakedPDT.updateEpochLength(newEpochLength);
        vm.stopPrank();
    }

    function testFuzz_OwnerUpdateEpochLength(uint128 _newEpochLength) public {
        uint256 newEpochLength = uint256(_newEpochLength) + 1;

        uint256 _epochId = bStakedPDT.currentEpochId();
        (uint256 _startTime, , ) = bStakedPDT.epoch(_epochId);

        vm.startPrank(owner);
        vm.expectEmit();
        emit UpdateEpochLength(0, initialEpochLength, newEpochLength);
        bStakedPDT.updateEpochLength(newEpochLength);

        assertEq(bStakedPDT.epochLength(), newEpochLength);

        (, uint256 _newEndTime, ) = bStakedPDT.epoch(_epochId);
        assertEq(_startTime + newEpochLength, _newEndTime);
    }

    function test_RevertIf_EpochHasEnded() public {
        uint256 POOL_SIZE = 1e18;

        /// EPOCH 0

        // Advance to epoch 1
        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(0);

        /// EPOCH 1

        uint256 initialBalance = 100;
        bPDTOFT.mint(staker1, initialBalance);

        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, initialBalance);

        // Can't stake if current epoch has ended
        (, uint256 epoch1EndTime, ) = bStakedPDT.epoch(1);
        vm.warp(epoch1EndTime + 1 days);
        vm.expectRevert(OutOfEpoch.selector);
        bStakedPDT.stake(staker1, initialBalance);

        vm.expectRevert(InvalidUnstakeAmount.selector);
        bStakedPDT.unstake(staker1, initialBalance);
        vm.stopPrank();

        // Extend current epoch
        vm.startPrank(owner);
        bStakedPDT.updateEpochLength(bStakedPDT.epochLength() + 2 days);
        vm.stopPrank();

        // Should be able to stake
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Stake(staker1, initialBalance, 1);
        bStakedPDT.stake(staker1, initialBalance);
        vm.stopPrank();

        // Advance to epoch 2
        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(1);

        /// EPOCH 2

        // Should be able to unstake half of initial stakes
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Unstake(staker1, initialBalance / 2, 2);
        bStakedPDT.unstake(staker1, initialBalance / 2);
        vm.stopPrank();

        (, uint256 epoch2EndTime, ) = bStakedPDT.epoch(2);
        vm.warp(epoch2EndTime + 1 days);

        assertGt(block.timestamp, epoch2EndTime);

        // Should not be able to unstake since epoch has ended
        vm.startPrank(staker1);
        vm.expectRevert(OutOfEpoch.selector);
        bStakedPDT.unstake(staker1, initialBalance / 2);
        vm.stopPrank();
    }
}
