// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Contract imports
import {StakedPDTTestBase} from "./StakedPDT_base.sol";

contract StakedPDTTest is StakedPDTTestBase {
    /**
     * contructor
     */

    function test_constructor() public {
        assertEq(bStakedPDT.epochLength(), initialEpochLength);

        (uint256 _startTime, uint256 _endTime, ) = bStakedPDT.epoch(0);
        assertEq(_endTime - _startTime, initialFirstEpochStartIn);

        assertEq(bStakedPDT.pdt(), address(bPDTOFT));
    }

    ///////////////////////////////////////////////////////////////////////////////////////////
    /// OWNER FUNCTIONS
    ///////////////////////////////////////////////////////////////////////////////////////////

    /**
     * updateEpochLength
     */

    function test_updateEpochLength_RevertIf_ZeroNewEpochLength() public {
        vm.expectRevert();
        bStakedPDT.updateEpochLength(0);
    }

    function test_updateEpochLength_RevertIf_NonAdminUpdateEpochLength() public {
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

        vm.startPrank(tokenManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                tokenManager,
                EPOCH_MANAGER
            )
        );
        bStakedPDT.updateEpochLength(newEpochLength);
        vm.stopPrank();
    }

    function testFuzz_updateEpochLength_OwnerUpdateEpochLength(uint128 _newEpochLength) public {
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

    function test_updateEpochLength_unstake_RevertIf_EpochHasEnded() public {
        /// EPOCH 0

        uint256 initialBalance = 100;
        bPDTOFT.mint(staker1, initialBalance);

        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, initialBalance);

        // Can't stake if current epoch has ended
        (, uint256 epoch0EndTime, ) = bStakedPDT.epoch(0);
        vm.warp(epoch0EndTime + 1 days);
        vm.expectRevert(OutOfEpoch.selector);
        bStakedPDT.stake(staker1, initialBalance);

        vm.expectRevert(OutOfEpoch.selector);
        bStakedPDT.unstake(staker1, initialBalance);
        vm.stopPrank();

        // Extend current epoch
        vm.startPrank(owner);
        bStakedPDT.updateEpochLength(bStakedPDT.epochLength() + 2 days);
        vm.stopPrank();

        // Should be able to stake
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Stake(staker1, initialBalance, 0);
        bStakedPDT.stake(staker1, initialBalance);
        vm.stopPrank();

        // End epoch 0
        _creditPRIMERewardPool(initialBalance);
        _moveToNextEpoch(0);

        /// EPOCH 1

        // Should be able to unstake half of initial stakes
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Unstake(staker1, initialBalance / 2, 1);
        bStakedPDT.unstake(staker1, initialBalance / 2);
        vm.stopPrank();

        (, uint256 epoch1EndTime, ) = bStakedPDT.epoch(1);
        vm.warp(epoch1EndTime + 1 days);

        assertGt(block.timestamp, epoch1EndTime);

        // Should not be able to unstake since epoch has ended
        vm.startPrank(staker1);
        vm.expectRevert(OutOfEpoch.selector);
        bStakedPDT.unstake(staker1, initialBalance / 2);
        vm.stopPrank();
    }

    /**
     * registerNewRewardToken
     */

    function test_registerNewRewardToken_RevertIf_NonManagerCallFunction() public {
        vm.expectRevert();
        bStakedPDT.registerNewRewardToken(bPROMPTAddress);
    }

    function test_registerNewRewardToken_RevertIf_RegisterExistingToken() public {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(DuplicatedRewardToken.selector, bPRIMEAddress));
        bStakedPDT.registerNewRewardToken(bPRIMEAddress);
        vm.stopPrank();
    }

    function test_registerNewRewardToken_ManagerCanRegister() public {
        vm.startPrank(tokenManager);
        // add PROMPT as a new active reward token
        bStakedPDT.registerNewRewardToken(bPROMPTAddress);

        // check reward token list
        assertEq(bStakedPDT.rewardTokenList(0), bPRIMEAddress);
        assertEq(bStakedPDT.rewardTokenList(1), bPROMPTAddress);

        vm.stopPrank();
    }

    function test_registerNewRewardToken_DefaultAdminCanRegister() public {
        vm.startPrank(owner);
        // add PROMPT as a new active reward token
        bStakedPDT.registerNewRewardToken(bPROMPTAddress);

        // check reward token list
        assertEq(bStakedPDT.rewardTokenList(0), bPRIMEAddress);
        assertEq(bStakedPDT.rewardTokenList(1), bPROMPTAddress);

        vm.stopPrank();
    }

    /**
     * distribute
     */

    function test_distribute_StartFirstEpochAfterEpoch0Ended() public {
        assertEq(bStakedPDT.currentEpochId(), 0);

        _creditPRIMERewardPool(1);
        _moveToNextEpoch(0);

        assertEq(bStakedPDT.currentEpochId(), 1);
    }

    function testFail_distribute_EmptyRewardPool() public {
        /// EPOCH 0

        uint256 defaultPoolSize = 100;
        _creditPRIMERewardPool(defaultPoolSize);
        _moveToNextEpoch(0);

        /// EPOCH 1 - active reward tokens: PRIME

        _creditPRIMERewardPool(defaultPoolSize);
        _creditPROMPTRewardPool(defaultPoolSize);
        _moveToNextEpoch(1);

        /// EPOCH 2 - active reward tokens: PRIME, PROMPT

        _moveToNextEpoch(2);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////
    /// EXTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////////////////////////////////////////

    /**
     * stake
     */

    function testFuzz_stake_RevertIf_StakeMoreThanBalance(uint128 _amount) public {
        uint256 initialBalance = uint256(_amount) + 1;
        bPDTOFT.mint(staker1, initialBalance);
        assertEq(bPDTOFT.balanceOf(staker1), initialBalance);

        vm.startPrank(staker1);
        vm.expectRevert();
        bStakedPDT.stake(staker1, initialBalance + 1);
        vm.stopPrank();
    }

    function testFuzz_stake_SetDetailsAfterStake(uint64 _stakeAmount) public {
        uint256 stakeAmount = uint256(_stakeAmount) + 1; // prevent zero stake by adding 1

        assertEq(bPDTOFT.balanceOf(staker1), 0);
        assertEq(bStakedPDT.totalSupply(), 0);
        assertEq(bStakedPDT.balanceOf(staker1), 0);
        assertEq(bPDTOFT.balanceOf(bStakedPDTAddress), 0);

        bPDTOFT.mint(staker1, stakeAmount * 3);

        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, stakeAmount);
        vm.expectEmit();
        emit Stake(staker1, stakeAmount, 0);
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
        uint256 stakeAmount = uint256(_stakeAmount) + 1;
        bPDTOFT.mint(staker1, stakeAmount * 3);

        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, stakeAmount);
        bStakedPDT.stake(staker1, stakeAmount);
        vm.stopPrank();

        _creditPRIMERewardPool(1);
        _moveToNextEpoch(0);

        assertEq(bStakedPDT.contractWeightAtEpoch(0), bStakedPDT.userWeightAtEpoch(staker1, 0));
    }

    function testFuzz_stake_SumOfStakerWeightEqualsToContractWeight(
        uint64 _stakeAmount1,
        uint64 _stakeAmount2
    ) public {
        /// EPOCH 0
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

        _creditPRIMERewardPool(1);
        _moveToNextEpoch(0);

        /// EPOCH 1

        assertEq(
            bStakedPDT.contractWeightAtEpoch(0),
            bStakedPDT.userWeightAtEpoch(staker1, 0) + bStakedPDT.userWeightAtEpoch(staker2, 0)
        );
    }

    /**
     * unstake
     */

    function testFuzz_unstake(uint8 _stakeAmount1, uint8 _stakeAmount2) public {
        /// EPOCH 0

        _creditPRIMERewardPool(1);
        _moveToNextEpoch(0);

        /// EPOCH 1

        // staker1 stakes in epoch 1
        // staker2 stakes in epoch 1
        uint256 stakeAmount1 = uint256(_stakeAmount1) + 2;
        uint256 stakeAmount2 = uint256(_stakeAmount2) + 2;
        bPDTOFT.mint(staker1, stakeAmount1);
        bPDTOFT.mint(staker2, stakeAmount2);

        // staker1 stakes stakeAmount1
        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, stakeAmount1);
        bStakedPDT.stake(staker1, stakeAmount1);
        vm.stopPrank();

        // staker2 stakes stakeAmount2
        vm.startPrank(staker2);
        bPDTOFT.approve(bStakedPDTAddress, stakeAmount2);
        bStakedPDT.stake(staker2, stakeAmount2);
        vm.stopPrank();

        // staker1 unstakes half in epoch 1
        vm.startPrank(staker1);

        vm.expectRevert(UnstakeLocked.selector);
        bStakedPDT.unstake(staker1, stakeAmount1 / 2);

        skip(2 days);

        vm.expectEmit();
        emit Unstake(staker1, stakeAmount1 / 2, 1);
        bStakedPDT.unstake(staker1, stakeAmount1 / 2);

        vm.stopPrank();

        // staker1 should receive half of staked PDT balance
        assertEq(bPDTOFT.balanceOf(staker1), stakeAmount1 / 2);
        // totalStaked should be equal to stakesByUser[staker1] + stakesByUser[staker2]
        assertEq(
            bStakedPDT.totalSupply(),
            bStakedPDT.balanceOf(staker1) + bStakedPDT.balanceOf(staker2)
        );

        // staker1 is able to unstake again
        vm.startPrank(staker1);
        bStakedPDT.unstake(staker1, stakeAmount1 - stakeAmount1 / 2);
        vm.stopPrank();

        // start epoch 2
        _creditPRIMERewardPool(1);
        _moveToNextEpoch(1);

        /// EPOCH 2

        // staker2 unstakes in epoch 2
        vm.startPrank(staker2);
        bStakedPDT.unstake(staker2, stakeAmount2);
        vm.stopPrank();

        // totalStaked should be zero
        assertEq(bStakedPDT.totalSupply(), 0);

        // start epoch 2
        _creditPRIMERewardPool(1);
        _moveToNextEpoch(1);

        /// EPOCH 2

        // contract weight at epoch 2 should be zero
        assertEq(bStakedPDT.contractWeightAtEpoch(2), 0);

        // both stakers can claim rewards
        vm.startPrank(staker1);
        bStakedPDT.claim(staker1);
        vm.stopPrank();

        vm.startPrank(staker2);
        bStakedPDT.claim(staker2);
        vm.stopPrank();
    }

    /**
     * claim & withdrawRewardTokens
     */

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
        vm.expectRevert();
        bStakedPDT.claim(staker1);
        vm.stopPrank();
    }

    function testFuzz_claim_OnlyOneStakerWithMultipleRewardTokens(
        uint8 _stakeAmount,
        uint8 _rewardAmount1,
        uint8 _rewardAmount2
    ) public {
        uint256 stakeAmount = uint256(_stakeAmount) + 1;
        uint256 rewardAmount1 = uint256(_rewardAmount1) + 1;
        uint256 rewardAmount2 = uint256(_rewardAmount2) + 1;

        /// EPOCH 0

        // stake
        bPDTOFT.mint(staker1, stakeAmount * 3);

        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, stakeAmount);
        bStakedPDT.stake(staker1, stakeAmount);
        vm.stopPrank();

        // add reward tokens to the staking contract
        vm.startPrank(owner);
        bStakedPDT.registerNewRewardToken(bPROMPTAddress);
        _creditPRIMERewardPool(rewardAmount1);
        bPROMPT.mint(bStakedPDTAddress, rewardAmount2);
        vm.stopPrank();
        _moveToNextEpoch(0);

        /// EPOCH 1

        // there is no reward for epoch 0
        assertEq(bStakedPDT.totalRewardsToDistribute(bPRIMEAddress, 0), 0);
        assertEq(bStakedPDT.totalRewardsToDistribute(bPRIMEAddress, 1), rewardAmount1);

        // always add reward tokens to the staking contract before new epoch starts
        _creditPRIMERewardPool(rewardAmount1);
        bPROMPT.mint(bStakedPDTAddress, rewardAmount2);
        _moveToNextEpoch(1);

        /// EPOCH 2

        assertEq(bStakedPDT.totalRewardsToDistribute(bPRIMEAddress, 2), rewardAmount1);

        // claim epoch 1's rewards
        vm.startPrank(staker1);
        bStakedPDT.claim(staker1);
        vm.stopPrank();

        assertEq(bPRIME.balanceOf(staker1), rewardAmount1);
        assertEq(bPROMPT.balanceOf(staker1), rewardAmount2);
        assertEq(bStakedPDT.totalRewardsClaimed(bPRIMEAddress, 1), rewardAmount1);

        // stake more
        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, stakeAmount);
        bStakedPDT.stake(staker1, stakeAmount);
        vm.stopPrank();

        // add more reward tokens to the staking contract
        bPRIME.mint(bStakedPDTAddress, bStakedPDT.totalRewardsToDistribute(bPRIMEAddress, 2));
        bPROMPT.mint(bStakedPDTAddress, bStakedPDT.totalRewardsToDistribute(bPROMPTAddress, 2));
        _moveToNextEpoch(2);
        assertEq(bStakedPDT.totalRewardsToDistribute(bPRIMEAddress, 2), rewardAmount1);
        assertEq(bStakedPDT.totalRewardsToDistribute(bPROMPTAddress, 2), rewardAmount2);

        // EPOCH 3

        // claim epoch 2's rewards
        vm.startPrank(staker1);
        bStakedPDT.claim(staker1);
        vm.stopPrank();

        assertEq(bPRIME.balanceOf(staker1), rewardAmount1 * 2);
        assertEq(bPROMPT.balanceOf(staker1), rewardAmount2 * 2);
        assertEq(bStakedPDT.totalRewardsClaimed(bPRIMEAddress, 2), rewardAmount1);
    }

    function test_claim_MultipleClaimersWithNoUnstaking() public {
        /// EPOCH 0

        uint256 epoch1_PRIME_pool_size = 100;

        // prepare reward pool for epoch 1 & start
        _creditPRIMERewardPool(epoch1_PRIME_pool_size);
        _moveToNextEpoch(0);

        /// EPOCH 1

        uint256 epoch1_staker1_stakedAmount = 10;
        uint256 epoch1_staker2_stakedAmount = 40;
        uint256 epoch2_PRIME_pool_size = 300;

        // staker1 stakes
        vm.startPrank(staker1);
        bPDTOFT.mint(staker1, 99999999999);
        bPDTOFT.approve(bStakedPDTAddress, 99999999999);
        bStakedPDT.stake(staker1, epoch1_staker1_stakedAmount);
        vm.stopPrank();

        // staker2 stakes
        vm.startPrank(staker2);
        bPDTOFT.mint(staker2, 99999999999);
        bPDTOFT.approve(bStakedPDTAddress, 99999999999);
        bStakedPDT.stake(staker2, epoch1_staker2_stakedAmount); // totalStaked: 50
        vm.stopPrank();

        // prepare reward pool for epoch 2 & start
        _creditPRIMERewardPool(epoch2_PRIME_pool_size);
        _moveToNextEpoch(1);

        /// EPOCH 2

        // staker1 claims rewards for epoch 1
        vm.startPrank(staker1);
        // vm.expectEmit();
        // emit Claim(
        //     staker1,
        //     2,
        //     address(prime),
        //     (epoch1_PRIME_pool_size * epoch1_staker1_stakedAmount) /
        //         (epoch1_staker1_stakedAmount + epoch1_staker2_stakedAmount)
        // );
        bStakedPDT.claim(staker1);
        bPRIME.balanceOf(staker1);
        vm.stopPrank();

        // staker1 stakes
        vm.startPrank(staker1);
        bStakedPDT.stake(staker1, 50); // totalStaked: 100
        vm.stopPrank();

        // prepare funds for epoch 3 & start
        _creditPRIMERewardPool(500);
        _moveToNextEpoch(2);

        /// EPOCH 3

        // staker1 claims rewards for epoch 2
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Claim(staker1, 3, bPRIMEAddress, (300 * (10 + 50)) / (10 + 40 + 50));
        bStakedPDT.claim(staker1);
        vm.stopPrank();

        // staker2 claims rewards for epoch 1 and 2
        vm.startPrank(staker2);
        vm.expectEmit();
        emit Claim(staker2, 3, bPRIMEAddress, (100 * 40) / (10 + 40) + (300 * 40) / (10 + 40 + 50));
        bStakedPDT.claim(staker2);
        vm.stopPrank();
    }

    function test_claim_MultipleClaimersWithUnstaking() public {
        /// EPOCH 0

        // prepare reward pool for epoch 1 & start
        _creditPRIMERewardPool(100);
        _moveToNextEpoch(0);

        /// EPOCH 1

        // staker1 stakes
        vm.startPrank(staker1);
        bPDTOFT.mint(staker1, 99999999999);
        bPDTOFT.approve(bStakedPDTAddress, 99999999999);
        bStakedPDT.stake(staker1, 10);
        vm.stopPrank();

        // staker2 stakes
        vm.startPrank(staker2);
        bPDTOFT.mint(staker2, 99999999999);
        bPDTOFT.approve(bStakedPDTAddress, 99999999999);
        bStakedPDT.stake(staker2, 40); // totalStaked: 50
        vm.stopPrank();

        // prepare reward pool for epoch 2 & start
        _creditPRIMERewardPool(300);
        _moveToNextEpoch(1);

        /// EPOCH 2

        // staker1 claims rewards for epoch 1
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Claim(staker1, 2, bPRIMEAddress, (100 * 10) / (10 + 40));
        bStakedPDT.claim(staker1);
        vm.stopPrank();

        // staker1 unstakes
        vm.startPrank(staker1);
        bStakedPDT.unstake(staker1, 10); // totalStaked: 40 = 50 - 10
        vm.stopPrank();

        // prepare funds for epoch 3 & start
        _creditPRIMERewardPool(500);
        _moveToNextEpoch(2);

        /// EPOCH 3

        // staker1 doesn't have rewards for epoch 2
        vm.startPrank(staker1);
        bStakedPDT.claim(staker1);
        vm.stopPrank();

        // staker2 claims rewards for epoch 1 and 2
        vm.startPrank(staker2);
        vm.expectEmit();
        emit Claim(staker2, 3, bPRIMEAddress, (100 * 40) / (10 + 40) + (300 * 40) / 40);
        bStakedPDT.claim(staker2);
        vm.stopPrank();
    }

    function test_claim_ClaimRewardsTwoYearsLater() public {
        /// EPOCH 0

        uint256 initialBalance = 100;
        bPDTOFT.mint(staker1, initialBalance);

        // stake in epoch 0
        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, initialBalance);
        bStakedPDT.stake(staker1, initialBalance);
        vm.stopPrank();

        uint256 POOL_SIZE = 100;
        uint256 nExpiredEpochs = 5;
        uint256 rewardsExpiryThreshold = bStakedPDT.rewardsExpiryThreshold();
        uint256 nEpochs = rewardsExpiryThreshold + nExpiredEpochs + 1;

        for (uint256 epochId = 0; epochId < nEpochs; ) {
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

    ///////////////////////////////////////////////////////////////////////////////////////////
    /// VIEW FUNCTIONS
    ///////////////////////////////////////////////////////////////////////////////////////////

    /**
     * Pending Rewards
     */

    function test_pendingRewards() public {
        /// EPOCH 0

        // move to epoch 1
        _creditPRIMERewardPool(100);
        _moveToNextEpoch(0);

        /// EPOCH 1

        // staker1 stakes 10
        bPDTOFT.mint(staker1, 10);
        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, 10);
        bStakedPDT.stake(staker1, 10);
        vm.stopPrank();

        // staker2 stakes 40
        bPDTOFT.mint(staker2, 40);
        vm.startPrank(staker2);
        bPDTOFT.approve(bStakedPDTAddress, 40);
        bStakedPDT.stake(staker2, 40);
        vm.stopPrank();

        // move to epoch 2
        _creditPRIMERewardPool(200);
        _moveToNextEpoch(1);

        /// EPOCH 2

        // staker1 claims rewards for epoch 1
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Claim(staker1, 2, bPRIMEAddress, 20);
        bStakedPDT.claim(staker1);
        vm.stopPrank();

        assertEq(bStakedPDT.claimAmountForEpoch(staker2, 1, bPRIMEAddress), 80);

        assertEq(bStakedPDT.pendingRewards(bPRIMEAddress), 0);

        // staker2 unstakes
        vm.startPrank(staker2);
        vm.expectEmit();
        emit Unstake(staker2, 40, 2);
        bStakedPDT.unstake(staker2, 40);
        vm.stopPrank();

        assertEq(bStakedPDT.claimAmountForEpoch(staker2, 1, bPRIMEAddress), 80);

        assertEq(bStakedPDT.pendingRewards(bPRIMEAddress), 0);

        _creditPRIMERewardPool(300);

        assertEq(bStakedPDT.pendingRewards(bPRIMEAddress), 300);
    }

    /**
     * claimAmountForEpoch
     */

    function test_claimAmountForEpoch() public {
        /// EPOCH 0

        // register aero as a reward token
        vm.startPrank(owner);
        bStakedPDT.registerNewRewardToken(bPROMPTAddress);
        vm.stopPrank();

        // move to epoch 1
        _creditPRIMERewardPool(100);
        _creditPROMPTRewardPool(200);
        _moveToNextEpoch(0);

        /// EPOCH 1

        // staker1 stakes 10
        bPDTOFT.mint(staker1, 10);
        vm.startPrank(staker1);
        bPDTOFT.approve(bStakedPDTAddress, 10);
        bStakedPDT.stake(staker1, 10);
        vm.stopPrank();

        // staker2 stakes 40
        bPDTOFT.mint(staker2, 40);
        vm.startPrank(staker2);
        bPDTOFT.approve(bStakedPDTAddress, 40);
        bStakedPDT.stake(staker2, 40);
        vm.stopPrank();

        // move to epoch 2
        _creditPRIMERewardPool(10);
        _creditPROMPTRewardPool(20);
        _moveToNextEpoch(1);

        /// EPOCH 2

        assertEq(bStakedPDT.claimAmountForEpoch(staker1, 1, bPRIMEAddress), (100 * 10) / (10 + 40));
        assertEq(
            bStakedPDT.claimAmountForEpoch(staker1, 1, bPROMPTAddress),
            (200 * 10) / (10 + 40)
        );

        assertEq(bStakedPDT.claimAmountForEpoch(staker2, 1, bPRIMEAddress), (100 * 40) / (10 + 40));
        assertEq(
            bStakedPDT.claimAmountForEpoch(staker2, 1, bPROMPTAddress),
            (200 * 40) / (10 + 40)
        );
    }
}
