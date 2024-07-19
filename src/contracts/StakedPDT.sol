// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

import {IStakedPDT} from "../interfaces/IStakedPDT.sol";

/**
 * @title StakedPDT contract
 * @dev Contract that allows PDT holders to claim rewards in blue-chip Web3 game tokens.
 *
 * @author Michael
 */
contract StakedPDT is ERC20, ReentrancyGuard, AccessControlEnumerable, IStakedPDT {
    using SafeERC20 for IERC20;

    ////////////////////////////////////////////////////////////////////////////////
    /// STATE VARIABLES
    ////////////////////////////////////////////////////////////////////////////////

    /// NEW ROLES

    bytes32 public constant EPOCH_MANAGER = keccak256("EPOCH_MANAGER");
    bytes32 public constant TOKEN_MANAGER = keccak256("TOKEN_MANAGER");

    /// Epoch Configuration

    /*
     * @notice Current epoch id
     */
    uint256 public currentEpochId;

    /*
     * @notice The duration of each epoch in seconds
     */
    uint256 public epochLength;

    /*
     * @notice The number of epochs in which rewards are claimable
     *
     * Initial value is 24 epochs, but this can be modified by admin.
     */
    uint256 public rewardsExpiryThreshold = 24;

    /*
     * @notice Epoch id to epoch details
     */
    mapping(uint256 => Epoch) public epoch;

    /// Staking Metrics

    /*
     * @notice The immutable address of PDT token utilized for staking
     */
    address public immutable pdt;

    /**
     * @notice Timestamp of lastest stake/unstake action on contract
     */
    uint256 public contractLastInteraction;

    /**
     * @notice Total weight of contract
     */
    uint256 internal _contractWeight;

    /**
     * @notice Mapping of contract addresses to their whitelisted status
     * @dev stPDT is not allowed to be transferred to non-whitelisted
     * addresses except for minting and burning cases.
     */
    mapping(address => bool) public whitelistedContracts;

    /// Reward Tokens

    /*
     * @notice Dynamic array to store reward token addresses
     */
    address[] public rewardTokenList;

    /*
     * @notice Reward token to its unclaimed amount
     */
    mapping(address => uint256) public unclaimedRewards;

    /*
     * @notice Maps each reward token to their respective rewards allocation for every epoch
     */
    mapping(address => mapping(uint256 => uint256)) public totalRewardsToDistribute;

    /*
     * @notice Maps each reward token to their respective claimed amount for every epoch
     */
    mapping(address => mapping(uint256 => uint256)) public totalRewardsClaimed;

    /// User Information

    /*
     * @notice Account to the claim reward status of certain epoch id
     */
    mapping(address => mapping(uint256 => bool)) public userClaimedEpoch;

    /*
     * @notice Account to its weight at a certain epoch
     */
    mapping(address => mapping(uint256 => uint256)) internal _userWeightAtEpoch;

    /*
     * @notice Account to the last interacted epoch id
     */
    mapping(address => uint256) public epochLeftOff;

    /*
     * @notice Account to the last claimed epoch id
     */
    mapping(address => uint256) public claimLeftOff;

    /**
     * @notice Mapping of accounts to their stake details
     */
    mapping(address => StakeDetails) public stakeDetails;

    ////////////////////////////////////////////////////////////////////////////////
    /// CONSTRUCTOR
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Constructs the contract.
     * @param name The name of receipt token
     * @param symbol The symbol of receipt token
     * @param initialEpochLength The duration of each epoch in seconds
     * @param firstEpochStartIn The duration of seconds the first epoch will starts in
     * @param pdtAddress The address of PDT token
     * @param initialOwner The address of initial owner
     */
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialEpochLength,
        uint256 firstEpochStartIn,
        address pdtAddress,
        address initialOwner
    ) ERC20(name, symbol) {
        require(initialEpochLength > 0, "Invalid initialEpochLength");
        require(firstEpochStartIn > 0, "Invalid firstEpochStartIn");
        require(pdtAddress != address(0), "Invalid PDT address");

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(EPOCH_MANAGER, initialOwner);
        _grantRole(TOKEN_MANAGER, initialOwner);

        epochLength = initialEpochLength;
        epoch[0].endTime = block.timestamp + firstEpochStartIn;
        epoch[0].startTime = block.timestamp;
        pdt = pdtAddress;
    }

    ////////////////////////////////////////////////////////////////////////////////
    /// OWNER FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Update epoch length
     * @param newEpochLength New epoch length in seconds
     *
     * Requirements:
     *
     * - Only EPOCH_MANAGER can update epoch length
     * - `newEpochLength` shouldn't be zero
     * - Updated epoch end time should be greater than `contractLastInteraction`
     *
     * Emits an {UpdateEpochLength} event.
     */
    function updateEpochLength(uint256 newEpochLength) external onlyRole(EPOCH_MANAGER) {
        uint256 newEndTime = epoch[currentEpochId].startTime + newEpochLength;
        require(
            newEpochLength > 0 && newEndTime > contractLastInteraction,
            "Invalid new epoch length"
        );

        uint256 previousEpochLength = epochLength;
        epochLength = newEpochLength;
        epoch[currentEpochId].endTime = newEndTime;

        emit UpdateEpochLength(currentEpochId, previousEpochLength, newEpochLength);
    }

    /**
     * @notice Update the number of epochs in which rewards are claimable
     * @param newRewardsExpiryThreshold The number of epochs in which rewards are claimable
     *
     * Requirements:
     *
     * - Only TOKEN_MANAGER can update rewards expiry threshold
     * - `newRewardsExpiryThreshold` shouldn't be zero
     *
     * Emits an {UpdateRewardDuration} event.
     */
    function updateRewardsExpiryThreshold(
        uint256 newRewardsExpiryThreshold
    ) external onlyRole(TOKEN_MANAGER) {
        if (newRewardsExpiryThreshold == 0) revert InvalidRewardsExpiryThreshold();

        rewardsExpiryThreshold = newRewardsExpiryThreshold;

        emit UpdateRewardDuration(newRewardsExpiryThreshold);
    }

    /**
     * @notice Register a new reward token
     * @param newRewardToken The address of reward token
     *
     * Requirements:
     *
     * - Only TOKEN_MANAGER can register new reward token
     * - `newRewardToken` shouldn't be a zero address
     * - `newRewardToken` shouldn't be already registered
     *
     * Emits a {RegisterNewRewardToken} event.
     */
    function registerNewRewardToken(address newRewardToken) external onlyRole(TOKEN_MANAGER) {
        require(newRewardToken != address(0) && newRewardToken != pdt, "Invalid reward token");

        uint256 numOfRewardTokens = rewardTokenList.length;

        for (uint256 itTokenIndex = 0; itTokenIndex < numOfRewardTokens; ) {
            if (rewardTokenList[itTokenIndex] == newRewardToken) {
                revert DuplicatedRewardToken(newRewardToken);
            }

            unchecked {
                ++itTokenIndex;
            }
        }

        // If newRewardToken is not found in rewardTokenList, then add it
        rewardTokenList.push(newRewardToken);

        emit RegisterNewRewardToken(currentEpochId, newRewardToken);
    }

    /**
     * @notice Unregister a reward token from reward token list
     * @param index Index of reward token address to remove
     *
     * Requirements:
     *
     * - Only TOKEN_MANAGER can unregister reward token
     *
     * Emits an {UnregisterRewardToken} event.
     */
    function unregisterRewardToken(uint256 index) external onlyRole(TOKEN_MANAGER) {
        require(index < rewardTokenList.length, "Index out of bounds");

        address rewardToken = rewardTokenList[index];
        rewardTokenList[index] = rewardTokenList[rewardTokenList.length - 1];
        rewardTokenList.pop();

        emit UnregisterRewardToken(currentEpochId, rewardToken);
    }

    /**
     * @notice Update epoch details if time
     *
     * Requirements:
     *
     * - Only EPOCH_MANAGER can end current epoch and start new one
     * - Reward pool for the next epoch shouldn't be empty
     * - Current epoch's end time should be already passed
     *
     * Emits a {Distribute} event.
     */
    function distribute() external onlyRole(EPOCH_MANAGER) {
        uint256 _currentEpochId = currentEpochId;
        Epoch memory _currentEpoch = epoch[_currentEpochId];

        if (block.timestamp >= _currentEpoch.endTime) {
            epoch[_currentEpochId].weightAtEnd = contractWeight();
            // Reset contract weight for new epoch
            _contractWeight = 0;

            ++_currentEpochId;
            currentEpochId = _currentEpochId;

            uint256 _nTokenTypes = rewardTokenList.length;
            uint256 _nTokenTypesForNextEpoch;

            for (uint256 itTokenIndex; itTokenIndex < _nTokenTypes; ) {
                address _token = rewardTokenList[itTokenIndex];
                uint256 _rewardBalance = IERC20(_token).balanceOf(address(this));
                uint256 _rewardsToDistribute = _rewardBalance - unclaimedRewards[_token];

                if (_rewardsToDistribute > 0) {
                    totalRewardsToDistribute[_token][_currentEpochId] = _rewardsToDistribute;
                    unclaimedRewards[_token] = _rewardBalance;
                    ++_nTokenTypesForNextEpoch;
                }

                unchecked {
                    ++itTokenIndex;
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
     * @notice Withdraw idle reward tokens. Idle reward amount
     * should be calculated from off-chain side.
     * @param rewardToken The address of the reward token
     * @param amount The amount of the reward tokens to withdraw
     *
     * Requirements:
     *
     * - Only TOKEN_MANAGER can withdraw reward tokens
     * - `rewardToken` should be already registered
     * - `amount` shouldn't be zero
     *
     * Emits a {WithdrawRewardToken} event.
     */
    function withdrawRewardTokens(
        address rewardToken,
        uint256 amount
    ) external onlyRole(TOKEN_MANAGER) {
        if (rewardToken == address(0)) {
            revert InvalidRewardToken();
        }
        if (amount == 0) {
            revert InvalidWithdrawAmount();
        }

        uint256 _tokenListSize = rewardTokenList.length;
        uint8 isRegistered = 0;

        for (uint256 itTokenIndex; itTokenIndex < _tokenListSize; ) {
            if (rewardTokenList[itTokenIndex] == rewardToken) {
                isRegistered = 1;
                break;
            }

            unchecked {
                ++itTokenIndex;
            }
        }

        if (isRegistered == 0) {
            revert InvalidRewardToken();
        }

        IERC20(rewardToken).safeTransfer(msg.sender, amount);

        emit WithdrawRewardToken(rewardToken, amount);
    }

    /**
     * @notice Whitelist contract addresses where stPDT tokens
     * can be transferred to.
     * @param value The contract address
     * @param shouldWhitelist Boolean if `value` should be whitelisted or not
     *
     * Requirements:
     *
     * - Only TOKEN_MANAGER can update contract whitelist
     */
    function updateWhitelistedContract(
        address value,
        bool shouldWhitelist
    ) external onlyRole(TOKEN_MANAGER) {
        whitelistedContracts[value] = shouldWhitelist;
    }

    ////////////////////////////////////////////////////////////////////////////////
    /// EXTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////

    /// @inheritdoc IStakedPDT
    function stake(address to, uint256 amount) external nonReentrant {
        Epoch memory _epoch = epoch[currentEpochId];

        if (block.timestamp > _epoch.endTime) {
            revert OutOfEpoch();
        }
        if (amount == 0) {
            revert InvalidStakeAmount();
        }

        _setUserWeightAtEpoch(to);
        _adjustContractWeight();

        StakeDetails memory _stake = stakeDetails[to];
        uint256 _amountStaked = balanceOf(to);

        if (_stake.lastInteraction > _epoch.startTime) {
            uint256 _additionalWeight = _weightIncreaseSinceInteraction(
                block.timestamp,
                _stake.lastInteraction,
                _amountStaked
            );
            _stake.weightAtLastInteraction += _additionalWeight;
        } else {
            _stake.weightAtLastInteraction = _weightIncreaseSinceInteraction(
                block.timestamp,
                _epoch.startTime,
                _amountStaked
            );
        }

        _stake.lastInteraction = block.timestamp;
        stakeDetails[to] = _stake;

        _mint(to, amount);
        IERC20(pdt).safeTransferFrom(msg.sender, address(this), amount);

        emit Stake(to, amount, currentEpochId);
    }

    /// @inheritdoc IStakedPDT
    function unstake(address to, uint256 amount) external nonReentrant {
        Epoch memory _epoch = epoch[currentEpochId];
        if (block.timestamp > _epoch.endTime) revert OutOfEpoch();

        uint256 _amountStaked = balanceOf(msg.sender);
        if (amount == 0 || amount > _amountStaked) revert InvalidUnstakeAmount();

        _setUserWeightAtEpoch(msg.sender);
        _adjustContractWeight();

        StakeDetails memory _stake = stakeDetails[msg.sender];

        if (_stake.lastInteraction > _epoch.startTime) {
            uint256 _additionalWeight = _weightIncreaseSinceInteraction(
                block.timestamp,
                _stake.lastInteraction,
                _amountStaked
            );
            _stake.weightAtLastInteraction += _additionalWeight;
        } else {
            _stake.weightAtLastInteraction = _weightIncreaseSinceInteraction(
                block.timestamp,
                _epoch.startTime,
                _amountStaked
            );
        }

        _stake.lastInteraction = block.timestamp;
        stakeDetails[msg.sender] = _stake;

        _burn(msg.sender, amount);
        IERC20(pdt).safeTransfer(to, amount);

        emit Unstake(msg.sender, amount, currentEpochId);
    }

    /// @inheritdoc IStakedPDT
    function claim(address to) external nonReentrant {
        _setUserWeightAtEpoch(msg.sender);

        uint256 _currentEpochId = currentEpochId;

        uint256 _claimLeftOff = claimLeftOff[msg.sender];
        if (_claimLeftOff == _currentEpochId || _currentEpochId == 1) revert ClaimedUpToEpoch();

        uint256 _rewardsExpiryThreshold = rewardsExpiryThreshold;
        uint256 _startActiveEpochId = _currentEpochId > _rewardsExpiryThreshold
            ? _currentEpochId - _rewardsExpiryThreshold
            : 1;

        uint256 _tokenListSize = rewardTokenList.length;
        uint256[] memory _pendingRewards = new uint256[](_tokenListSize);
        uint256[] memory _expiredRewards = new uint256[](_tokenListSize);

        for (uint256 itEpochId; itEpochId < _currentEpochId; ) {
            uint256 _contractWeightAtEpoch = contractWeightAtEpoch(itEpochId);

            if (!userClaimedEpoch[msg.sender][itEpochId] && _contractWeightAtEpoch > 0) {
                userClaimedEpoch[msg.sender][itEpochId] = true;

                uint256 _userWeight = _userWeightAtEpoch[msg.sender][itEpochId];

                if (_userWeight > 0) {
                    for (uint256 itTokenIdex; itTokenIdex < _tokenListSize; ) {
                        address _token = rewardTokenList[itTokenIdex];
                        uint256 _totalRewards = totalRewardsToDistribute[_token][itEpochId];
                        uint256 _totalRewardsClaimed = totalRewardsClaimed[_token][itEpochId];
                        uint256 _epochRewards = (_totalRewards * _userWeight) /
                            _contractWeightAtEpoch;

                        if (_totalRewardsClaimed + _epochRewards > _totalRewards) {
                            _epochRewards = _totalRewards - _totalRewardsClaimed;
                        }

                        if (_startActiveEpochId > itEpochId) {
                            unchecked {
                                _expiredRewards[itTokenIdex] += _epochRewards;
                            }
                        } else {
                            unchecked {
                                _pendingRewards[itTokenIdex] += _epochRewards;
                                totalRewardsClaimed[_token][itEpochId] += _epochRewards;
                            }
                        }

                        unchecked {
                            ++itTokenIdex;
                        }
                    }
                }
            }

            unchecked {
                ++itEpochId;
            }
        }

        claimLeftOff[msg.sender] = _currentEpochId;

        for (uint256 itTokenIndex; itTokenIndex < _tokenListSize; ) {
            address _token = rewardTokenList[itTokenIndex];
            uint256 _pendingRewardsByToken = _pendingRewards[itTokenIndex];

            if (_pendingRewardsByToken > 0) {
                unclaimedRewards[_token] =
                    unclaimedRewards[_token] -
                    _pendingRewardsByToken -
                    _expiredRewards[itTokenIndex];
                IERC20(_token).safeTransfer(to, _pendingRewardsByToken);

                emit Claim(msg.sender, _currentEpochId, _token, _pendingRewardsByToken);
                emit RewardsExpired(
                    msg.sender,
                    _currentEpochId,
                    _token,
                    _expiredRewards[itTokenIndex]
                );
            }

            unchecked {
                ++itTokenIndex;
            }
        }
    }

    ////////////////////////////////////////////////////////////////////////////////
    /// VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Returns current pending rewards of a specific reward token for next epoch
     * @param rewardToken The address of reward token to get pending reward amount of
     * @return pendingRewards_ Current pending rewards of a specific reward token for next epoch
     */
    function pendingRewards(address rewardToken) external view returns (uint256 pendingRewards_) {
        return IERC20(rewardToken).balanceOf(address(this)) - unclaimedRewards[rewardToken];
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
        uint256 _contractWeightAtEpoch = contractWeightAtEpoch(epochId);
        uint256 _totalRewards = totalRewardsToDistribute[rewardToken][epochId];

        if (_hasClaimed || _contractWeightAtEpoch == 0 || _userWeight == 0 || _totalRewards == 0) {
            return 0;
        }

        claimable_ = (_totalRewards * _userWeight) / _contractWeightAtEpoch;
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
        require(epochId < currentEpochId, "Invalid epoch id");

        uint256 _epochLeftOff = epochLeftOff[user];
        uint256 _amountStaked = balanceOf(user);

        if (_epochLeftOff > epochId) {
            userWeight_ = _userWeightAtEpoch[user][epochId];
        } else {
            Epoch memory _epoch = epoch[epochId];
            StakeDetails memory _stake = stakeDetails[user];
            if (_stake.lastInteraction > _epoch.startTime) {
                userWeight_ =
                    _stake.weightAtLastInteraction +
                    _weightIncreaseSinceInteraction(
                        _epoch.endTime,
                        _stake.lastInteraction,
                        _amountStaked
                    );
            } else {
                userWeight_ = _weightIncreaseSinceInteraction(
                    _epoch.endTime,
                    _epoch.startTime,
                    _amountStaked
                );
            }
        }
    }

    /**
     * @notice Returns total weight of `user`
     * @param user Address to calculate `userWeight_` of
     * @return userWeight_  Weight of `user`
     */
    function userTotalWeight(address user) public view returns (uint256 userWeight_) {
        Epoch memory _epoch = epoch[currentEpochId];
        StakeDetails memory _stake = stakeDetails[user];
        uint256 _balance = balanceOf(user);

        if (_stake.lastInteraction > _epoch.startTime) {
            uint256 _additionalWeight = _weightIncreaseSinceInteraction(
                Math.min(block.timestamp, _epoch.endTime),
                _stake.lastInteraction,
                _balance
            );
            userWeight_ = _additionalWeight + _stake.weightAtLastInteraction;
        } else {
            userWeight_ = _weightIncreaseSinceInteraction(
                Math.min(block.timestamp, _epoch.endTime),
                _epoch.startTime,
                _balance
            );
        }
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
     * @notice Returns current total weight of contract
     * @return contractWeight_ Total current weight of contract
     */
    function contractWeight() public view returns (uint256 contractWeight_) {
        Epoch memory _epoch = epoch[currentEpochId];
        uint256 _weightIncrease = _weightIncreaseSinceInteraction(
            Math.min(block.timestamp, _epoch.endTime),
            Math.max(contractLastInteraction, _epoch.startTime),
            totalSupply()
        );
        contractWeight_ = _weightIncrease + _contractWeight;
    }

    ////////////////////////////////////////////////////////////////////////////////
    /// INTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Returns additional weight since `lastInteraction` at `timestamp`
     * @param timestamp Timestamp calculating on
     * @param lastInteraction Last interaction time
     * @param baseAmount Base amount of PDT to account for
     * @return additionalWeight_  Additional weight since `lastinteraction` at `timestamp`
     */
    function _weightIncreaseSinceInteraction(
        uint256 timestamp,
        uint256 lastInteraction,
        uint256 baseAmount
    ) internal pure returns (uint256 additionalWeight_) {
        uint256 _timePassed = timestamp - lastInteraction;
        uint256 _multiplierReceived = (1e18 * _timePassed) / 1 days;
        additionalWeight_ = (baseAmount * _multiplierReceived) / 1e18;
    }

    /**
     * @notice Adjust contract weight since last interaction
     */
    function _adjustContractWeight() internal {
        _contractWeight = contractWeight();
        contractLastInteraction = block.timestamp;
    }

    /**
     * @notice Set user weights of past epochs after they left off
     * @param user Address of user being updated
     */
    function _setUserWeightAtEpoch(address user) internal {
        uint256 _epochLeftOff = epochLeftOff[user];
        uint256 _currentEpochId = currentEpochId;

        if (_epochLeftOff != _currentEpochId) {
            uint256 _amountStaked = balanceOf(user);
            if (_amountStaked > 0) {
                StakeDetails memory _stake = stakeDetails[user];

                for (_epochLeftOff; _epochLeftOff < _currentEpochId; ) {
                    Epoch memory _epoch = epoch[_epochLeftOff];

                    if (_stake.lastInteraction > _epoch.startTime) {
                        uint256 _additionalWeight = _weightIncreaseSinceInteraction(
                            _epoch.endTime,
                            _stake.lastInteraction,
                            _amountStaked
                        );

                        _userWeightAtEpoch[user][_epochLeftOff] =
                            _stake.weightAtLastInteraction +
                            _additionalWeight;
                    } else {
                        _userWeightAtEpoch[user][_epochLeftOff] = _weightIncreaseSinceInteraction(
                            _epoch.endTime,
                            _epoch.startTime,
                            _amountStaked
                        );
                    }

                    unchecked {
                        ++_epochLeftOff;
                    }
                }
            }

            epochLeftOff[user] = _currentEpochId;
        }
    }

    ////////////////////////////////////////////////////////////////////////////////
    /// ERC20 OVERRIDEN FUNCTIONS
    ////////////////////////////////////////////////////////////////////////////////

    function transfer(address to, uint256 value) public override returns (bool) {
        if (!whitelistedContracts[to]) revert InvalidStakesTransfer();

        super._transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (!whitelistedContracts[to]) revert InvalidStakesTransfer();

        super._spendAllowance(from, msg.sender, value);
        super._transfer(msg.sender, to, value);
        return true;
    }
}
