// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {PDTStakingV2} from "../src/PDTStakingV2.sol";
import {IPDTStakingV2} from "../src/interfaces/IPDTStakingV2.sol";
import {MockERC20} from "../src/mocks/ERC20.sol";

contract PDTStakingV2Test is Test, IPDTStakingV2 {
    PDTStakingV2 public pdtStakingV2;
    MockERC20 public pdt;
    MockERC20 public prime;
    MockERC20 public aero;
    address owner;
    address staker = address(3);
    address staker1 = address(4);
    address staker2 = address(5);

    function setUp() public {
        pdt = new MockERC20("ParagonsDAO Token", "PDT");
        prime = new MockERC20("PRIME Token", "PRIME");
        aero = new MockERC20("AERO Token", "AERO");

        pdtStakingV2 = new PDTStakingV2(
            4 weeks, // epochLength
            1 days, // firstEpochStartIn
            address(pdt), // PDT address
            msg.sender // initial owner
        );

        owner = pdtStakingV2.owner();

        vm.startPrank(owner);
        pdtStakingV2.upsertRewardToken(address(prime), true);
        vm.stopPrank();
    }

    function test_constructor() public view {
        assertEq(pdtStakingV2.epochLength(), 4 weeks);

        (uint256 _startTime, uint256 _endTime, ) = pdtStakingV2.epoch(0);
        assertEq(_endTime - _startTime, 1 days);

        assertEq(pdtStakingV2.pdt(), address(pdt));
    }

    /**
     * pushBackEpoch0
     */

    function test_pushBackEpoch0_NonOwnerCannotPushBack() public {
        vm.expectRevert();
        pdtStakingV2.pushBackEpoch0(3 days);
    }

    function test_pushBackEpoch0_CannotPushBackAfterEpoch0() public {
        _creditPRIMERewardPool(1);
        _moveToNextEpoch(0);

        assertEq(pdtStakingV2.currentEpochId(), 1);
        vm.startPrank(owner);
        vm.expectRevert();
        pdtStakingV2.pushBackEpoch0(3 days);
        vm.stopPrank();
    }

    function test_pushBackEpoch0_OwnerPushBack() public {
        vm.startPrank(owner);
        pdtStakingV2.pushBackEpoch0(3 days);
        (uint256 _startTime, uint256 _endTime, ) = pdtStakingV2.epoch(0);
        assertEq(_endTime - _startTime, 4 days);
        vm.stopPrank();
    }

    /**
     * updateEpochLength
     */

    function testFuzz_updateEpochLength_NonOwnerCannotUpdate(uint256 _newEpochLength) public {
        vm.expectRevert();
        pdtStakingV2.updateEpochLength(_newEpochLength);
    }

    function testFuzz_updateEpochLength_OwnerUpdateEpochLength(uint256 _newEpochLength) public {
        vm.startPrank(owner);
        pdtStakingV2.updateEpochLength(_newEpochLength);
        assertEq(pdtStakingV2.epochLength(), _newEpochLength);
    }

    /**
     * upsertRewardToken & getActiveRewardTokenList
     */

    function test_upsertRewardToken() public {
        vm.startPrank(owner);
        // add AERO as a new active reward token
        pdtStakingV2.upsertRewardToken(address(aero), true);

        // check active reward token list
        (address[] memory tokens, ) = pdtStakingV2.getActiveRewardTokenList();
        assertEq(tokens.length, 2);

        // mark AERO as an inactive reward token
        pdtStakingV2.upsertRewardToken(address(aero), false);

        // check active reward token list
        (address[] memory tokens2, ) = pdtStakingV2.getActiveRewardTokenList();
        assertEq(tokens2[0], address(prime));
        assertEq(tokens2.length, 1);

        // mark AERO as an active reward token again
        pdtStakingV2.upsertRewardToken(address(aero), true);

        // check active reward token list
        (address[] memory tokens3, ) = pdtStakingV2.getActiveRewardTokenList();
        assertEq(tokens3.length, 2);

        vm.stopPrank();
    }

    /**
     * distribute
     */

    function test_distribute_StartFirstEpochAfterEpoch0Ended() public {
        assertEq(pdtStakingV2.currentEpochId(), 0);

        _creditPRIMERewardPool(1);
        _moveToNextEpoch(0);

        assertEq(pdtStakingV2.currentEpochId(), 1);
    }

    /**
     * stake
     */

    function test_stake_RevertIf_StakeMoreThanBalance() public {
        pdt.mint(staker, 100);
        assertEq(pdt.balanceOf(staker), 100);

        vm.startPrank(staker);
        vm.expectRevert();
        pdtStakingV2.stake(staker, 200);
        vm.stopPrank();
    }

    function testFuzz_stake_SetDetailsAfterStake(uint64 _stakeAmount) public {
        uint256 stakeAmount = uint256(_stakeAmount) + 1; // prevent zero stake by adding 1
        pdt.mint(staker, stakeAmount * 3);

        vm.startPrank(staker);
        pdt.approve(address(pdtStakingV2), stakeAmount);
        vm.expectEmit();
        emit Stake(staker, stakeAmount);
        pdtStakingV2.stake(staker, stakeAmount);
        vm.stopPrank();

        assertEq(pdt.balanceOf(staker), stakeAmount * 2);
        assertEq(pdtStakingV2.totalStaked(), stakeAmount);
        assertEq(pdtStakingV2.stakesByUser(staker), stakeAmount);
        assertEq(pdt.balanceOf(address(pdtStakingV2)), stakeAmount);
    }

    function testFuzz_stake_StakerWeightEqualsToContractWeightWhenOnlyStaker(
        uint64 _stakeAmount
    ) public {
        uint256 stakeAmount = uint256(_stakeAmount) + 1;
        pdt.mint(staker, stakeAmount * 3);

        vm.startPrank(staker);
        pdt.approve(address(pdtStakingV2), stakeAmount);
        pdtStakingV2.stake(staker, stakeAmount);
        vm.stopPrank();

        _creditPRIMERewardPool(1);
        _moveToNextEpoch(0);

        assertEq(pdtStakingV2.contractWeightAtEpoch(0), pdtStakingV2.userWeightAtEpoch(staker, 0));
    }

    function testFuzz_stake_SumOfStakerWeightEqualsToContractWeight(
        uint64 _stakeAmount1,
        uint64 _stakeAmount2
    ) public {
        uint256 stakeAmount1 = uint256(_stakeAmount1) + 1;
        uint256 stakeAmount2 = uint256(_stakeAmount2) + 1;
        pdt.mint(staker1, stakeAmount1);
        pdt.mint(staker2, stakeAmount2);

        vm.startPrank(staker1);
        pdt.approve(address(pdtStakingV2), stakeAmount1);
        pdtStakingV2.stake(staker1, stakeAmount1);
        vm.stopPrank();

        vm.startPrank(staker2);
        pdt.approve(address(pdtStakingV2), stakeAmount2);
        pdtStakingV2.stake(staker2, stakeAmount2);
        vm.stopPrank();

        assertEq(
            pdtStakingV2.totalStaked(),
            pdtStakingV2.stakesByUser(staker1) + pdtStakingV2.stakesByUser(staker2)
        );

        _creditPRIMERewardPool(1);
        _moveToNextEpoch(0);

        assertEq(
            pdtStakingV2.contractWeightAtEpoch(0),
            pdtStakingV2.userWeightAtEpoch(staker1, 0) + pdtStakingV2.userWeightAtEpoch(staker2, 0)
        );
    }

    /**
     * unstake
     */

    function testFuzz_unstake(uint64 _stakeAmount1, uint64 _stakeAmount2) public {
        // staker1 stakes in epoch 0
        // staker2 stakes in epoch 0
        uint256 stakeAmount1 = uint256(_stakeAmount1) + 1;
        uint256 stakeAmount2 = uint256(_stakeAmount2) + 1;
        pdt.mint(staker1, stakeAmount1);
        pdt.mint(staker2, stakeAmount2);

        vm.startPrank(staker1);
        pdt.approve(address(pdtStakingV2), stakeAmount1);
        pdtStakingV2.stake(staker1, stakeAmount1);
        vm.stopPrank();

        vm.startPrank(staker2);
        pdt.approve(address(pdtStakingV2), stakeAmount2);
        pdtStakingV2.stake(staker2, stakeAmount2);
        vm.stopPrank();

        // staker1 unstakes in epoch 0
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Unstake(staker1, stakeAmount1);
        pdtStakingV2.unstake(staker1);
        vm.stopPrank();

        // staker1's PDT balance should be the same as initial balance
        assertEq(pdt.balanceOf(staker1), stakeAmount1);
        // totalStaked should be equal to stakesByUser[staker2]
        assertEq(pdtStakingV2.totalStaked(), pdtStakingV2.stakesByUser(staker2));

        // staker1 cannot unstake again because already unstaked
        vm.startPrank(staker1);
        vm.expectRevert();
        pdtStakingV2.unstake(staker1);
        vm.stopPrank();

        // start epoch 1
        _creditPRIMERewardPool(1);
        _moveToNextEpoch(0);

        // contract weight should equals to staker2's weight at epoch 0
        assertEq(pdtStakingV2.contractWeightAtEpoch(0), pdtStakingV2.userWeightAtEpoch(staker2, 0));

        // staker2 unstakes in epoch 1
        vm.startPrank(staker2);
        pdtStakingV2.unstake(staker2);
        vm.stopPrank();

        // totalStaked should be zero
        assertEq(pdtStakingV2.totalStaked(), 0);

        // start epoch 2
        _creditPRIMERewardPool(1);
        _moveToNextEpoch(1);

        // contract weight at epoch 1 should be zero
        assertEq(pdtStakingV2.contractWeightAtEpoch(1), 0);
    }

    /**
     * claim
     */

    function test_claim_RevertIf_ClaimDuringEpoch0() public {
        vm.startPrank(staker);
        vm.expectRevert();
        pdtStakingV2.claim(staker);
        vm.stopPrank();
    }

    function testFuzz_claim_RevertIf_ClaimAfterAlreadyClaimedForEpoch(uint64 _stakeAmount) public {
        uint256 stakeAmount = uint256(_stakeAmount) + 1;
        pdt.mint(staker, stakeAmount * 3);

        vm.startPrank(staker);
        pdt.approve(address(pdtStakingV2), stakeAmount);
        pdtStakingV2.stake(staker, stakeAmount);
        vm.stopPrank();

        _creditPRIMERewardPool(100);
        _moveToNextEpoch(0);

        /// EPOCH 1

        vm.startPrank(staker);
        pdtStakingV2.claim(staker);
        vm.expectRevert();
        pdtStakingV2.claim(staker);
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
        pdt.mint(staker, stakeAmount * 3);

        vm.startPrank(staker);
        pdt.approve(address(pdtStakingV2), stakeAmount);
        pdtStakingV2.stake(staker, stakeAmount);
        vm.stopPrank();

        // add reward tokens to the staking contract
        vm.startPrank(owner);
        pdtStakingV2.upsertRewardToken(address(aero), true);
        _creditPRIMERewardPool(rewardAmount1);
        aero.mint(address(pdtStakingV2), rewardAmount2);
        vm.stopPrank();
        _moveToNextEpoch(0);

        /// EPOCH 1

        // there is no reward for epoch 0
        assertEq(pdtStakingV2.totalRewardsToDistribute(address(prime), 0), 0);
        assertEq(pdtStakingV2.totalRewardsToDistribute(address(prime), 1), rewardAmount1);

        // always add reward tokens to the staking contract before new epoch starts
        _creditPRIMERewardPool(rewardAmount1);
        aero.mint(address(pdtStakingV2), rewardAmount2);
        _moveToNextEpoch(1);

        /// EPOCH 2

        assertEq(pdtStakingV2.totalRewardsToDistribute(address(prime), 2), rewardAmount1);

        // claim epoch 1's rewards
        vm.startPrank(staker);
        pdtStakingV2.claim(staker);
        vm.stopPrank();

        assertEq(prime.balanceOf(staker), rewardAmount1);
        assertEq(aero.balanceOf(staker), rewardAmount2);
        assertEq(pdtStakingV2.totalRewardsClaimed(address(prime), 1), rewardAmount1);

        // stake more
        vm.startPrank(staker);
        pdt.approve(address(pdtStakingV2), stakeAmount);
        pdtStakingV2.stake(staker, stakeAmount);
        vm.stopPrank();

        // add more reward tokens to the staking contract
        prime.mint(address(pdtStakingV2), pdtStakingV2.totalRewardsToDistribute(address(prime), 2));
        aero.mint(address(pdtStakingV2), pdtStakingV2.totalRewardsToDistribute(address(aero), 2));
        _moveToNextEpoch(2);
        assertEq(pdtStakingV2.totalRewardsToDistribute(address(prime), 2), rewardAmount1);
        assertEq(pdtStakingV2.totalRewardsToDistribute(address(aero), 2), rewardAmount2);

        // EPOCH 3

        // claim epoch 2's rewards
        vm.startPrank(staker);
        pdtStakingV2.claim(staker);
        vm.stopPrank();

        assertEq(prime.balanceOf(staker), rewardAmount1 * 2);
        assertEq(aero.balanceOf(staker), rewardAmount2 * 2);
        assertEq(pdtStakingV2.totalRewardsClaimed(address(prime), 2), rewardAmount1);
    }

    function test_claim_MultipleClaimersWithNoUnstaking() public {
        /// EPOCH 0

        // prepare reward pool for epoch 1 & start
        _creditPRIMERewardPool(100);
        _moveToNextEpoch(0);

        /// EPOCH 1

        // staker1 stakes
        vm.startPrank(staker1);
        pdt.mint(staker1, 99999999999);
        pdt.approve(address(pdtStakingV2), 99999999999);
        pdtStakingV2.stake(staker1, 10);
        vm.stopPrank();

        // staker2 stakes
        vm.startPrank(staker2);
        pdt.mint(staker2, 99999999999);
        pdt.approve(address(pdtStakingV2), 99999999999);
        pdtStakingV2.stake(staker2, 40); // totalStaked: 50
        vm.stopPrank();

        // prepare reward pool for epoch 2 & start
        _creditPRIMERewardPool(300);
        _moveToNextEpoch(1);

        /// EPOCH 2

        // staker1 claims rewards for epoch 1
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Claim(staker1, 2, address(prime), (100 * 10) / (10 + 40));
        pdtStakingV2.claim(staker1);
        vm.stopPrank();

        // staker1 stakes
        vm.startPrank(staker1);
        pdtStakingV2.stake(staker1, 50); // totalStaked: 100
        vm.stopPrank();

        // prepare funds for epoch 3 & start
        _creditPRIMERewardPool(500);
        _moveToNextEpoch(2);

        /// EPOCH 3

        // staker1 claims rewards for epoch 2
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Claim(staker1, 3, address(prime), (300 * (10 + 50)) / (10 + 40 + 50));
        pdtStakingV2.claim(staker1);
        vm.stopPrank();

        // staker2 claims rewards for epoch 1 and 2
        vm.startPrank(staker2);
        vm.expectEmit();
        emit Claim(
            staker2,
            3,
            address(prime),
            (100 * 40) / (10 + 40) + (300 * 40) / (10 + 40 + 50)
        );
        pdtStakingV2.claim(staker2);
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
        pdt.mint(staker1, 99999999999);
        pdt.approve(address(pdtStakingV2), 99999999999);
        pdtStakingV2.stake(staker1, 10);
        vm.stopPrank();

        // staker2 stakes
        vm.startPrank(staker2);
        pdt.mint(staker2, 99999999999);
        pdt.approve(address(pdtStakingV2), 99999999999);
        pdtStakingV2.stake(staker2, 40); // totalStaked: 50
        vm.stopPrank();

        // prepare reward pool for epoch 2 & start
        _creditPRIMERewardPool(300);
        _moveToNextEpoch(1);

        /// EPOCH 2

        // staker1 claims rewards for epoch 1
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Claim(staker1, 2, address(prime), (100 * 10) / (10 + 40));
        pdtStakingV2.claim(staker1);
        vm.stopPrank();

        // staker1 unstakes
        vm.startPrank(staker1);
        pdtStakingV2.unstake(staker1); // totalStaked: 40 = 50 - 10
        vm.stopPrank();

        // prepare funds for epoch 3 & start
        _creditPRIMERewardPool(500);
        _moveToNextEpoch(2);

        /// EPOCH 3

        // staker1 doesn't have rewards for epoch 2
        vm.startPrank(staker1);
        pdtStakingV2.claim(staker1);
        vm.stopPrank();

        // staker2 claims rewards for epoch 1 and 2
        vm.startPrank(staker2);
        vm.expectEmit();
        emit Claim(staker2, 3, address(prime), (100 * 40) / (10 + 40) + (300 * 40) / 40);
        pdtStakingV2.claim(staker2);
        vm.stopPrank();
    }

    /**
     * transferStakes
     */

    function test_transferStakes() public {
        /// EPOCH 0

        // staker1 stakes 10
        pdt.mint(staker1, 10);
        vm.startPrank(staker1);
        pdt.approve(address(pdtStakingV2), 10);
        pdtStakingV2.stake(staker1, 10);
        vm.stopPrank();

        // move to next epoch
        _creditPRIMERewardPool(100);
        _moveToNextEpoch(0);

        /// EPOCH 1

        // transfer some of the stakes from staker1 to staker2
        vm.startPrank(staker1);
        pdtStakingV2.transferStakes(staker2, 2); // 8 + 2 = 10
        vm.stopPrank();

        // move to next epoch
        _creditPRIMERewardPool(200);
        _moveToNextEpoch(1);

        /// EPOCH 2

        // staker1 claims rewards
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Claim(staker1, 2, address(prime), (100 * 8) / (8 + 2));
        pdtStakingV2.claim(staker1);
        vm.stopPrank();

        // staker2 claims rewards
        vm.startPrank(staker2);
        vm.expectEmit();
        emit Claim(staker2, 2, address(prime), (100 * 2) / (8 + 2));
        pdtStakingV2.claim(staker2);
        vm.stopPrank();

        // transfer all of the stakes from staker1 to staker2
        vm.startPrank(staker1);
        vm.expectEmit();
        emit TransferStakes(staker1, staker2, 2, 8);
        pdtStakingV2.transferStakes(staker2, 8);
        vm.stopPrank();

        // move to next epoch
        _creditPRIMERewardPool(10);
        _moveToNextEpoch(2);

        /// EPOCH 3

        // staker1 can't claim rewards
        vm.startPrank(staker1);
        pdtStakingV2.claim(staker1);
        vm.stopPrank();

        // staker2 claims rewards
        vm.startPrank(staker2);
        vm.expectEmit();
        emit Claim(staker2, 3, address(prime), 200);
        pdtStakingV2.claim(staker2);
        vm.stopPrank();
    }

    /**
     * claimAmountForEpoch
     */

    function test_claimAmountForEpoch() public {
        /// EPOCH 0

        // register aero as a reward token
        vm.startPrank(owner);
        pdtStakingV2.upsertRewardToken(address(aero), true);
        vm.stopPrank();

        // move to epoch 1
        _creditPRIMERewardPool(100);
        _creditAERORewardPool(200);
        _moveToNextEpoch(0);

        /// EPOCH 1

        // staker1 stakes 10
        pdt.mint(staker1, 10);
        vm.startPrank(staker1);
        pdt.approve(address(pdtStakingV2), 10);
        pdtStakingV2.stake(staker1, 10);
        vm.stopPrank();

        // staker2 stakes 40
        pdt.mint(staker2, 40);
        vm.startPrank(staker2);
        pdt.approve(address(pdtStakingV2), 40);
        pdtStakingV2.stake(staker2, 40);
        vm.stopPrank();

        // move to epoch 2
        _creditPRIMERewardPool(10);
        _creditAERORewardPool(20);
        _moveToNextEpoch(1);

        /// EPOCH 2

        assertEq(
            pdtStakingV2.claimAmountForEpoch(staker1, 1, address(prime)),
            (100 * 10) / (10 + 40)
        );
        assertEq(
            pdtStakingV2.claimAmountForEpoch(staker1, 1, address(aero)),
            (200 * 10) / (10 + 40)
        );

        assertEq(
            pdtStakingV2.claimAmountForEpoch(staker2, 1, address(prime)),
            (100 * 40) / (10 + 40)
        );
        assertEq(
            pdtStakingV2.claimAmountForEpoch(staker2, 1, address(aero)),
            (200 * 40) / (10 + 40)
        );
    }

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
        pdt.mint(staker1, 10);
        vm.startPrank(staker1);
        pdt.approve(address(pdtStakingV2), 10);
        pdtStakingV2.stake(staker1, 10);
        vm.stopPrank();

        // staker2 stakes 40
        pdt.mint(staker2, 40);
        vm.startPrank(staker2);
        pdt.approve(address(pdtStakingV2), 40);
        pdtStakingV2.stake(staker2, 40);
        vm.stopPrank();

        // move to epoch 2
        _creditPRIMERewardPool(200);
        _moveToNextEpoch(1);

        /// EPOCH 2

        // staker1 claims rewards for epoch 1
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Claim(staker1, 2, address(prime), 20);
        pdtStakingV2.claim(staker1);
        vm.stopPrank();

        assertEq(pdtStakingV2.claimAmountForEpoch(staker2, 1, address(prime)), 80);

        assertEq(pdtStakingV2.pendingRewards(address(prime)), 0);

        // staker2 unstakes
        vm.startPrank(staker2);
        vm.expectEmit();
        emit Unstake(staker2, 40);
        pdtStakingV2.unstake(staker2);
        vm.stopPrank();

        assertEq(pdtStakingV2.claimAmountForEpoch(staker2, 1, address(prime)), 80);

        assertEq(pdtStakingV2.pendingRewards(address(prime)), 0);

        _creditPRIMERewardPool(300);

        assertEq(pdtStakingV2.pendingRewards(address(prime)), 300);
    }

    /// Helper Functions ///

    function _creditPRIMERewardPool(uint256 _amount) internal {
        prime.mint(address(pdtStakingV2), _amount);
    }

    function _creditAERORewardPool(uint256 _amount) internal {
        aero.mint(address(pdtStakingV2), _amount);
    }

    function _moveToNextEpoch(uint256 _currentEpochId) internal {
        (, uint256 epochEndTime, ) = pdtStakingV2.epoch(_currentEpochId);
        vm.warp(epochEndTime + 1 days);
        vm.startPrank(owner);
        pdtStakingV2.distribute();
        vm.stopPrank();
    }
}
