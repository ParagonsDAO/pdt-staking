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
     * @notice Emitted if a reward token info is added or updated
     * @param epochId The epoch Id that the reward token info is added or updated in
     * @param rewardToken The address of reward token to be added or updated within contract
     * @param isActive Indicates that `rewardToken` will be an active/inactive reward token
     */
    event UpsertRewardToken(
        uint256 indexed epochId,
        address indexed rewardToken,
        bool indexed isActive
    );

    /**
     * @notice Emitted upon user staking
     * @param to Address of who is receiving credit of stake
     * @param amount Stake amount of `to`
     * @param epochId The epoch id which staking is happened in
     */
    event Stake(address to, uint256 indexed amount, uint256 epochId);

    /**
     * @notice Emitted upon user unstaking
     * @param staker Address of who is unstaking
     * @param amount Amount `staker` unstaked
     * @param epochId The epoch id which unstaking is happened in
     */
    event Unstake(address staker, uint256 indexed amount, uint256 epochId);

    /**
     * @notice Emitted upon staker claiming
     * @param staker Address of who claimed rewards
     * @param currentEpochId Current epoch id
     * @param rewardToken Address of claimed reward token
     * @param amount Amount claimed
     */
    event Claim(
        address staker,
        uint256 indexed currentEpochId,
        address indexed rewardToken,
        uint256 indexed amount
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

    /// ERRORS ///

    /**
     * @notice Error for if epoch param of a function is not earlier than current epoch
     */
    error InvalidEpoch();

    /**
     * @notice Error for if user has already claimed up to current epoch
     */
    error ClaimedUpToEpoch();

    /**
     * @notice Error for if unstaking when nothing is staked
     */
    error NothingStaked();

    /**
     * @notice Error for if address is zero address
     */
    error ZeroAddress();

    /**
     * @notice Error for if `pushBackEpoch0` is called after epoch 0
     */
    error AfterEpoch0();

    /**
     * @notice Error for if reward pool for the next epoch is not ready while distributing
     * @param rewardToken The address of reward token to distribute
     * @param currentEpochId The epoch id which is going to be ended
     */
    error EmptyRewardPool(address rewardToken, uint256 currentEpochId);

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
     * @notice Represents the status of a reward token within the contract
     * @param isActive Indicates whether this token is currently active for rewarding users. If `true`, the token is used as a reward
     * @param index The position of this reward token in the overall list of reward tokens
     */
    struct RewardTokenInfo {
        bool isActive;
        uint256 index;
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
