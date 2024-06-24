// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import {IPDTStakingV2} from "../interfaces/IPDTStakingV2.sol";

/**
 * @title PDT Staking v2
 * @notice Contract that allows users to stake PDT
 * @author Michael
 */
contract PDTStakingV2 is IPDTStakingV2, ReentrancyGuard, AccessControlEnumerable {
    using SafeERC20 for IERC20;

    /// NEW ROLES ///

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

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
     * @param initialEpochLength The duration of each epoch in seconds
     * @param firstEpochStartIn The duration of seconds the first epoch will starts in
     * @param pdtAddress The address of PDT token
     * @param initialOwner The address of initial owner
     */
    constructor(
        uint256 initialEpochLength,
        uint256 firstEpochStartIn,
        address pdtAddress,
        address initialOwner
    ) {
        require(initialEpochLength > 0, "Invalid initialEpochLength");
        require(firstEpochStartIn > 0, "Invalid firstEpochStartIn");
        require(pdtAddress != address(0), "Invalid PDT address");

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(MANAGER_ROLE, initialOwner);

        epochLength = initialEpochLength;
        epoch[0].endTime = block.timestamp + firstEpochStartIn;
        epoch[0].startTime = block.timestamp;
        pdt = pdtAddress;
    }

    /// OWNER FUNCTIONS ///

    /**
     * @notice Update epoch length
     * @param newEpochLength New epoch length in seconds
     *
     * Requirements:
     *
     * - msg.sender should has DEFAULT_ADMIN_ROLE role
     * - `newEpochLength` shouldn't be zero
     *
     * Emits an {UpdateEpochLength} event.
     */
    function updateEpochLength(uint256 newEpochLength) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newEpochLength > 0, "Invalid new epoch length");

        uint256 previousEpochLength = epochLength;
        epochLength = newEpochLength;

        epoch[currentEpochId].endTime = epoch[currentEpochId].startTime + newEpochLength;

        emit UpdateEpochLength(currentEpochId, previousEpochLength, newEpochLength);
    }

    /**
     * @notice Update reward duration
     * @param newRewardDuration The time-to-live duration for rewards in seconds
     *
     * Requirements:
     *
     * - msg.sender should has DEFAULT_ADMIN_ROLE role
     * - `newRewardDuration` should be longer than the current epoch length
     *
     * Emits an {UpdateRewardDuration} event.
     */
    function updateRewardDuration(uint256 newRewardDuration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRewardDuration > epochLength, "Invalid reward duration");

        rewardDuration = newRewardDuration;

        emit UpdateRewardDuration(newRewardDuration);
    }

    /**
     * @notice Register a new reward token
     * @param newRewardToken The address of reward token
     *
     * Requirements:
     *
     * - msg.sender should has MANAGER_ROLE role
     * - `newRewardToken` shouldn't be a zero address
     * - `newRewardToken` shouldn't be already registered
     *
     * Emits a {RegisterNewRewardToken} event.
     */
    function registerNewRewardToken(address newRewardToken) external onlyRole(MANAGER_ROLE) {
        require(newRewardToken != address(0), "Invalid reward token");

        uint256 numOfRewardTokens = rewardTokenList.length;

        for (uint256 i = 0; i < numOfRewardTokens; ) {
            if (rewardTokenList[i] == newRewardToken) {
                revert DuplicatedRewardToken(newRewardToken);
            }

            unchecked {
                ++i;
            }
        }

        // If newRewardToken is not found in rewardTokenList, then add it
        rewardTokenList.push(newRewardToken);

        emit RegisterNewRewardToken(currentEpochId, newRewardToken);
    }

    /**
     * @notice Update epoch details if time
     *
     * Requirements:
     *
     * - msg.sender should has MANAGER_ROLE role
     * - reward pool for the next epoch shouldn't be empty
     * - current epoch should be already ended
     *
     * Emits a {Distribute} event.
     */
    function distribute() external onlyRole(MANAGER_ROLE) {
        uint256 _currentEpochId = currentEpochId;
        Epoch memory _currentEpoch = epoch[_currentEpochId];

        if (block.timestamp >= _currentEpoch.endTime) {
            epoch[_currentEpochId].weightAtEnd = totalStaked;
            ++_currentEpochId;
            currentEpochId = _currentEpochId;

            uint256 _nTokenTypes = rewardTokenList.length;
            uint256 _nTokenTypesForNextEpoch;
            address[] memory _tokenList = rewardTokenList;

            for (uint256 i; i < _nTokenTypes; ) {
                address _token = _tokenList[i];
                uint256 _rewardBalance = IERC20(_token).balanceOf(address(this));
                uint256 _rewardsToDistribute = _rewardBalance - unclaimedRewards[_token];

                if (_rewardsToDistribute > 0) {
                    totalRewardsToDistribute[_token][_currentEpochId] = _rewardsToDistribute;
                    unclaimedRewards[_token] = _rewardBalance;
                    ++_nTokenTypesForNextEpoch;
                }

                unchecked {
                    ++i;
                }
            }

            if (_nTokenTypesForNextEpoch == 0) {
                revert EmptyRewardPool(_currentEpochId);
            }

            _currentEpoch.startTime = block.timestamp;
            _currentEpoch.endTime = block.timestamp + epochLength;

            epoch[_currentEpochId] = _currentEpoch;

            emit Distribute(_currentEpochId);
        }
    }

    /**
     * @notice Owner can withdraw idle reward tokens. Idle reward amount
     * should be calculated from off-chain side.
     * @param rewardToken The address of the reward token
     * @param amount The amount of the reward tokens to withdraw
     *
     * Requirements:
     *
     * - msg.sender should has DEFAULT_ADMIN_ROLE role
     * - `rewardToken` should be already registered
     * - `amount` shouldn't be zero
     *
     * Emits a {WithdrawRewardToken} event.
     */
    function withdrawRewardTokens(
        address rewardToken,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (rewardToken == address(0)) {
            revert InvalidRewardToken();
        }
        if (amount == 0) {
            revert InvalidWithdrawAmount();
        }

        address[] memory _tokenList = rewardTokenList;
        uint256 _tokenListSize = _tokenList.length;
        uint8 isRegistered = 0;

        for (uint256 i; i < _tokenListSize; ) {
            if (_tokenList[i] == rewardToken) {
                isRegistered = 1;
                break;
            }

            unchecked {
                ++i;
            }
        }

        if (isRegistered == 0) {
            revert InvalidRewardToken();
        }

        IERC20(rewardToken).safeTransfer(msg.sender, amount);

        emit WithdrawRewardToken(rewardToken, amount);
    }

    /// EXTERNAL FUNCTIONS ///

    /// @inheritdoc IPDTStakingV2
    function stake(address to, uint256 amount) external nonReentrant {
        if (block.timestamp > epoch[currentEpochId].endTime) {
            revert OutOfEpoch();
        }
        if (amount == 0) {
            revert InvalidStakeAmount();
        }

        _setUserWeightAtEpoch(to);

        totalStaked += amount;
        stakesByUser[to] += amount;

        IERC20(pdt).safeTransferFrom(msg.sender, address(this), amount);

        emit Stake(to, amount, currentEpochId);
    }

    /// @inheritdoc IPDTStakingV2
    function unstake(address to, uint256 amount) external nonReentrant {
        if (block.timestamp > epoch[currentEpochId].endTime) {
            revert OutOfEpoch();
        }

        uint256 _amountStaked = stakesByUser[to];
        if (amount == 0 || amount > _amountStaked) {
            revert InvalidUnstakeAmount(_amountStaked, amount);
        }

        _setUserWeightAtEpoch(msg.sender);

        totalStaked -= amount;
        stakesByUser[to] -= amount;

        IERC20(pdt).safeTransfer(to, amount);

        emit Unstake(msg.sender, amount, currentEpochId);
    }

    /// @inheritdoc IPDTStakingV2
    function claim(address to) external nonReentrant {
        _setUserWeightAtEpoch(msg.sender);

        uint256 _claimLeftOff = claimLeftOff[msg.sender];
        uint256 _bottomEpochId = rewardsActiveFrom();
        uint256 _currentEpochId = currentEpochId;

        if (_claimLeftOff == _currentEpochId) revert ClaimedUpToEpoch();

        address[] memory _tokenList = rewardTokenList;
        uint256 _tokenListSize = _tokenList.length;
        uint256[] memory _pendingRewards = new uint256[](_tokenListSize);
        uint256[] memory _expiredRewards = new uint256[](_tokenListSize);

        for (_claimLeftOff; _claimLeftOff < _currentEpochId; ) {
            uint256 _contractWeight = contractWeightAtEpoch(_claimLeftOff);

            if (!userClaimedEpoch[msg.sender][_claimLeftOff] && _contractWeight > 0) {
                userClaimedEpoch[msg.sender][_claimLeftOff] = true;

                uint256 _userWeight = _userWeightAtEpoch[msg.sender][_claimLeftOff];

                if (_userWeight > 0) {
                    for (uint256 i; i < _tokenListSize; ) {
                        address _token = _tokenList[i];
                        uint256 _totalRewards = totalRewardsToDistribute[_token][_claimLeftOff];
                        uint256 _totalRewardsClaimed = totalRewardsClaimed[_token][_claimLeftOff];

                        if (_totalRewards > 0) {
                            uint256 _epochRewards = (_totalRewards * _userWeight) / _contractWeight;
                            if (_totalRewardsClaimed + _epochRewards > _totalRewards) {
                                _epochRewards = _totalRewards - _totalRewardsClaimed;
                            }

                            if (_bottomEpochId > _claimLeftOff) {
                                _expiredRewards[i] += _epochRewards;
                            } else {
                                _pendingRewards[i] += _epochRewards;
                                totalRewardsClaimed[_token][_claimLeftOff] += _epochRewards;
                            }
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

        claimLeftOff[msg.sender] = _currentEpochId;

        for (uint256 i; i < _tokenListSize; ) {
            address _token = _tokenList[i];
            uint256 _pendingRewardsByToken = _pendingRewards[i];

            if (_pendingRewardsByToken > 0) {
                unclaimedRewards[_token] =
                    unclaimedRewards[_token] -
                    _pendingRewardsByToken -
                    _expiredRewards[i];
                IERC20(_token).safeTransfer(to, _pendingRewardsByToken);

                emit Claim(msg.sender, _currentEpochId, _token, _pendingRewardsByToken);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IPDTStakingV2
    function transferStakes(address to, uint256 amount) external nonReentrant {
        if (to == address(0) || to == msg.sender || amount == 0) {
            revert InvalidStakesTransfer();
        }

        _setUserWeightAtEpoch(msg.sender);

        stakesByUser[msg.sender] -= amount;
        stakesByUser[to] += amount;

        emit TransferStakes(msg.sender, to, currentEpochId, amount);
    }

    /// VIEW FUNCTIONS ///

    /**
     * @notice Returns current pending rewards of a specific reward token for next epoch
     * @param rewardToken The address of reward token to get pending reward amount of
     * @return pendingRewards_ Current pending rewards of a specific reward token for next epoch
     */
    function pendingRewards(address rewardToken) external view returns (uint256 pendingRewards_) {
        return IERC20(rewardToken).balanceOf(address(this)) - unclaimedRewards[rewardToken];
    }

    /**
     * @notice Returns total weight of contract at `epochId`
     * @param epochId Epoch to return total weight of contract for
     * @return contractWeight_ Weight of contract at the end of `epochId`
     */
    function contractWeightAtEpoch(uint256 epochId) public view returns (uint256 contractWeight_) {
        contractWeight_ = epoch[epochId].weightAtEnd;
    }

    /**
     * @notice Returns `user`'s claimable amount of rewards for `epochId`
     * @param user Address to see `claimable_` for `epochId`
     * @param epochId Id of epoch wanting to get `claimable_` for
     * @param rewardToken The address of reward token to get claimable amount of
     * @return claimable_ Amount claimable
     */
    function claimAmountForEpoch(
        address user,
        uint256 epochId,
        address rewardToken
    ) external view returns (uint256 claimable_) {
        bool _hasClaimed = userClaimedEpoch[user][epochId];
        uint256 _userWeight = userWeightAtEpoch(user, epochId);
        uint256 _contractWeight = contractWeightAtEpoch(epochId);
        uint256 _totalRewards = totalRewardsToDistribute[rewardToken][epochId];

        if (_hasClaimed || _contractWeight == 0 || _userWeight == 0 || _totalRewards == 0) {
            return 0;
        }

        claimable_ = (_totalRewards * _userWeight) / _contractWeight;
    }

    /**
     * @notice Returns total weight of `user` at epoch `epochId`
     * @param user Address to calculate `userWeight_` of for epoch `epochId`
     * @param epochId Epoch id to calculate weight of `user`
     * @return userWeight_ Weight of `user` for epoch `epochId`
     */
    function userWeightAtEpoch(
        address user,
        uint256 epochId
    ) public view returns (uint256 userWeight_) {
        uint256 _epochLeftOff = epochLeftOff[user];
        uint256 _amountStaked = stakesByUser[user];

        if (_epochLeftOff > epochId) {
            userWeight_ = _userWeightAtEpoch[user][epochId];
        } else {
            userWeight_ = _amountStaked;
        }
    }

    /**
     * @notice Returns epoch id from which rewards are active
     */
    function rewardsActiveFrom() public view returns (uint256 bottomEpochId_) {
        uint256 _currentEpochId = currentEpochId;
        uint256 _rewardDuration = rewardDuration;
        uint256 _end = epoch[_currentEpochId].startTime;

        for (uint256 i = _currentEpochId; i > 0; ) {
            uint256 _start = epoch[i - 1].startTime;

            if (_end - _start > _rewardDuration) {
                bottomEpochId_ = i;
                break;
            }

            unchecked {
                --i;
            }
        }
    }

    /// INTERNAL FUNCTIONS ///

    /**
     * @notice Set epochs of `user` that they left off on
     * @param user Address of user being updated
     */
    function _setUserWeightAtEpoch(address user) internal {
        uint256 _epochLeftOff = epochLeftOff[user];
        uint256 _currentEpochId = currentEpochId;

        if (_epochLeftOff != _currentEpochId) {
            uint256 _amountStaked = stakesByUser[user];
            if (_amountStaked > 0) {
                for (_epochLeftOff; _epochLeftOff < _currentEpochId; ) {
                    _userWeightAtEpoch[user][_epochLeftOff] = _amountStaked;

                    unchecked {
                        ++_epochLeftOff;
                    }
                }
            }

            epochLeftOff[user] = _currentEpochId;
        }
    }
}
