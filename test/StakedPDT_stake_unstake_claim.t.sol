// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Contract imports
import {StakedPDTTestBase} from "./StakedPDT_base.sol";

contract StakedPDTStakeUnstakeClaimTest is StakedPDTTestBase {
    uint256 primesForEpoch = 1000 ether;
    uint256 promptsForEpoch = 2000 ether;
    uint256 pdtInitialBalance = 1000 ether;

    /// @dev (user address => (epoch id => user weight))
    mapping(address => mapping(uint256 => uint256)) _tUserWeightAtEpoch;

    /// @dev (epoch id => user weight)
    mapping(uint256 => uint256) _tContractWeightAtEpoch;

    function setUp() public virtual override {
        super.setUp();
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
    }

    /**
     * Basic Staking
     *
     * Test single user staking PDT tokens.
     * - Verify the user's staked balance.
     * - Check if the multiplier starts at 1x on staking.
     *
     *
     * Multiplier Growth
     *
     * Test daily increase in multiplier.
     * - Stake tokens and call a function to simulate passing days.
     * - Verify multiplier increases by 1x each day.
     * - Ensure multiplier resets to 1x at the start of a new epoch.
     *
     *
     * Multiple Users Staking
     *
     * Multiple users stake different amounts of PDT.
     * - Verify each user's staked balance and multiplier.
     * - Ensure overall stakes and rewards distribution is correct.
     */
    function testFuzz_basicStaking(
        uint64 stakesAmount1,
        uint64 stakesAmount2,
        uint64 stakesAmount3
    ) public {
        uint256 _stakesAmount1 = uint256(stakesAmount1) + 1;
        uint256 _stakesAmount2 = uint256(stakesAmount2) + 1;
        uint256 _stakesAmount3 = uint256(stakesAmount3) + 1;

        /// EPOCH 0

        // Staking is not allowed in epoch 0
        _creditPRIMERewardPool(primesForEpoch);
        _moveToNextEpoch(0);

        /// EPOCH 1

        // staker1 stakes `_stakesAmount1`
        vm.startPrank(staker1);
        bStakedPDT.stake(staker1, _stakesAmount1);
        vm.stopPrank();

        // Ensure multiplier increases by 1x each day.
        assertEq(bStakedPDT.contractWeight(), 0);
        // epoch 1, staker1, day 0 weightAtLastInteraction
        (, uint256 e1_s1_d0_weightAtLastInteraction) = bStakedPDT.stakeDetails(staker1);
        assertEq(e1_s1_d0_weightAtLastInteraction, 0);
        assertEq(bStakedPDT.userTotalWeight(staker1), 0);
        skip(1 days);
        assertEq(bStakedPDT.contractWeight(), _stakesAmount1);
        assertEq(bStakedPDT.userTotalWeight(staker1), _stakesAmount1);

        // staker2 stakes `_stakesAmount2`
        vm.startPrank(staker2);
        bStakedPDT.stake(staker2, _stakesAmount2);
        vm.stopPrank();

        // Ensure multiplier increases by 1x each day.
        assertEq(bStakedPDT.contractWeight(), _stakesAmount1);
        skip(6 days);
        assertEq(bStakedPDT.contractWeight(), _stakesAmount1 * 7 + _stakesAmount2 * 6);
        assertEq(bStakedPDT.userTotalWeight(staker1), _stakesAmount1 * 7);
        assertEq(bStakedPDT.userTotalWeight(staker2), _stakesAmount2 * 6);

        // staker3 stakes `_stakesAmount3`
        vm.startPrank(staker3);
        bStakedPDT.stake(staker3, _stakesAmount3);
        vm.stopPrank();
        assertEq(bStakedPDT.contractWeight(), _stakesAmount1 * 7 + _stakesAmount2 * 6);

        // Time to end of epoch
        (, uint256 epochEndTime, ) = bStakedPDT.epoch(1);
        vm.warp(epochEndTime + 1 days);
        _tUserWeightAtEpoch[staker1][1] = _stakesAmount1 * 28;
        _tUserWeightAtEpoch[staker2][1] = _stakesAmount2 * 27;
        _tUserWeightAtEpoch[staker3][1] = _stakesAmount3 * 21;
        _tContractWeightAtEpoch[1] =
            _stakesAmount1 *
            28 +
            _stakesAmount2 *
            27 +
            _stakesAmount3 *
            21;

        // Ensure multiplier increases by 1x each day.
        assertEq(bStakedPDT.contractWeight(), _tContractWeightAtEpoch[1]);
        assertEq(bStakedPDT.userTotalWeight(staker1), _tUserWeightAtEpoch[staker1][1]);
        assertEq(bStakedPDT.userTotalWeight(staker2), _tUserWeightAtEpoch[staker2][1]);
        assertEq(bStakedPDT.userTotalWeight(staker3), _tUserWeightAtEpoch[staker3][1]);

        // Move to epoch 2
        vm.startPrank(epochManager);
        _creditPRIMERewardPool(primesForEpoch);
        bStakedPDT.distribute();
        vm.stopPrank();

        /// EPOCH 2

        // Ensure user/contract weight is saved correctly in the next epoch.
        assertEq(bStakedPDT.userWeightAtEpoch(staker1, 1), _tUserWeightAtEpoch[staker1][1]);
        assertEq(bStakedPDT.userWeightAtEpoch(staker2, 1), _tUserWeightAtEpoch[staker2][1]);
        assertEq(bStakedPDT.userWeightAtEpoch(staker3, 1), _tUserWeightAtEpoch[staker3][1]);
        assertEq(bStakedPDT.contractWeightAtEpoch(1), _tContractWeightAtEpoch[1]);

        // Ensure multiplier resets to 1x at the start of a new epoch.
        assertEq(bStakedPDT.contractWeight(), 0);
        assertEq(bStakedPDT.userTotalWeight(staker1), 0);
        assertEq(bStakedPDT.userTotalWeight(staker2), 0);
        assertEq(bStakedPDT.userTotalWeight(staker3), 0);

        // Ensure the overall reward distribution is correct
        uint256 e1_s1_claimAmount = bStakedPDT.claimAmountForEpoch(staker1, 1, bPRIMEAddress);
        assertEq(
            e1_s1_claimAmount,
            (primesForEpoch * _tUserWeightAtEpoch[staker1][1]) / _tContractWeightAtEpoch[1]
        );

        vm.startPrank(staker1);
        bStakedPDT.claim(staker1);
        assertEq(bPRIME.balanceOf(staker1), e1_s1_claimAmount);
        vm.stopPrank();

        vm.startPrank(staker2);
        bStakedPDT.claim(staker2);
        assertEq(
            bPRIME.balanceOf(staker2),
            (primesForEpoch * _tUserWeightAtEpoch[staker2][1]) / _tContractWeightAtEpoch[1]
        );
        vm.stopPrank();

        vm.startPrank(staker3);
        bStakedPDT.claim(staker3);
        assertEq(
            bPRIME.balanceOf(staker3),
            (primesForEpoch * _tUserWeightAtEpoch[staker3][1]) / _tContractWeightAtEpoch[1]
        );
        vm.stopPrank();

        // In epoch 2, staker1 stakes another `_stakesAmount1`
        vm.startPrank(staker1);
        bStakedPDT.stake(staker1, _stakesAmount1);
        vm.stopPrank();

        // epoch 2, staker1, day 0 weightAtLastInteraction
        (, uint256 e2_s1_d0_weightAtLastInteraction) = bStakedPDT.stakeDetails(staker1);
        assertEq(e2_s1_d0_weightAtLastInteraction, 0);
    }

    /**
     * Unstaking Before Epoch Ends
     *
     * User unstakes partially or fully before epoch ends.
     * - Check if appropriate amount of PDT is unstaked.
     * - Validate remaining staked balance and multipliers.
     */
    function testFuzz_unstakingBeforeEpochEnds(
        uint64 stakesAmount1,
        uint64 stakesAmount2,
        uint64 stakesAmount3
    ) public {
        // To test unstaking one third amount of staked amount, ensure
        // the minimum value of staking amount is 3.
        uint256 _stakesAmount1 = uint256(stakesAmount1) + 3;
        uint256 _stakesAmount2 = uint256(stakesAmount2) + 3;
        uint256 _stakesAmount3 = uint256(stakesAmount3) + 3;

        /// EPOCH 0

        _creditPRIMERewardPool(primesForEpoch);
        _moveToNextEpoch(0);

        /// EPOCH 1

        (uint256 epoch1StartTime, , ) = bStakedPDT.epoch(1);

        // staker1 stakes `_stakesAmount1`
        vm.startPrank(staker1);
        bStakedPDT.stake(staker1, _stakesAmount1);
        vm.stopPrank();

        vm.warp(epoch1StartTime + 1 days);

        // staker2 stakes `_stakesAmount2`
        vm.startPrank(staker2);
        bStakedPDT.stake(staker2, _stakesAmount2);
        vm.stopPrank();

        vm.warp(epoch1StartTime + 7 days);

        // staker3 stakes `_stakesAmount3`
        vm.startPrank(staker3);
        bStakedPDT.stake(staker3, _stakesAmount3);
        vm.stopPrank();

        vm.warp(epoch1StartTime + 8 days);

        // staker1 unstakes `_stakesAmount1` / 3
        vm.startPrank(staker1);
        bStakedPDT.unstake(staker1, _stakesAmount1 / 3);
        vm.stopPrank();

        assertEq(bStakedPDT.userTotalWeight(staker1), _stakesAmount1 * 8);
        vm.warp(epoch1StartTime + 10 days);
        assertEq(
            bStakedPDT.userTotalWeight(staker1),
            _stakesAmount1 * 8 + (_stakesAmount1 - _stakesAmount1 / 3) * 2
        );

        // Time to end of epoch
        (, uint256 epochEndTime, ) = bStakedPDT.epoch(1);
        vm.warp(epochEndTime + 1 days);
        _tUserWeightAtEpoch[staker1][1] =
            _stakesAmount1 *
            8 +
            (_stakesAmount1 - _stakesAmount1 / 3) *
            20;
        _tUserWeightAtEpoch[staker2][1] = _stakesAmount2 * 27;
        _tUserWeightAtEpoch[staker3][1] = _stakesAmount3 * 21;
        _tContractWeightAtEpoch[1] =
            _tUserWeightAtEpoch[staker1][1] +
            _tUserWeightAtEpoch[staker2][1] +
            _tUserWeightAtEpoch[staker3][1];

        // Ensure multiplier increases by 1x each day.
        assertEq(bStakedPDT.contractWeight(), _tContractWeightAtEpoch[1]);
        assertEq(bStakedPDT.userTotalWeight(staker1), _tUserWeightAtEpoch[staker1][1]);
        assertEq(bStakedPDT.userTotalWeight(staker2), _tUserWeightAtEpoch[staker2][1]);
        assertEq(bStakedPDT.userTotalWeight(staker3), _tUserWeightAtEpoch[staker3][1]);

        // Move to epoch 2
        vm.startPrank(epochManager);
        _creditPRIMERewardPool(primesForEpoch);
        bStakedPDT.distribute();
        vm.stopPrank();

        /// EPOCH 2

        // Ensure user/contract weight is saved correctly in the next epoch.
        assertEq(bStakedPDT.userWeightAtEpoch(staker1, 1), _tUserWeightAtEpoch[staker1][1]);
        assertEq(bStakedPDT.userWeightAtEpoch(staker2, 1), _tUserWeightAtEpoch[staker2][1]);
        assertEq(bStakedPDT.userWeightAtEpoch(staker3, 1), _tUserWeightAtEpoch[staker3][1]);
        assertEq(bStakedPDT.contractWeightAtEpoch(1), _tContractWeightAtEpoch[1]);

        // Ensure multiplier resets to 1x at the start of a new epoch.
        assertEq(bStakedPDT.contractWeight(), 0);
        assertEq(bStakedPDT.userTotalWeight(staker1), 0);
        assertEq(bStakedPDT.userTotalWeight(staker2), 0);
        assertEq(bStakedPDT.userTotalWeight(staker3), 0);

        // Ensure the overall reward distribution is correct
        vm.startPrank(staker1);
        bStakedPDT.claim(staker1);
        assertEq(
            bPRIME.balanceOf(staker1),
            (primesForEpoch * _tUserWeightAtEpoch[staker1][1]) / _tContractWeightAtEpoch[1]
        );
        vm.stopPrank();

        vm.startPrank(staker2);
        bStakedPDT.claim(staker2);
        assertEq(
            bPRIME.balanceOf(staker2),
            (primesForEpoch * _tUserWeightAtEpoch[staker2][1]) / _tContractWeightAtEpoch[1]
        );
        vm.stopPrank();

        vm.startPrank(staker3);
        bStakedPDT.claim(staker3);
        assertEq(
            bPRIME.balanceOf(staker3),
            (primesForEpoch * _tUserWeightAtEpoch[staker3][1]) / _tContractWeightAtEpoch[1]
        );
        vm.stopPrank();

        // In epoch 2, staker1 stakes another `_stakesAmount1`
        vm.startPrank(staker1);
        bStakedPDT.stake(staker1, _stakesAmount1);
        vm.stopPrank();

        // epoch 2, staker1, day 0 weightAtLastInteraction
        (, uint256 e2_s1_d0_weightAtLastInteraction) = bStakedPDT.stakeDetails(staker1);
        assertEq(e2_s1_d0_weightAtLastInteraction, 0);
    }

    /**
     * Claiming Rewards
     *
     * Users claim their PRIME token rewards.
     * - Ensure rewards are calculated correctly based on staked amount, time and multiplier.
     * - Verify the reward token balances of users after claiming.
     *
     *
     * Epoch Transition
     *
     * Simulate the transition from one epoch to another.
     * - Ensure all multipliers reset to 1x.
     * - Verify no issues in transitioning and reward calculations.
     */
    function testFuzz_claimingRewards(
        uint64 stakesAmount1,
        uint64 stakesAmount2,
        uint64 stakesAmount3
    ) public {
        uint256 _stakesAmount1 = uint256(stakesAmount1) + 1;
        uint256 _stakesAmount2 = uint256(stakesAmount2) + 1;
        uint256 _stakesAmount3 = uint256(stakesAmount3) + 1;

        /// EPOCH 0

        _creditPRIMERewardPool(primesForEpoch);
        _moveToNextEpoch(0);

        /// EPOCH 1

        // staker1 stakes `_stakesAmount1`
        vm.startPrank(staker1);
        bStakedPDT.stake(staker1, _stakesAmount1);
        vm.stopPrank();

        // staker2 stakes `_stakesAmount2`
        vm.startPrank(staker2);
        bStakedPDT.stake(staker2, _stakesAmount2);
        vm.stopPrank();

        // staker3 stakes `_stakesAmount3`
        vm.startPrank(staker3);
        bStakedPDT.stake(staker3, _stakesAmount3);
        vm.stopPrank();

        // register PROMPT token as a new reward token
        vm.startPrank(owner);
        bStakedPDT.registerNewRewardToken(bPROMPTAddress);
        vm.stopPrank();

        _creditPRIMERewardPool(primesForEpoch);
        _creditPROMPTRewardPool(promptsForEpoch);
        _moveToNextEpoch(1);

        /// EPOCH 2

        // staker1 stakes `_stakesAmount1`
        vm.startPrank(staker1);
        bStakedPDT.stake(staker1, _stakesAmount1);
        vm.stopPrank();

        // staker2 stakes `_stakesAmount2` * 2
        vm.startPrank(staker2);
        bStakedPDT.stake(staker2, _stakesAmount2 * 2);
        vm.stopPrank();

        _creditPRIMERewardPool(primesForEpoch);
        _moveToNextEpoch(2);

        /// EPOCH 3

        vm.startPrank(staker1);
        bStakedPDT.claim(staker1);
        vm.stopPrank();

        vm.startPrank(staker2);
        bStakedPDT.claim(staker2);
        vm.stopPrank();

        vm.startPrank(staker3);
        bStakedPDT.claim(staker3);
        vm.stopPrank();

        // Ensure rewards distribution is correct
        uint256 e1_s1_weight = bStakedPDT.userWeightAtEpoch(staker1, 1);
        uint256 e2_s1_weight = bStakedPDT.userWeightAtEpoch(staker1, 2);
        uint256 e1_s2_weight = bStakedPDT.userWeightAtEpoch(staker2, 1);
        uint256 e2_s2_weight = bStakedPDT.userWeightAtEpoch(staker2, 2);
        uint256 e1_s3_weight = bStakedPDT.userWeightAtEpoch(staker3, 1);
        uint256 e2_s3_weight = bStakedPDT.userWeightAtEpoch(staker3, 2);
        uint256 e1_c_weight = bStakedPDT.contractWeightAtEpoch(1);
        uint256 e2_c_weight = bStakedPDT.contractWeightAtEpoch(2);
        assertEq(
            (primesForEpoch * e1_s1_weight) /
                e1_c_weight +
                (primesForEpoch * e2_s1_weight) /
                e2_c_weight,
            bPRIME.balanceOf(staker1)
        );
        assertEq(
            (primesForEpoch * e1_s2_weight) /
                e1_c_weight +
                (primesForEpoch * e2_s2_weight) /
                e2_c_weight,
            bPRIME.balanceOf(staker2)
        );
        assertEq(
            (primesForEpoch * e1_s3_weight) /
                e1_c_weight +
                (primesForEpoch * e2_s3_weight) /
                e2_c_weight,
            bPRIME.balanceOf(staker3)
        );
        assertEq((promptsForEpoch * e2_s1_weight) / e2_c_weight, bPROMPT.balanceOf(staker1));
        assertEq((promptsForEpoch * e2_s2_weight) / e2_c_weight, bPROMPT.balanceOf(staker2));
        assertEq((promptsForEpoch * e2_s3_weight) / e2_c_weight, bPROMPT.balanceOf(staker3));
    }

    /**
     * Edge Cases
     *
     * No staking activity in an epoch:
     * - Verify no rewards are distributed.
     */
    function test_edgeCases() public {
        /// EPOCH 0

        _creditPRIMERewardPool(primesForEpoch);
        _moveToNextEpoch(0);

        /// EPOCH 1

        _creditPRIMERewardPool(primesForEpoch);
        _moveToNextEpoch(1);

        /// EPOCH 2

        vm.startPrank(staker1);
        bStakedPDT.claim(staker1);
        vm.stopPrank();

        // Ensure no rewards are distributed when there was no staking activity
        assertEq(bPRIME.balanceOf(staker1), 0);
    }

    /**
     * Abnormal Behavior
     *
     * - Staking when the epoch is about to end.
     */
    function test_abnormalBehavior() public {
        /// EPOCH 0

        _creditPRIMERewardPool(primesForEpoch);
        _moveToNextEpoch(0);

        /// EPOCH 1

        vm.startPrank(staker1);
        bStakedPDT.stake(staker1, 1 ether);
        vm.stopPrank();

        (, uint256 e1EndTime, ) = bStakedPDT.epoch(1);
        vm.warp(e1EndTime - 10 minutes);
        vm.startPrank(staker2);
        bStakedPDT.stake(staker2, 1 ether);
        vm.stopPrank();

        _creditPRIMERewardPool(primesForEpoch);
        _moveToNextEpoch(1);

        /// EPOCH 2

        vm.startPrank(staker1);
        bStakedPDT.claim(staker1);
        vm.stopPrank();

        vm.startPrank(staker2);
        bStakedPDT.claim(staker2);
        vm.stopPrank();

        assertEq(
            bPRIME.balanceOf(staker1) / bPRIME.balanceOf(staker2),
            bStakedPDT.epochLength() / 10 minutes
        );
    }
}
