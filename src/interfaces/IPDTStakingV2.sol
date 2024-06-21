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
     * @notice Error for if user has already claimed up to current epoch
     */
    error ClaimedUpToEpoch();

    /**
     * @notice Error for if an action is performed when the current epoch has ended
     */
    error OutOfEpoch();

    /**
     * @notice Can't stake zero amount.
     */
    error InvalidStakeAmount();

    /**
     * @notice Error for if unstaking zero or more than staked
     * @param amountStaked Total amount of PDT staked by the user
     * @param amountUnstaking The amount of PDT to unstake
     */
    error InvalidUnstakeAmount(uint256 amountStaked, uint256 amountUnstaking);

    /**
     * @notice Error for if reward pool for the next epoch is not ready while distributing
     * @param nextEpochId The epoch id to be started
     */
    error EmptyRewardPool(uint256 nextEpochId);

    /**
     * @notice Error for if the owner attemps to register existing reward token
     * @param rewardToken The address of already registered reward token
     */
    error DuplicatedRewardToken(address rewardToken);

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
     * @notice Stake PDT
     * @param _to The address that will receive credit for stake
     * @param _amount The amount of PDT to stake
     */
    function stake(address _to, uint256 _amount) external;

    /**
     * @notice Unstake PDT
     * @param _to The address that will receive PDT unstaked
     * @param _amount The amount of PDT to unstake
     */
    function unstake(address _to, uint256 _amount) external;

    /**
     * @notice Claims all pending rewards for msg.sender.
     * Claiming rewards is available just once per epoch.
     * @param _to The address to send rewards to
     */
    function claim(address _to) external;

    /**
     * @notice Transfer some amount of stakes to another wallet
     * @param _to The target wallet address for transfering stakes
     * @param _amount The amount of stakes to transfer to `_to` address
     */
    function transferStakes(address _to, uint256 _amount) external;
}
