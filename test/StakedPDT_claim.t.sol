// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Forge imports
import {console} from "forge-std/Test.sol";

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
                DEFAULT_ADMIN_ROLE
            )
        );
        bStakedPDT.withdrawRewardTokens(bPRIMEAddress, _expiredRewardsAmount);
        vm.stopPrank();

        vm.startPrank(epochManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                epochManager,
                DEFAULT_ADMIN_ROLE
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

    function test_transferTokenAndClaim() public {
        uint256 POOL_SIZE = 1e18;
        uint256 initialBalance = 1e18;
        bPDTOFT.mint(staker1, initialBalance * 2);
        bPDTOFT.mint(staker2, initialBalance * 2);
        bPDTOFT.mint(staker3, initialBalance * 2);
        bPDTOFT.mint(staker4, initialBalance * 2);

        //update staker2 as whitelisted
        vm.startPrank(owner);
        bStakedPDT.updateWhitelistedContract(staker2, true);
        vm.stopPrank();

        //advance to epoch1
        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(0);

        //advance to epoch2
        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(1);

        console.log("Epoch 2");

        //staker1, staker3 and staker4 stake at epoch2 start
        (uint256 epochStartTime, uint256 epochEndTime, ) = bStakedPDT.epoch(2);
        vm.warp(epochStartTime);

        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, initialBalance * 2);
        bStakedPDT.stake(staker1, initialBalance);
        vm.stopPrank();

        vm.startPrank(staker3);
        bPDTOFT.approve(bStakedPDTAddress, initialBalance * 2);
        bStakedPDT.stake(staker3, initialBalance);
        vm.stopPrank();

        vm.startPrank(staker4);
        bPDTOFT.approve(bStakedPDTAddress, initialBalance * 2);
        bStakedPDT.stake(staker4, initialBalance);
        vm.stopPrank();

        //staker1 transfers StakedPDT to staker2 at the end of epoch 2
        //only whitelisted contract can call `transfer`
        vm.warp(epochEndTime - 1 days);

        vm.startPrank(staker1);
        vm.expectRevert(InvalidStakesTransfer.selector);
        bStakedPDT.transfer(staker2, initialBalance);
        bStakedPDT.approve(bWstPDTAddress, initialBalance);
        bWstPDT.wrap(initialBalance);
        bWstPDT.transfer(staker2, initialBalance);
        vm.stopPrank();

        vm.startPrank(staker2);
        bWstPDT.unwrap(initialBalance);
        vm.stopPrank();

        console.log("Contract weight:", bStakedPDT.contractWeight());
        console.log("Staker1 weight:", bStakedPDT.userTotalWeight(staker1));
        console.log("Staker2 weight:", bStakedPDT.userTotalWeight(staker2));
        console.log("Staker3 weight:", bStakedPDT.userTotalWeight(staker3));
        console.log("Staker4 weight:", bStakedPDT.userTotalWeight(staker4));

        //advance to epoch3
        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(2);

        console.log("Epoch 3");

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

        vm.startPrank(staker4);
        bStakedPDT.claim(staker4);
        vm.stopPrank();

        //logs
        console.log("Staker1 PRIME Reward Tokens:", bPRIME.balanceOf(staker1));
        console.log("Staker2 PRIME Reward Tokens:", bPRIME.balanceOf(staker2));
        console.log("Staker3 PRIME Reward Tokens:", bPRIME.balanceOf(staker3));
        console.log("Staker4 PRIME Reward Tokens:", bPRIME.balanceOf(staker4));
    }

    function test_wrapUnwrapAndClaim() public {
        /**
         * EPOCH 1
         * staker1 stakes 100 PDT
         * staker2 stakes 100 PDT
         *
         * EPOCH 4
         * staker1 wraps 50 stPDT into 50 wstPDT at the end of epoch
         * staker1 transfers 50 wstPDT to staker2
         * staker2 unwraps 50 wstPDT into 50 stPDT
         *
         * EPOCH 6
         * staker1, staker2 both claims their rewards
         */

        uint256 POOL_SIZE = 100 ether;

        /// EPOCH 0

        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(0);

        /// EPOCH 1

        uint256 initialBalance1 = 100 ether;
        uint256 initialBalance2 = 100 ether;
        bPDTOFT.mint(staker1, initialBalance1);
        bPDTOFT.mint(staker2, initialBalance2);

        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, initialBalance1);
        bStakedPDT.stake(staker1, initialBalance1);
        vm.stopPrank();

        vm.startPrank(staker2);
        bPDTOFT.approve(bStakedPDTAddress, initialBalance2);
        bStakedPDT.stake(staker2, initialBalance2);
        vm.stopPrank();

        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(1);

        /// EPOCH 2

        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(2);

        /// EPOCH 3

        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(3);

        /// EPOCH 4

        uint256 wrapAmount = 50 ether;
        (, uint256 epoch4EndTime, ) = bStakedPDT.epoch(4);
        vm.warp(epoch4EndTime - 1 days);

        console.log("\nEpoch 4");
        console.log("Before wrapping");
        console.log("Contract weight: ", bStakedPDT.contractWeight());
        console.log("Staker1 weight: ", bStakedPDT.userTotalWeight(staker1));
        console.log("Staker2 weight: ", bStakedPDT.userTotalWeight(staker2));

        vm.startPrank(staker1);
        bStakedPDT.approve(bWstPDTAddress, wrapAmount);
        bWstPDT.wrap(wrapAmount);
        bWstPDT.transfer(staker2, wrapAmount);
        vm.stopPrank();

        console.log("After wrapping");
        console.log("Contract weight: ", bStakedPDT.contractWeight());
        console.log("Staker1 weight: ", bStakedPDT.userTotalWeight(staker1));
        console.log("Staker2 weight: ", bStakedPDT.userTotalWeight(staker2));

        vm.startPrank(staker2);
        bWstPDT.unwrap(wrapAmount);
        vm.stopPrank();

        console.log("After unwrapping");
        console.log("Contract weight: ", bStakedPDT.contractWeight());
        console.log("Staker1 weight: ", bStakedPDT.userTotalWeight(staker1));
        console.log("Staker2 weight: ", bStakedPDT.userTotalWeight(staker2));

        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(4);

        /// EPOCH 5

        _creditPRIMERewardPool(POOL_SIZE);
        _moveToNextEpoch(5);

        /// EPOCH 6

        (, uint256 epoch6EndTime, ) = bStakedPDT.epoch(6);
        vm.warp(epoch6EndTime - 1 days);

        console.log("\nEpoch 6");
        console.log("Before claiming");

        uint256 e6_s1_claimableAmount = 0;
        uint256 e6_s2_claimableAmount = 0;
        for (uint256 i = 1; i <= 5; ++i) {
            uint256 rewards1 = bStakedPDT.claimAmountForEpoch(staker1, i, bPRIMEAddress);
            uint256 rewards2 = bStakedPDT.claimAmountForEpoch(staker2, i, bPRIMEAddress);
            console.log("Staker1 claimable rewards of Epoch ", i, ": ", rewards1);
            console.log("Staker2 claimable rewards of Epoch ", i, ": ", rewards2);
            e6_s1_claimableAmount += rewards1;
            e6_s2_claimableAmount += rewards2;
        }

        vm.startPrank(staker1);
        bStakedPDT.claim(staker1);
        vm.stopPrank();

        vm.startPrank(staker2);
        bStakedPDT.claim(staker2);
        vm.stopPrank();

        console.log("After claiming");
        console.log("Staker1 PRIME balance: ", bPRIME.balanceOf(staker1));
        console.log("Staker2 PRIME balance: ", bPRIME.balanceOf(staker2));

        assertEq(e6_s1_claimableAmount, bPRIME.balanceOf(staker1));
        assertEq(e6_s2_claimableAmount, bPRIME.balanceOf(staker2));
    }
}
