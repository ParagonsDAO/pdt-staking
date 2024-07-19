// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PDT Staking v2 Interface
 * @dev Interface for managing token stake.
 */
interface IStakedPDT {
    /// EVENTS ///

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
     * @param epochId Current epoch id
     * @param rewardToken Address of new reward token
     */
    event RegisterNewRewardToken(uint256 indexed epochId, address indexed rewardToken);

    /**
     * @notice Emitted if a reward token is unregistered
     * @param epochId Current epoch id
     * @param rewardToken Address of unregistered reward token
     */
    event UnregisterRewardToken(uint256 indexed epochId, address indexed rewardToken);

    /**
     * @notice Emitted if a contract address is whitelisted or not
     * @param value Address of the contract
     * @param isWhitelisted Boolean true/false
     */
    event UpdateWhitelistedContract(address indexed value, bool indexed isWhitelisted);

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
     * @notice Emitted upon staker claiming
     * @param staker Address of who claimed rewards
     * @param currentEpochId Current epoch id
     * @param rewardToken Address of expired reward token
     * @param amount Amount expired
     */
    event RewardsExpired(
        address indexed staker,
        uint256 indexed currentEpochId,
        address indexed rewardToken,
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
     * @notice The number of rewards expiry threshold can't be zero
     */
    error InvalidRewardsExpiryThreshold();

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
     * @notice Can't stake zero.
     */
    error InvalidStakeAmount();

    /**
     * @notice Can't unstake zero.
     */
    error InvalidUnstakeAmount();

    /**
     * @notice Can't transfer zero amount of stakes, or to non-whitelisted
     * addresses.
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

    /**
     * @notice Stake details for user
     * @param lastInteraction Last timestamp user interacted
     * @param weightAtLastInteraction Weight of stake at last interaction
     */
    struct StakeDetails {
        uint256 lastInteraction;
        uint256 weightAtLastInteraction;
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
}
