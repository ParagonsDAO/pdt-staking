// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Forge imports
import {Test, console} from "forge-std/Test.sol";

// Contract imports
import {PDTStaking} from "../src/contracts/PDTStaking.sol";
import {PDTStakingV2} from "../src/contracts/PDTStakingV2.sol";
import {IPDTStakingV2} from "../src/interfaces/IPDTStakingV2.sol";

// Mock imports
import {PRIMEMock} from "../src/mocks/PRIMEMock.sol";
import {PROMPTMock} from "../src/mocks/PROMPTMock.sol";
import {PDTOFTMock} from "../src/mocks/PDTOFTMock.sol";

// DevTools imports
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract PDTStakingV2Test is Test, TestHelperOz5, IPDTStakingV2 {
    // Mock endpoint of base/sepolia base chain
    uint32 bEid = 2;

    PDTStakingV2 public bPDTStakingV2;
    PDTOFTMock public bPDTOFT;
    PRIMEMock public bPRIME;
    PROMPTMock public bPROMPT;

    address owner;
    address staker = address(0x9);
    address staker1 = address(0x1);
    address staker2 = address(0x2);

    uint256 initialEpochLength = 4 weeks;
    uint256 initialFirstEpochStartIn = 1 days;

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        bPRIME = new PRIMEMock("PRIME Token", "PRIME");
        bPROMPT = new PROMPTMock("PROMPT Token", "PROMPT");

        bPDTOFT = PDTOFTMock(
            _deployOApp(
                type(PDTOFTMock).creationCode,
                abi.encode("ParagonsDAO Token", "PDT", address(endpoints[bEid]), address(this))
            )
        );

        bPDTStakingV2 = new PDTStakingV2(
            initialEpochLength, // epochLength
            initialFirstEpochStartIn, // firstEpochStartIn
            address(bPDTOFT), // PDT address
            msg.sender // initial owner
        );

        owner = bPDTStakingV2.owner();

        vm.startPrank(owner);
        bPDTStakingV2.upsertRewardToken(address(bPRIME), true);
        vm.stopPrank();
    }

    /**
     * Implement interface functions
     */

    function stake(address _to, uint256 _amount) external {}

    function unstake(address _to, uint256 _amount) external {}

    function claim(address _to) external {}

    function transferStakes(address _to, uint256 _amount) external {}

    /**
     * contructor
     */

    function test_constructor() public {
        assertEq(bPDTStakingV2.epochLength(), initialEpochLength);

        (uint256 _startTime, uint256 _endTime, ) = bPDTStakingV2.epoch(0);
        assertEq(_endTime - _startTime, initialFirstEpochStartIn);

        assertEq(bPDTStakingV2.pdt(), address(bPDTOFT));
    }

    /**
     * updateEpochLength
     */

    function test_updateEpochLength_RevertIf_ZeroNewEpochLength() public {
        vm.expectRevert();
        bPDTStakingV2.updateEpochLength(0);
    }

    function testFuzz_updateEpochLength_RevertIf_NonOwnerUpdate(uint128 _newEpochLength) public {
        uint256 newEpochLength = uint256(_newEpochLength) + 1;

        vm.expectRevert();
        bPDTStakingV2.updateEpochLength(newEpochLength);
    }

    function testFuzz_updateEpochLength_OwnerUpdateEpochLength(uint128 _newEpochLength) public {
        uint256 newEpochLength = uint256(_newEpochLength) + 1;

        uint256 _epochId = bPDTStakingV2.currentEpochId();
        (uint256 _startTime, , ) = bPDTStakingV2.epoch(_epochId);

        vm.startPrank(owner);
        vm.expectEmit();
        emit UpdateEpochLength(0, initialEpochLength, newEpochLength);
        bPDTStakingV2.updateEpochLength(newEpochLength);

        assertEq(bPDTStakingV2.epochLength(), newEpochLength);

        (, uint256 _newEndTime, ) = bPDTStakingV2.epoch(_epochId);
        assertEq(_startTime + newEpochLength, _newEndTime);
    }

    function test_updateEpochLength_unstake_RevertIf_EpochHasEnded() public {
        /// EPOCH 0

        uint256 initialBalance = 100;
        bPDTOFT.mint(staker1, initialBalance);

        vm.startPrank(staker1);
        bPDTOFT.approve(address(bPDTStakingV2), initialBalance);

        // Can't stake if current epoch has ended
        (, uint256 epoch0EndTime, ) = bPDTStakingV2.epoch(0);
        vm.warp(epoch0EndTime + 1 days);
        vm.expectRevert(bytes("Epoch has ended"));
        bPDTStakingV2.stake(staker1, initialBalance);

        vm.expectRevert(bytes("Epoch has ended"));
        bPDTStakingV2.unstake(staker1, initialBalance);
        vm.stopPrank();

        // Extend current epoch
        vm.startPrank(owner);
        bPDTStakingV2.updateEpochLength(bPDTStakingV2.epochLength() + 2 days);
        vm.stopPrank();

        // Should be able to stake
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Stake(staker1, initialBalance, 0);
        bPDTStakingV2.stake(staker1, initialBalance);
        vm.stopPrank();

        // End epoch 0
        _creditPRIMERewardPool(initialBalance);
        _moveToNextEpoch(0);

        /// EPOCH 1

        // Should be able to unstake half of initial stakes
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Unstake(staker1, initialBalance / 2, 1);
        bPDTStakingV2.unstake(staker1, initialBalance / 2);
        vm.stopPrank();

        (, uint256 epoch1EndTime, ) = bPDTStakingV2.epoch(1);
        vm.warp(epoch1EndTime + 1 days);

        assertGt(block.timestamp, epoch1EndTime);

        // Should not be able to unstake since epoch has ended
        vm.startPrank(staker1);
        vm.expectRevert(bytes("Epoch has ended"));
        bPDTStakingV2.unstake(staker1, initialBalance / 2);
        vm.stopPrank();
    }

    /**
     * upsertRewardToken & getActiveRewardTokenList
     */

    function test_upsertRewardToken_RevertIf_NonOwnerTry() public {
        vm.expectRevert();
        bPDTStakingV2.upsertRewardToken(address(bPROMPT), true);
    }

    function test_upsertRewardToken_OwnerCanUpsert() public {
        vm.startPrank(owner);
        // add PROMPT as a new active reward token
        bPDTStakingV2.upsertRewardToken(address(bPROMPT), true);

        // check active reward token list
        (address[] memory tokens, ) = bPDTStakingV2.getActiveRewardTokenList();
        assertEq(tokens.length, 2);

        // mark PROMPT as an inactive reward token
        bPDTStakingV2.upsertRewardToken(address(bPROMPT), false);

        // check active reward token list
        (address[] memory tokens2, ) = bPDTStakingV2.getActiveRewardTokenList();
        assertEq(tokens2[0], address(bPRIME));
        assertEq(tokens2.length, 1);

        // mark PROMPT as an active reward token again
        bPDTStakingV2.upsertRewardToken(address(bPROMPT), true);

        // check active reward token list
        (address[] memory tokens3, ) = bPDTStakingV2.getActiveRewardTokenList();
        assertEq(tokens3.length, 2);

        vm.stopPrank();
    }

    /**
     * distribute
     */

    function test_distribute_StartFirstEpochAfterEpoch0Ended() public {
        assertEq(bPDTStakingV2.currentEpochId(), 0);

        _creditPRIMERewardPool(1);
        _moveToNextEpoch(0);

        assertEq(bPDTStakingV2.currentEpochId(), 1);
    }

    /**
     * stake
     */

    function testFuzz_stake_RevertIf_StakeMoreThanBalance(uint128 _amount) public {
        uint256 initialBalance = uint256(_amount) + 1;
        bPDTOFT.mint(staker, initialBalance);
        assertEq(bPDTOFT.balanceOf(staker), initialBalance);

        vm.startPrank(staker);
        vm.expectRevert();
        bPDTStakingV2.stake(staker, initialBalance + 1);
        vm.stopPrank();
    }

    function testFuzz_stake_SetDetailsAfterStake(uint64 _stakeAmount) public {
        uint256 stakeAmount = uint256(_stakeAmount) + 1; // prevent zero stake by adding 1

        assertEq(bPDTOFT.balanceOf(staker), 0);
        assertEq(bPDTStakingV2.totalStaked(), 0);
        assertEq(bPDTStakingV2.stakesByUser(staker), 0);
        assertEq(bPDTOFT.balanceOf(address(bPDTStakingV2)), 0);

        bPDTOFT.mint(staker, stakeAmount * 3);

        vm.startPrank(staker);
        bPDTOFT.approve(address(bPDTStakingV2), stakeAmount);
        vm.expectEmit();
        emit Stake(staker, stakeAmount, 0);
        bPDTStakingV2.stake(staker, stakeAmount);
        vm.stopPrank();

        assertEq(bPDTOFT.balanceOf(staker), stakeAmount * 2);
        assertEq(bPDTStakingV2.totalStaked(), stakeAmount);
        assertEq(bPDTStakingV2.stakesByUser(staker), stakeAmount);
        assertEq(bPDTOFT.balanceOf(address(bPDTStakingV2)), stakeAmount);
    }

    function testFuzz_stake_StakerWeightEqualsToContractWeightWhenOnlyStaker(
        uint64 _stakeAmount
    ) public {
        uint256 stakeAmount = uint256(_stakeAmount) + 1;
        bPDTOFT.mint(staker, stakeAmount * 3);

        vm.startPrank(staker);
        bPDTOFT.approve(address(bPDTStakingV2), stakeAmount);
        bPDTStakingV2.stake(staker, stakeAmount);
        vm.stopPrank();

        _creditPRIMERewardPool(1);
        _moveToNextEpoch(0);

        assertEq(
            bPDTStakingV2.contractWeightAtEpoch(0),
            bPDTStakingV2.userWeightAtEpoch(staker, 0)
        );
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
        bPDTOFT.approve(address(bPDTStakingV2), stakeAmount1);
        bPDTStakingV2.stake(staker1, stakeAmount1);
        vm.stopPrank();

        vm.startPrank(staker2);
        bPDTOFT.approve(address(bPDTStakingV2), stakeAmount2);
        bPDTStakingV2.stake(staker2, stakeAmount2);
        vm.stopPrank();

        assertEq(
            bPDTStakingV2.totalStaked(),
            bPDTStakingV2.stakesByUser(staker1) + bPDTStakingV2.stakesByUser(staker2)
        );

        _creditPRIMERewardPool(1);
        _moveToNextEpoch(0);

        /// EPOCH 1

        assertEq(
            bPDTStakingV2.contractWeightAtEpoch(0),
            bPDTStakingV2.userWeightAtEpoch(staker1, 0) +
                bPDTStakingV2.userWeightAtEpoch(staker2, 0)
        );
    }

    /**
     * unstake
     */

    function testFuzz_unstake(uint8 _stakeAmount1, uint8 _stakeAmount2) public {
        /// EPOCH 0
        // staker1 stakes in epoch 0
        // staker2 stakes in epoch 0
        uint256 stakeAmount1 = uint256(_stakeAmount1) + 1;
        uint256 stakeAmount2 = uint256(_stakeAmount2) + 1;
        bPDTOFT.mint(staker1, stakeAmount1);
        bPDTOFT.mint(staker2, stakeAmount2);

        // staker1 stakes stakeAmount1
        vm.startPrank(staker1);
        bPDTOFT.approve(address(bPDTStakingV2), stakeAmount1);
        bPDTStakingV2.stake(staker1, stakeAmount1);
        vm.stopPrank();

        // staker2 stakes stakeAmount2
        vm.startPrank(staker2);
        bPDTOFT.approve(address(bPDTStakingV2), stakeAmount2);
        bPDTStakingV2.stake(staker2, stakeAmount2);
        vm.stopPrank();

        // staker1 unstakes half in epoch 0
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Unstake(staker1, stakeAmount1 / 2, 0);
        bPDTStakingV2.unstake(staker1, stakeAmount1 / 2);
        vm.stopPrank();

        // staker1 should receive half of staked PDT balance
        assertEq(bPDTOFT.balanceOf(staker1), stakeAmount1 / 2);
        // totalStaked should be equal to stakesByUser[staker1] + stakesByUser[staker2]
        assertEq(
            bPDTStakingV2.totalStaked(),
            bPDTStakingV2.stakesByUser(staker1) + bPDTStakingV2.stakesByUser(staker2)
        );

        // staker1 is able to unstake again
        vm.startPrank(staker1);
        bPDTStakingV2.unstake(staker1, stakeAmount1 - stakeAmount1 / 2);
        vm.stopPrank();

        // start epoch 1
        _creditPRIMERewardPool(1);
        _moveToNextEpoch(0);

        /// EPOCH 1

        // staker2 unstakes in epoch 1
        vm.startPrank(staker2);
        bPDTStakingV2.unstake(staker2, stakeAmount2);
        vm.stopPrank();

        // totalStaked should be zero
        assertEq(bPDTStakingV2.totalStaked(), 0);

        // start epoch 2
        _creditPRIMERewardPool(1);
        _moveToNextEpoch(1);

        /// EPOCH 2

        // contract weight at epoch 1 should be zero
        assertEq(bPDTStakingV2.contractWeightAtEpoch(1), 0);

        // both stakers can claim rewards
        vm.startPrank(staker1);
        bPDTStakingV2.claim(staker1);
        vm.stopPrank();

        vm.startPrank(staker2);
        bPDTStakingV2.claim(staker2);
        vm.stopPrank();
    }

    /**
     * claim
     */

    function test_claim_RevertIf_ClaimDuringEpoch0() public {
        vm.startPrank(staker);
        vm.expectRevert();
        bPDTStakingV2.claim(staker);
        vm.stopPrank();
    }

    function testFuzz_claim_RevertIf_ClaimAfterAlreadyClaimedForEpoch(uint64 _stakeAmount) public {
        uint256 stakeAmount = uint256(_stakeAmount) + 1;
        bPDTOFT.mint(staker, stakeAmount * 3);

        vm.startPrank(staker);
        bPDTOFT.approve(address(bPDTStakingV2), stakeAmount);
        bPDTStakingV2.stake(staker, stakeAmount);
        vm.stopPrank();

        _creditPRIMERewardPool(100);
        _moveToNextEpoch(0);

        /// EPOCH 1

        vm.startPrank(staker);
        bPDTStakingV2.claim(staker);
        vm.expectRevert();
        bPDTStakingV2.claim(staker);
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
        bPDTOFT.mint(staker, stakeAmount * 3);

        vm.startPrank(staker);
        bPDTOFT.approve(address(bPDTStakingV2), stakeAmount);
        bPDTStakingV2.stake(staker, stakeAmount);
        vm.stopPrank();

        // add reward tokens to the staking contract
        vm.startPrank(owner);
        bPDTStakingV2.upsertRewardToken(address(bPROMPT), true);
        _creditPRIMERewardPool(rewardAmount1);
        bPROMPT.mint(address(bPDTStakingV2), rewardAmount2);
        vm.stopPrank();
        _moveToNextEpoch(0);

        /// EPOCH 1

        // there is no reward for epoch 0
        assertEq(bPDTStakingV2.totalRewardsToDistribute(address(bPRIME), 0), 0);
        assertEq(bPDTStakingV2.totalRewardsToDistribute(address(bPRIME), 1), rewardAmount1);

        // always add reward tokens to the staking contract before new epoch starts
        _creditPRIMERewardPool(rewardAmount1);
        bPROMPT.mint(address(bPDTStakingV2), rewardAmount2);
        _moveToNextEpoch(1);

        /// EPOCH 2

        assertEq(bPDTStakingV2.totalRewardsToDistribute(address(bPRIME), 2), rewardAmount1);

        // claim epoch 1's rewards
        vm.startPrank(staker);
        bPDTStakingV2.claim(staker);
        vm.stopPrank();

        assertEq(bPRIME.balanceOf(staker), rewardAmount1);
        assertEq(bPROMPT.balanceOf(staker), rewardAmount2);
        assertEq(bPDTStakingV2.totalRewardsClaimed(address(bPRIME), 1), rewardAmount1);

        // stake more
        vm.startPrank(staker);
        bPDTOFT.approve(address(bPDTStakingV2), stakeAmount);
        bPDTStakingV2.stake(staker, stakeAmount);
        vm.stopPrank();

        // add more reward tokens to the staking contract
        bPRIME.mint(
            address(bPDTStakingV2),
            bPDTStakingV2.totalRewardsToDistribute(address(bPRIME), 2)
        );
        bPROMPT.mint(
            address(bPDTStakingV2),
            bPDTStakingV2.totalRewardsToDistribute(address(bPROMPT), 2)
        );
        _moveToNextEpoch(2);
        assertEq(bPDTStakingV2.totalRewardsToDistribute(address(bPRIME), 2), rewardAmount1);
        assertEq(bPDTStakingV2.totalRewardsToDistribute(address(bPROMPT), 2), rewardAmount2);

        // EPOCH 3

        // claim epoch 2's rewards
        vm.startPrank(staker);
        bPDTStakingV2.claim(staker);
        vm.stopPrank();

        assertEq(bPRIME.balanceOf(staker), rewardAmount1 * 2);
        assertEq(bPROMPT.balanceOf(staker), rewardAmount2 * 2);
        assertEq(bPDTStakingV2.totalRewardsClaimed(address(bPRIME), 2), rewardAmount1);
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
        bPDTOFT.approve(address(bPDTStakingV2), 99999999999);
        bPDTStakingV2.stake(staker1, epoch1_staker1_stakedAmount);
        vm.stopPrank();

        // staker2 stakes
        vm.startPrank(staker2);
        bPDTOFT.mint(staker2, 99999999999);
        bPDTOFT.approve(address(bPDTStakingV2), 99999999999);
        bPDTStakingV2.stake(staker2, epoch1_staker2_stakedAmount); // totalStaked: 50
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
        bPDTStakingV2.claim(staker1);
        bPRIME.balanceOf(staker1);
        vm.stopPrank();

        // staker1 stakes
        vm.startPrank(staker1);
        bPDTStakingV2.stake(staker1, 50); // totalStaked: 100
        vm.stopPrank();

        // prepare funds for epoch 3 & start
        _creditPRIMERewardPool(500);
        _moveToNextEpoch(2);

        /// EPOCH 3

        // staker1 claims rewards for epoch 2
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Claim(staker1, 3, address(bPRIME), (300 * (10 + 50)) / (10 + 40 + 50));
        bPDTStakingV2.claim(staker1);
        vm.stopPrank();

        // staker2 claims rewards for epoch 1 and 2
        vm.startPrank(staker2);
        vm.expectEmit();
        emit Claim(
            staker2,
            3,
            address(bPRIME),
            (100 * 40) / (10 + 40) + (300 * 40) / (10 + 40 + 50)
        );
        bPDTStakingV2.claim(staker2);
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
        bPDTOFT.approve(address(bPDTStakingV2), 99999999999);
        bPDTStakingV2.stake(staker1, 10);
        vm.stopPrank();

        // staker2 stakes
        vm.startPrank(staker2);
        bPDTOFT.mint(staker2, 99999999999);
        bPDTOFT.approve(address(bPDTStakingV2), 99999999999);
        bPDTStakingV2.stake(staker2, 40); // totalStaked: 50
        vm.stopPrank();

        // prepare reward pool for epoch 2 & start
        _creditPRIMERewardPool(300);
        _moveToNextEpoch(1);

        /// EPOCH 2

        // staker1 claims rewards for epoch 1
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Claim(staker1, 2, address(bPRIME), (100 * 10) / (10 + 40));
        bPDTStakingV2.claim(staker1);
        vm.stopPrank();

        // staker1 unstakes
        vm.startPrank(staker1);
        bPDTStakingV2.unstake(staker1, 10); // totalStaked: 40 = 50 - 10
        vm.stopPrank();

        // prepare funds for epoch 3 & start
        _creditPRIMERewardPool(500);
        _moveToNextEpoch(2);

        /// EPOCH 3

        // staker1 doesn't have rewards for epoch 2
        vm.startPrank(staker1);
        bPDTStakingV2.claim(staker1);
        vm.stopPrank();

        // staker2 claims rewards for epoch 1 and 2
        vm.startPrank(staker2);
        vm.expectEmit();
        emit Claim(staker2, 3, address(bPRIME), (100 * 40) / (10 + 40) + (300 * 40) / 40);
        bPDTStakingV2.claim(staker2);
        vm.stopPrank();
    }

    /**
     * transferStakes
     */

    function test_transferStakes() public {
        /// EPOCH 0

        // staker1 stakes 10
        bPDTOFT.mint(staker1, 10);
        vm.startPrank(staker1);
        bPDTOFT.approve(address(bPDTStakingV2), 10);
        bPDTStakingV2.stake(staker1, 10);
        vm.stopPrank();

        // move to next epoch
        _creditPRIMERewardPool(100);
        _moveToNextEpoch(0);

        /// EPOCH 1

        // transfer some of the stakes from staker1 to staker2
        vm.startPrank(staker1);
        bPDTStakingV2.transferStakes(staker2, 2); // 8 + 2 = 10
        vm.stopPrank();

        // move to next epoch
        _creditPRIMERewardPool(200);
        _moveToNextEpoch(1);

        /// EPOCH 2

        // staker1 claims rewards
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Claim(staker1, 2, address(bPRIME), (100 * 8) / (8 + 2));
        bPDTStakingV2.claim(staker1);
        vm.stopPrank();

        // staker2 claims rewards
        vm.startPrank(staker2);
        vm.expectEmit();
        emit Claim(staker2, 2, address(bPRIME), (100 * 2) / (8 + 2));
        bPDTStakingV2.claim(staker2);
        vm.stopPrank();

        // transfer all of the stakes from staker1 to staker2
        vm.startPrank(staker1);
        vm.expectEmit();
        emit TransferStakes(staker1, staker2, 2, 8);
        bPDTStakingV2.transferStakes(staker2, 8);
        vm.stopPrank();

        // move to next epoch
        _creditPRIMERewardPool(10);
        _moveToNextEpoch(2);

        /// EPOCH 3

        // staker1 can't claim rewards
        vm.startPrank(staker1);
        bPDTStakingV2.claim(staker1);
        vm.stopPrank();

        // staker2 claims rewards
        vm.startPrank(staker2);
        vm.expectEmit();
        emit Claim(staker2, 3, address(bPRIME), 200);
        bPDTStakingV2.claim(staker2);
        vm.stopPrank();
    }

    /**
     * claimAmountForEpoch
     */

    function test_claimAmountForEpoch() public {
        /// EPOCH 0

        // register aero as a reward token
        vm.startPrank(owner);
        bPDTStakingV2.upsertRewardToken(address(bPROMPT), true);
        vm.stopPrank();

        // move to epoch 1
        _creditPRIMERewardPool(100);
        _creditPROMPTRewardPool(200);
        _moveToNextEpoch(0);

        /// EPOCH 1

        // staker1 stakes 10
        bPDTOFT.mint(staker1, 10);
        vm.startPrank(staker1);
        bPDTOFT.approve(address(bPDTStakingV2), 10);
        bPDTStakingV2.stake(staker1, 10);
        vm.stopPrank();

        // staker2 stakes 40
        bPDTOFT.mint(staker2, 40);
        vm.startPrank(staker2);
        bPDTOFT.approve(address(bPDTStakingV2), 40);
        bPDTStakingV2.stake(staker2, 40);
        vm.stopPrank();

        // move to epoch 2
        _creditPRIMERewardPool(10);
        _creditPROMPTRewardPool(20);
        _moveToNextEpoch(1);

        /// EPOCH 2

        assertEq(
            bPDTStakingV2.claimAmountForEpoch(staker1, 1, address(bPRIME)),
            (100 * 10) / (10 + 40)
        );
        assertEq(
            bPDTStakingV2.claimAmountForEpoch(staker1, 1, address(bPROMPT)),
            (200 * 10) / (10 + 40)
        );

        assertEq(
            bPDTStakingV2.claimAmountForEpoch(staker2, 1, address(bPRIME)),
            (100 * 40) / (10 + 40)
        );
        assertEq(
            bPDTStakingV2.claimAmountForEpoch(staker2, 1, address(bPROMPT)),
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
        bPDTOFT.mint(staker1, 10);
        vm.startPrank(staker1);
        bPDTOFT.approve(address(bPDTStakingV2), 10);
        bPDTStakingV2.stake(staker1, 10);
        vm.stopPrank();

        // staker2 stakes 40
        bPDTOFT.mint(staker2, 40);
        vm.startPrank(staker2);
        bPDTOFT.approve(address(bPDTStakingV2), 40);
        bPDTStakingV2.stake(staker2, 40);
        vm.stopPrank();

        // move to epoch 2
        _creditPRIMERewardPool(200);
        _moveToNextEpoch(1);

        /// EPOCH 2

        // staker1 claims rewards for epoch 1
        vm.startPrank(staker1);
        vm.expectEmit();
        emit Claim(staker1, 2, address(bPRIME), 20);
        bPDTStakingV2.claim(staker1);
        vm.stopPrank();

        assertEq(bPDTStakingV2.claimAmountForEpoch(staker2, 1, address(bPRIME)), 80);

        assertEq(bPDTStakingV2.pendingRewards(address(bPRIME)), 0);

        // staker2 unstakes
        vm.startPrank(staker2);
        vm.expectEmit();
        emit Unstake(staker2, 40, 2);
        bPDTStakingV2.unstake(staker2, 40);
        vm.stopPrank();

        assertEq(bPDTStakingV2.claimAmountForEpoch(staker2, 1, address(bPRIME)), 80);

        assertEq(bPDTStakingV2.pendingRewards(address(bPRIME)), 0);

        _creditPRIMERewardPool(300);

        assertEq(bPDTStakingV2.pendingRewards(address(bPRIME)), 300);
    }

    /// Helper Functions ///

    function _creditPRIMERewardPool(uint256 _amount) internal {
        bPRIME.mint(address(bPDTStakingV2), _amount);
    }

    function _creditPROMPTRewardPool(uint256 _amount) internal {
        bPROMPT.mint(address(bPDTStakingV2), _amount);
    }

    function _moveToNextEpoch(uint256 _currentEpochId) internal {
        (, uint256 epochEndTime, ) = bPDTStakingV2.epoch(_currentEpochId);
        vm.warp(epochEndTime + 1 days);
        vm.startPrank(owner);
        bPDTStakingV2.distribute();
        vm.stopPrank();
    }
}
