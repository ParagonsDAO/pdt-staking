// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Contract imports
import {StakedPDTTestBase} from "./StakedPDT_base.sol";

contract StakedPDTClaimTest is StakedPDTTestBase {
    function test_claim_RevertIf_ClaimDuringEpoch0() public {
        vm.startPrank(staker1);
        vm.expectRevert();
        bStakedPDT.claim(staker1);
        vm.stopPrank();
    }

    function testFuzz_claim_RevertIf_ClaimAfterAlreadyClaimedForEpoch(uint64 _stakeAmount) public {
        uint256 stakeAmount = uint256(_stakeAmount) + 1;
        bPDTOFT.mint(staker1, stakeAmount * 3);

        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, stakeAmount);
        bStakedPDT.stake(staker1, stakeAmount);
        vm.stopPrank();

        _creditPRIMERewardPool(100);
        _moveToNextEpoch(0);

        /// EPOCH 1

        _creditPRIMERewardPool(100);
        _moveToNextEpoch(1);

        /// Epoch 2

        vm.startPrank(staker1);
        bStakedPDT.claim(staker1);
        vm.expectRevert(ClaimedUpToEpoch.selector);
        bStakedPDT.claim(staker1);
        vm.stopPrank();
    }

    function test_claim_ClaimRewardsTwoYearsLater() public {
        uint256 POOL_SIZE = 100;

        /// EPOCH 0

        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(0);

        /// EPOCH 1

        uint256 initialBalance = 100;
        bPDTOFT.mint(staker1, initialBalance);

        // stake in epoch 1
        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, initialBalance);
        bStakedPDT.stake(staker1, initialBalance);
        vm.stopPrank();

        uint256 nExpiredEpochs = 5;
        uint256 rewardsExpiryThreshold = bStakedPDT.rewardsExpiryThreshold();
        uint256 nEpochs = rewardsExpiryThreshold + nExpiredEpochs + 1;

        for (uint256 epochId = 1; epochId < nEpochs; ) {
            _creditPRIMERewardPool(POOL_SIZE);
            _moveToNextEpoch(epochId);

            unchecked {
                ++epochId;
            }
        }

        /// EPOCH nEpochs

        assertEq(bStakedPDT.currentEpochId(), nEpochs);

        vm.startPrank(staker1);
        vm.expectEmit();
        emit RewardsExpired(staker1, nEpochs, bPRIMEAddress, POOL_SIZE * nExpiredEpochs);
        bStakedPDT.claim(staker1);
        vm.stopPrank();

        // Should exclude current epoch's rewards
        uint256 _expiredRewardsAmount = bPRIME.balanceOf(bStakedPDTAddress) - POOL_SIZE;
        assertEq(_expiredRewardsAmount, POOL_SIZE * nExpiredEpochs);

        // Non-owners shouldn't be able to withdraw expired rewards
        vm.startPrank(staker1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                staker1,
                TOKEN_MANAGER
            )
        );
        bStakedPDT.withdrawRewardTokens(bPRIMEAddress, _expiredRewardsAmount);
        vm.stopPrank();

        vm.startPrank(epochManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                epochManager,
                TOKEN_MANAGER
            )
        );
        bStakedPDT.withdrawRewardTokens(bPRIMEAddress, _expiredRewardsAmount);
        vm.stopPrank();

        // Owner should be able to withdraw expired rewards
        vm.startPrank(owner);
        bStakedPDT.withdrawRewardTokens(bPRIMEAddress, _expiredRewardsAmount);
        vm.stopPrank();

        assertEq(bPRIME.balanceOf(bStakedPDTAddress), POOL_SIZE);
        assertEq(bStakedPDT.pendingRewards(bPRIMEAddress), 0);
    }
}
