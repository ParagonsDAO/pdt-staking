// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IPDTStakingV2} from "../interfaces/IPDTStakingV2.sol";

/**
 * @title PDT Staking v2
 * @notice Contract that allows users to stake PDT
 * @author Michael
 */
contract PDTStakingV2 is IPDTStakingV2, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /// STATE VARIABLES ///

    /**
     * Epoch Configuration
     */

    /// @notice Current epoch id
    uint256 public currentEpochId;

    /// @notice The duration of each epoch in seconds
    uint256 public epochLength;

    /// @notice The time-to-live duration for rewards in seconds
    uint256 public rewardDuration = 104 weeks; // initial reward duration = 2 years

    /// @notice Epoch id to epoch details
    mapping(uint256 => Epoch) public epoch;

    /**
     * Staking Metrics
     */

    /// @notice Total amount of staked PDT within contract
    uint256 public totalStaked;

    /// @notice The immutable address of PDT token utilized for staking
    address public immutable pdt;

    /**
     * Reward Tokens
     */

    /// @notice Dynamic array to store reward token addresses
    address[] public rewardTokenList;

    /// @notice Reward token to its unclaimed amount
    mapping(address => uint256) public unclaimedRewards;

    /// @notice Maps each reward token to their respective rewards allocation for every epoch
    mapping(address => mapping(uint256 => uint256)) public totalRewardsToDistribute;

    /// @notice Maps each reward token to their respective claimed amount for every epoch
    mapping(address => mapping(uint256 => uint256)) public totalRewardsClaimed;

    /**
     * User Information
     */

    /// @notice Account to the claim reward status of certain epoch id
    mapping(address => mapping(uint256 => bool)) public userClaimedEpoch;

    /// @notice Account to its weight at a certain epoch
    mapping(address => mapping(uint256 => uint256)) internal _userWeightAtEpoch;

    /// @notice Account to the last interacted epoch id
    mapping(address => uint256) public epochLeftOff;

    /// @notice Account to the last claimed epoch id
    mapping(address => uint256) public claimLeftOff;

    /// @notice Account to the amount of staked tokens
    mapping(address => uint256) public stakesByUser;

    /// CONSTRUCTOR ///

    /**
     * @notice Constructs the contract.
     * @param _epochLength The duration of each epoch in seconds
     * @param _firstEpochStartIn The duration of seconds the first epoch will starts in
     * @param _pdt The address of PDT token
     * @param _initialOwner The address of initial owner
     */
    constructor(
        uint256 _epochLength,
        uint256 _firstEpochStartIn,
        address _pdt,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_epochLength > 0, "Zero epochLength");
        require(_firstEpochStartIn > 0, "Zero firstEpochStartIn");
        require(_pdt != address(0), "Zero Address: PDT");

        epochLength = _epochLength;
        epoch[0].endTime = block.timestamp + _firstEpochStartIn;
        epoch[0].startTime = block.timestamp;
        pdt = _pdt;
    }

    /// OWNER FUNCTION ///

    /**
     * @notice Update epoch length
     * @param _epochLength New epoch length in seconds
     */
    function updateEpochLength(uint256 _epochLength) external onlyOwner {
        require(_epochLength > 0, "Invalid new epoch length");

        uint256 previousEpochLength = epochLength;
        epochLength = _epochLength;

        epoch[currentEpochId].endTime = epoch[currentEpochId].startTime + _epochLength;

        emit UpdateEpochLength(currentEpochId, previousEpochLength, _epochLength);
    }

    /**
     * @notice Update reward duration
     * @param _newRewardDuration The time-to-live duration for rewards in seconds
     */
    function updateRewardDuration(uint256 _newRewardDuration) external onlyOwner {
        require(_newRewardDuration > 0, "Invalid reward duration");
        require(_newRewardDuration > epochLength, "Invalid reward duration");

        rewardDuration = _newRewardDuration;

        emit UpdateRewardDuration(_newRewardDuration);
    }

    /**
     * @notice Register a new reward token
     * @param _newToken The address of reward token
     */
    function registerNewRewardToken(address _newToken) external onlyOwner {
        require(_newToken != address(0), "Invalid reward token");

        uint256 numOfRewardTokens = rewardTokenList.length;

        for (uint256 i = 0; i < numOfRewardTokens; ) {
            if (rewardTokenList[i] == _newToken) {
                revert DuplicatedRewardToken(_newToken);
            }

            unchecked {
                ++i;
            }
        }

        // If _newToken is not found in rewardTokenList, then add it
        rewardTokenList.push(_newToken);

        emit RegisterNewRewardToken(currentEpochId, _newToken);
    }

    /**
     * @notice Update epoch details if time
     * @dev Revert if the reward pool for the next epoch is empty
     */
    function distribute() external onlyOwner {
        Epoch memory _currentEpoch = epoch[currentEpochId];

        if (block.timestamp >= _currentEpoch.endTime) {
            epoch[currentEpochId].weightAtEnd = totalStaked;
            ++currentEpochId;

            uint256 _nRewardTokenTypes = rewardTokenList.length;
            uint256 _nRewardTokenTypesForNextEpoch;

            for (uint256 i; i < _nRewardTokenTypes; ) {
                address _rewardToken = rewardTokenList[i];
                uint256 _rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
                uint256 _rewardsToDistribute = _rewardBalance - unclaimedRewards[_rewardToken];

                if (_rewardsToDistribute > 0) {
                    totalRewardsToDistribute[_rewardToken][currentEpochId] = _rewardsToDistribute;
                    unclaimedRewards[_rewardToken] = _rewardBalance;
                    ++_nRewardTokenTypesForNextEpoch;
                }

                unchecked {
                    ++i;
                }
            }

            if (_nRewardTokenTypesForNextEpoch == 0) {
                revert EmptyRewardPool(currentEpochId);
            }

            _currentEpoch.startTime = block.timestamp;
            _currentEpoch.endTime = block.timestamp + epochLength;

            epoch[currentEpochId] = _currentEpoch;
        }
    }

    /**
     * @notice Returns epoch id from which rewards are active
     */
    function rewardsActiveFrom() public view returns (uint256 bottomEpochId_) {
        uint256 _currentEpochId = currentEpochId;
        uint256 _rewardDuration = rewardDuration;
        uint256 end = epoch[_currentEpochId].startTime;

        for (uint256 i = _currentEpochId; i > 0; ) {
            uint256 start = epoch[i - 1].startTime;
            if (end - start > _rewardDuration) {
                bottomEpochId_ = i;
                break;
            }

            unchecked {
                --i;
            }
        }
    }

    /// EXTERNAL FUNCTIONS ///

    /// @inheritdoc IPDTStakingV2
    function stake(address _to, uint256 _amount) external nonReentrant {
        require(_amount > 0, "Invalid stake amount");
        require(block.timestamp < epoch[currentEpochId].endTime, "Epoch has ended");

        _setUserWeightAtEpoch(_to);

        totalStaked += _amount;
        stakesByUser[_to] += _amount;

        IERC20(pdt).safeTransferFrom(msg.sender, address(this), _amount);

        emit Stake(_to, _amount, currentEpochId);
    }

    /// @inheritdoc IPDTStakingV2
    function unstake(address _to, uint256 _amount) external nonReentrant {
        require(_amount > 0, "Invalid unstake amount");
        require(block.timestamp < epoch[currentEpochId].endTime, "Epoch has ended");

        uint256 amountStaked = stakesByUser[_to];
        require(_amount <= amountStaked, "Insufficient stakes");

        _setUserWeightAtEpoch(msg.sender);

        totalStaked -= _amount;
        stakesByUser[_to] -= _amount;

        IERC20(pdt).safeTransfer(_to, _amount);

        emit Unstake(msg.sender, _amount, currentEpochId);
    }

    /// @inheritdoc IPDTStakingV2
    function claim(address _to) external nonReentrant {
        _setUserWeightAtEpoch(msg.sender);

        uint256 _claimLeftOff = claimLeftOff[msg.sender];
        uint256 _bottomEpochId = rewardsActiveFrom();

        if (_bottomEpochId > _claimLeftOff) {
            _claimLeftOff = _bottomEpochId;
        }

        if (_claimLeftOff == currentEpochId) revert ClaimedUpToEpoch();

        address[] memory _rewardTokenList = rewardTokenList;
        uint256 _tokenListSize = _rewardTokenList.length;
        uint256[] memory _pendingRewards = new uint256[](_tokenListSize);

        for (_claimLeftOff; _claimLeftOff < currentEpochId; ) {
            uint256 _contractWeightAtEpoch = contractWeightAtEpoch(_claimLeftOff);

            if (!userClaimedEpoch[msg.sender][_claimLeftOff] && _contractWeightAtEpoch > 0) {
                userClaimedEpoch[msg.sender][_claimLeftOff] = true;

                uint256 _weightAtEpoch = _userWeightAtEpoch[msg.sender][_claimLeftOff];

                if (_weightAtEpoch > 0) {
                    for (uint256 i; i < _tokenListSize; ) {
                        address _rewardToken = _rewardTokenList[i];

                        uint256 _totalRewardsToDistributeAtEpoch = totalRewardsToDistribute[
                            _rewardToken
                        ][_claimLeftOff];

                        uint256 _totalRewardsClaimedAtEpoch = totalRewardsClaimed[_rewardToken][
                            _claimLeftOff
                        ];

                        if (_totalRewardsToDistributeAtEpoch > 0) {
                            uint256 _epochRewards = (_totalRewardsToDistributeAtEpoch *
                                _weightAtEpoch) / _contractWeightAtEpoch;
                            if (
                                _totalRewardsClaimedAtEpoch + _epochRewards >
                                _totalRewardsToDistributeAtEpoch
                            ) {
                                _epochRewards =
                                    _totalRewardsToDistributeAtEpoch -
                                    _totalRewardsClaimedAtEpoch;
                            }

                            _pendingRewards[i] += _epochRewards;

                            totalRewardsClaimed[_rewardToken][_claimLeftOff] += _epochRewards;
                        }

                        unchecked {
                            ++i;
                        }
                    }
                }
            }

            unchecked {
                ++_claimLeftOff;
            }
        }

        claimLeftOff[msg.sender] = currentEpochId;

        for (uint256 i; i < _tokenListSize; ) {
            address _rewardToken = _rewardTokenList[i];

            uint256 _pendingRewardsByToken = _pendingRewards[i];

            if (_pendingRewardsByToken > 0) {
                unclaimedRewards[_rewardToken] -= _pendingRewardsByToken;
                IERC20(_rewardToken).safeTransfer(_to, _pendingRewardsByToken);

                emit Claim(msg.sender, currentEpochId, _rewardToken, _pendingRewardsByToken);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IPDTStakingV2
    function transferStakes(address _to, uint256 _amount) external nonReentrant {
        require(_to != address(0) || _to != msg.sender, "Invalid target wallet");
        require(_amount > 0, "Invalid stakes transfer amount");

        stakesByUser[msg.sender] -= _amount;
        stakesByUser[_to] += _amount;

        emit TransferStakes(msg.sender, _to, currentEpochId, _amount);
    }

    /// VIEW FUNCTIONS ///

    /**
     * @notice Returns current pending rewards of a specific reward token for next epoch
     * @param _rewardToken The address of reward token to get pending reward amount of
     * @return pendingRewards_ Current pending rewards of a specific reward token for next epoch
     */
    function pendingRewards(address _rewardToken) external view returns (uint256 pendingRewards_) {
        return IERC20(_rewardToken).balanceOf(address(this)) - unclaimedRewards[_rewardToken];
    }

    /**
     * @notice Returns total weight of contract at `_epochId`
     * @param _epochId Epoch to return total weight of contract for
     * @return contractWeight_ Weight of contract at the end of `_epochId`
     */
    function contractWeightAtEpoch(uint256 _epochId) public view returns (uint256 contractWeight_) {
        if (currentEpochId <= _epochId) revert InvalidEpoch();
        return epoch[_epochId].weightAtEnd;
    }

    /**
     * @notice Returns `_user`'s claimable amount of rewards for `_epochId`
     * @param _user Address to see `claimable_` for `_epochId`
     * @param _epochId Id of epoch wanting to get `claimable_` for
     * @param _rewardToken The address of reward token to get claimable amount of
     * @return claimable_ Amount claimable
     */
    function claimAmountForEpoch(
        address _user,
        uint256 _epochId,
        address _rewardToken
    ) external view returns (uint256 claimable_) {
        if (currentEpochId <= _epochId) revert InvalidEpoch();
        if (userClaimedEpoch[_user][_epochId] || contractWeightAtEpoch(_epochId) == 0) {
            return 0;
        }

        claimable_ =
            (totalRewardsToDistribute[_rewardToken][_epochId] *
                userWeightAtEpoch(_user, _epochId)) /
            contractWeightAtEpoch(_epochId);
    }

    /**
     * @notice Returns total weight of `_user` at `_epochId`
     * @param _user Address to calculate `userWeight_` of for `_epochId`
     * @param _epochId Epoch id to calculate weight of `_user`
     * @return userWeight_ Weight of `_user` for `_epochId`
     */
    function userWeightAtEpoch(
        address _user,
        uint256 _epochId
    ) public view returns (uint256 userWeight_) {
        if (currentEpochId <= _epochId) revert InvalidEpoch();
        uint256 _epochLeftOff = epochLeftOff[_user];
        uint256 amountStaked = stakesByUser[_user];

        if (_epochLeftOff > _epochId) {
            userWeight_ = _userWeightAtEpoch[_user][_epochId];
        } else {
            userWeight_ = amountStaked;
        }
    }

    /// INTERNAL FUNCTIONS ///

    /**
     * @notice Set epochs of `_user` that they left off on
     * @param _user Address of user being updated
     */
    function _setUserWeightAtEpoch(address _user) internal {
        uint256 _epochLeftOff = epochLeftOff[_user];

        if (_epochLeftOff != currentEpochId) {
            uint256 amountStaked = stakesByUser[_user];
            if (amountStaked > 0) {
                for (_epochLeftOff; _epochLeftOff < currentEpochId; ) {
                    _userWeightAtEpoch[_user][_epochLeftOff] = amountStaked;

                    unchecked {
                        ++_epochLeftOff;
                    }
                }
            }

            epochLeftOff[_user] = currentEpochId;
        }
    }
}
