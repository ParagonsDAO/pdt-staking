// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PDT Staking v2 Interface
 * @dev Interface for managing token stake.
 */
interface IPDTStakingV2 {
    /// EVENTS ///

    /**
     * @notice Emitted if epoch 0 is pushed back
     * @param newEndTime New end time of epoch 0
     */
    event Epoch0PushedBack(uint256 indexed newEndTime);

    /**
     * @notice Emitted if epoch length is updated
     * @param previousEpochLength Previous length of epochs
     * @param newEpochLength New length of epochs
     */
    event EpochLengthUpdated(uint256 indexed previousEpochLength, uint256 indexed newEpochLength);

    /**
     * @notice Emitted upon address staking
     * @param to Address of who is receiving credit of stake
     * @param newStakeAmount New stake amount of `to`
     * @param newWeightAmount New weight amount of `to`
     */
    event Staked(address to, uint256 indexed newStakeAmount, uint256 indexed newWeightAmount);

    /**
     * @notice Emitted upon user unstaking
     * @param staker Address of who is unstaking
     * @param amountUnstaked Amount `staker` unstaked
     */
    event Unstaked(address staker, uint256 indexed amountUnstaked);

    /**
     * @notice Emitted upon staker claiming
     * @param staker Address of who claimed rewards
     * @param epochsClaimed Array of epochs claimed
     * @param claimed Amount claimed
     */
    event Claimed(address staker, uint256[] indexed epochsClaimed, uint256 indexed claimed);

    /// ERRORS ///

    /**
     * @notice Error for if epoch is invalid
     */
    error InvalidEpoch();

    /**
     * @notice Error for if user has already claimed up to current epoch
     */
    error ClaimedUpToEpoch();

    /**
     * @notice Error for if staking more than balance
     */
    error MoreThanBalance();

    /**
     * @notice Error for if unstaking when nothing is staked
     */
    error NothingStaked();

    /**
     * @notice Error for if not owner
     */
    error NotOwner();

    /**
     * @notice Error for if zero address
     */
    error ZeroAddress();

    /**
     * @notice Error for if after epoch 0
     */
    error AfterEpoch0();

    /// STRUCTS ///

    /**
     * @notice Details for epoch
     * @param totalToDistribute Total amount of token to distribute for epoch
     * @param totalClaimed Total amount of tokens claimed from epoch
     * @param startTime Timestamp epoch started
     * @param endTime Timestamp epoch ends
     * @param weightAtEnd Weight of staked tokens at end of epoch
     */
    struct Epoch {
        uint256 totalToDistribute;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
        uint256 weightAtEnd;
    }

    /**
     * @notice Stake details for user
     * @param amountStaked Amount user has staked
     * @param lastInteraction Last timestamp user interacted
     * @param weightAtLastInteraction Weight of stake at last interaction
     */
    struct Stake {
        uint256 amountStaked;
        uint256 lastInteraction;
        uint256 weightAtLastInteraction;
    }
}
