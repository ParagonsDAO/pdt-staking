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
    event PushBackEpoch0(uint256 indexed newEndTime);

    /**
     * @notice Emitted if epoch length is updated
     * @param epochId The epoch Id that the epoch length is updated in
     * @param previousEpochLength Previous length of epochs
     * @param newEpochLength New length of epochs
     */
    event UpdateEpochLength(
        uint256 indexed epochId,
        uint256 indexed previousEpochLength,
        uint256 indexed newEpochLength
    );

    /**
     * @notice Emitted if a reward token is registered
     * @param epochId The epoch Id that the reward token info is added or updated in
     * @param rewardToken The address of new reward token
     */
    event RegisterNewRewardToken(uint256 indexed epochId, address indexed rewardToken);

    /**
     * @notice Emitted if a new epoch is started
     * @param newEpochId The new epoch id
     */
    event Distribute(uint256 indexed newEpochId);

    /**
     * @notice Emitted upon user staking
     * @param to Address of who is receiving credit of stake
     * @param amount Stake amount of `to`
     * @param epochId The epoch id which staking is happened in
     */
    event Stake(address indexed to, uint256 indexed amount, uint256 indexed epochId);

    /**
     * @notice Emitted upon user unstaking
     * @param staker Address of who is unstaking
     * @param amount Amount `staker` unstaked
     * @param epochId The epoch id which unstaking is happened in
     */
    event Unstake(address indexed staker, uint256 indexed amount, uint256 indexed epochId);

    /**
     * @notice Emitted upon staker claiming
     * @param staker Address of who claimed rewards
     * @param currentEpochId Current epoch id
     * @param rewardToken Address of claimed reward token
     * @param amount Amount claimed
     */
    event Claim(
        address indexed staker,
        uint256 indexed currentEpochId,
        address indexed rewardToken,
        uint256 amount
    );

    /**
     * @notice Emitted upon staker transfers stakes to another user
     * @param from The address of who is sending stakes
     * @param to The address of who is receiving stakes
     * @param epochId Current epoch id
     * @param amount The amount that is transfered
     */
    event TransferStakes(
        address indexed from,
        address indexed to,
        uint256 indexed epochId,
        uint256 amount
    );

    /**
     * @notice Emitted upon the owner withdraw reward tokens
     * @param rewardToken The address of reward token
     * @param amount The amount of withdrawn reward tokens
     */
    event WithdrawRewardToken(address indexed rewardToken, uint256 indexed amount);

    /**
     * @notice Emitted upon owner updates reward duration
     * @param newRewardDuration The time-to-live duration for rewards in seconds
     */
    event UpdateRewardDuration(uint256 indexed newRewardDuration);

    /// ERRORS ///

    /**
     * @notice Can't withdraw unregistered reward token
     */
    error InvalidRewardToken();

    /**
     * @notice Can't withdraw zero reward tokens
     */
    error InvalidWithdrawAmount();

    /**
     * @notice Can't register already registered token
     * @param rewardToken The address of already registered reward token
     */
    error DuplicatedRewardToken(address rewardToken);

    /**
     * @notice Can't distribute if reward pool for the next epoch is not ready
     * @param nextEpochId The epoch id to be started
     */
    error EmptyRewardPool(uint256 nextEpochId);

    /**
     * @notice Can't claim if rewards are already claimed up to current epoch
     */
    error ClaimedUpToEpoch();

    /**
     * @notice Can't stake/unstake if the current epoch has ended
     */
    error OutOfEpoch();

    /**
     * @notice Can't stake zero amount.
     */
    error InvalidStakeAmount();

    /**
     * @notice Can't unstaking zero or more than staked
     * @param amountStaked Total amount of PDT staked by the user
     * @param amountUnstaking The amount of PDT to unstake
     */
    error InvalidUnstakeAmount(uint256 amountStaked, uint256 amountUnstaking);

    /**
     * @notice Can't transfer zero amount of stakes, can't transfer to zero address
     * or to msg.sender.
     *
     * Emits a {TransferStakes} event.
     */
    error InvalidStakesTransfer();

    /// STRUCTS ///

    /**
     * @notice Contains information about a specific staking epoch
     * @param startTime The start time of the epoch, represented as a UNIX timestamp
     * @param endTime The end time of the epoch, also represented as a UNIX timestamp
     * @param weightAtEnd The cumulative weight of staked tokens at the conclusion of the epoch
     */
    struct Epoch {
        uint256 startTime;
        uint256 endTime;
        uint256 weightAtEnd;
    }

    /// EXTERNAL FUNCTIONS ///

    /**
     * @notice Stake PDT.
     * @param to The address that will receive credit for stake.
     * @param amount The amount of PDT to stake.
     *
     * Requirements:
     *
     * - should stake during the current epoch is live.
     * - `to` shouldn't be zero address.
     * - `amount` shouldn't be zero.
     *
     * Emits a {Stake} event.
     */
    function stake(address to, uint256 amount) external;

    /**
     * @notice Unstake PDT.
     * @param to The address that will receive PDT unstaked.
     * @param amount The amount of PDT to unstake.
     *
     * Requirements:
     *
     * - should unstake during the current epoch is live.
     * * - `to` shouldn't be zero address.
     * - `amount` shouldn't be zero.
     * - should unstake not more than staked amount.
     *
     * Emits an {Unstake} event.
     */
    function unstake(address to, uint256 amount) external;

    /**
     * @notice Claims all pending rewards for msg.sender.
     * Claiming rewards is available just once per epoch.
     * @param to The address to send rewards to
     *
     * Emits a {Claim} event.
     */
    function claim(address to) external;

    /**
     * @notice Transfer some amount of stakes to another wallet
     * @param to The target wallet address for transfering stakes
     * @param amount The amount of stakes to transfer to `to` address
     *
     * Requirements:
     *
     * - `to` shouldn't be zero address nor msg.sender
     * - `amount` shouldn't be zero
     */
    function transferStakes(address to, uint256 amount) external;
}
