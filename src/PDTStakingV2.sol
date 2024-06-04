// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IPDTStakingV2} from "./interfaces/IPDTStakingV2.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

/**
 * @title PDT Staking v2
 * @notice Contract that allows users to stake PDT
 * @author Michael
 */
contract PDTStakingV2 is IPDTStakingV2, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /// STATE VARIABLES ///

    /// @notice The duration to double weight in seconds
    uint256 public immutable timeToDouble;
    /// @notice Current epoch id
    uint256 public epochId;
    /// @notice The duration of each epoch in seconds
    uint256 public epochLength;
    /// @notice The time of last interaction with contract in seconds
    uint256 public lastInteraction;
    /// @notice Total amount of staked PDT
    uint256 public totalStaked;

    /// @notice Total weight of contract
    uint256 internal _contractWeight;
    /// @notice The amount of unclaimed rewards
    uint256 public unclaimedRewards;

    /// @notice Current epoch
    Epoch public currentEpoch;

    /// @notice The address of PDT
    address public immutable pdt;
    /// @notice The address of prime
    address public immutable prime;

    /// @notice Account to the claim reward status of certain epoch id
    mapping(address => mapping(uint256 => bool)) public userClaimedEpoch;
    /// @notice Account to its weight at a certain epoch
    mapping(address => mapping(uint256 => uint256)) internal _userWeightAtEpoch;
    /// @notice Account to the last interacted epoch id
    mapping(address => uint256) public epochLeftOff;
    /// @notice Account to the last claimed epoch id
    mapping(address => uint256) public claimLeftOff;
    /// @notice Epoch id to epoch details
    mapping(uint256 => Epoch) public epoch;
    /// @notice Account to Stake details
    mapping(address => Stake) public stakeDetails;

    /// CONSTRUCTOR ///

    /**
     * @param _timeToDouble The duration to double weight in seconds
     * @param _epochLength The duration of each epoch in seconds
     * @param _firstEpochStartIn The duration of seconds the first epoch will starts in
     * @param _pdt The address of PDT token
     * @param _prime The address of reward token
     * @param _initialOwner The address of initial owner
     */
    constructor(
        uint256 _timeToDouble,
        uint256 _epochLength,
        uint256 _firstEpochStartIn,
        address _pdt,
        address _prime,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_timeToDouble > 0, "Zero timeToDouble");
        require(_epochLength > 0, "Zero epochLength");
        require(_firstEpochStartIn > 0, "Zero firstEpochStartIn");
        require(_pdt != address(0), "Zero Address: PDT");
        require(_prime != address(0), "Zero Address: PRIME");

        timeToDouble = _timeToDouble;
        epochLength = _epochLength;
        currentEpoch.endTime = block.timestamp + _firstEpochStartIn;
        epoch[0].endTime = block.timestamp + _firstEpochStartIn;
        currentEpoch.startTime = block.timestamp;
        epoch[0].startTime = block.timestamp;
        pdt = _pdt;
        prime = _prime;
    }

    /// OWNER FUNCTION ///

    /**
     * @notice Push back epoch 0, used in case PRIME can not be transferred at current end time
     * @param _timeToPushBack The amount of seconds to push epoch 0 back
     */
    function pushBackEpoch0(uint256 _timeToPushBack) external onlyOwner {
        if (epochId != 0) revert AfterEpoch0();

        currentEpoch.endTime += _timeToPushBack;
        epoch[0].endTime += _timeToPushBack;

        emit Epoch0PushedBack(currentEpoch.endTime);
    }

    /**
     * @notice Update epoch length
     * @param _epochLength New epoch length in seconds
     */
    function updateEpochLength(uint256 _epochLength) external onlyOwner {
        uint256 previousEpochLength_ = epochLength;
        epochLength = _epochLength;

        emit EpochLengthUpdated(previousEpochLength_, _epochLength);
    }

    /// PUBLIC FUNCTIONS ///

    /**
     * @notice Update epoch details if time
     */
    function distribute() external nonReentrant {
        _distribute();
    }

    /**
     * @notice Stake PDT
     * @param _to Address that will receive credit for stake
     * @param _amount Amount of PDT to stake
     */
    function stake(address _to, uint256 _amount) external nonReentrant {
        require(_amount > 0, "Invalid zero stake");

        IERC20(pdt).safeTransferFrom(msg.sender, address(this), _amount);

        _distribute();
        _setUserWeightAtEpoch(_to);
        _adjustContractWeight(true, _amount);

        totalStaked += _amount;

        Stake memory _stake = stakeDetails[_to];

        if (_stake.amountStaked > 0) {
            uint256 _additionalWeight = _weightIncreaseSinceInteraction(
                block.timestamp,
                _stake.lastInteraction,
                _stake.amountStaked
            );
            _stake.weightAtLastInteraction += (_additionalWeight + _amount);
        } else {
            _stake.weightAtLastInteraction = _amount;
        }

        _stake.amountStaked += _amount;
        _stake.lastInteraction = block.timestamp;

        stakeDetails[_to] = _stake;

        emit Staked(_to, _stake.amountStaked, _stake.weightAtLastInteraction);
    }

    /**
     * @notice Unstake PDT
     * @param _to Address that will receive PDT unstaked
     */
    function unstake(address _to) external nonReentrant {
        Stake memory _stake = stakeDetails[msg.sender];

        uint256 _stakedAmount = _stake.amountStaked;

        if (_stakedAmount == 0) revert NothingStaked();

        _distribute();
        _setUserWeightAtEpoch(msg.sender);
        _adjustContractWeight(false, _stakedAmount);

        totalStaked -= _stakedAmount;

        _stake.amountStaked = 0;
        _stake.lastInteraction = block.timestamp;
        _stake.weightAtLastInteraction = 0;

        stakeDetails[msg.sender] = _stake;

        IERC20(pdt).safeTransfer(_to, _stakedAmount);

        emit Unstaked(msg.sender, _stakedAmount);
    }

    /**
     * @notice Claims all pending rewards tokens for msg.sender
     * @param _to Address to send rewards to
     */
    function claim(address _to) external nonReentrant {
        _setUserWeightAtEpoch(msg.sender);

        uint256 _pendingRewards;
        uint256 _claimLeftOff = claimLeftOff[msg.sender];

        if (_claimLeftOff == epochId) revert ClaimedUpToEpoch();

        for (_claimLeftOff; _claimLeftOff < epochId; ++_claimLeftOff) {
            if (
                !userClaimedEpoch[msg.sender][_claimLeftOff] &&
                contractWeightAtEpoch(_claimLeftOff) > 0
            ) {
                userClaimedEpoch[msg.sender][_claimLeftOff] = true;
                Epoch memory _epoch = epoch[_claimLeftOff];
                uint256 _weightAtEpoch = _userWeightAtEpoch[msg.sender][
                    _claimLeftOff
                ];

                uint256 _epochRewards = (_epoch.totalToDistribute *
                    _weightAtEpoch) / contractWeightAtEpoch(_claimLeftOff);
                if (
                    _epoch.totalClaimed + _epochRewards >
                    _epoch.totalToDistribute
                ) {
                    _epochRewards =
                        _epoch.totalToDistribute -
                        _epoch.totalClaimed;
                }

                _pendingRewards += _epochRewards;
                epoch[_claimLeftOff].totalClaimed += _epochRewards;
            }
        }

        claimLeftOff[msg.sender] = epochId;
        unclaimedRewards -= _pendingRewards;
        IERC20(prime).safeTransfer(_to, _pendingRewards);
    }

    /// VIEW FUNCTIONS ///

    /**
     * @notice Returns current pending rewards for next epoch
     * @return pendingRewards_ Current pending rewards for next epoch
     */
    function pendingRewards() external view returns (uint256 pendingRewards_) {
        return IERC20(prime).balanceOf(address(this)) - unclaimedRewards;
    }

    /**
     * @notice Returns total weight `_user` has currently
     * @param _user Address to calculate `userWeight_` of
     * @return userWeight_ Weight of `_user`
     */
    function userTotalWeight(
        address _user
    ) public view returns (uint256 userWeight_) {
        Stake memory _stake = stakeDetails[_user];
        uint256 _additionalWeight = _weightIncreaseSinceInteraction(
            block.timestamp,
            _stake.lastInteraction,
            _stake.amountStaked
        );
        userWeight_ = _additionalWeight + _stake.weightAtLastInteraction;
    }

    /**
     * @notice Returns total weight of contract at `_epochId`
     * @param _epochId Epoch to return total weight of contract for
     * @return contractWeight_ Weight of contract at end of `_epochId`
     */
    function contractWeightAtEpoch(
        uint256 _epochId
    ) public view returns (uint256 contractWeight_) {
        if (epochId <= _epochId) revert InvalidEpoch();
        return epoch[_epochId].weightAtEnd;
    }

    /**
     * @notice Returns amount `_user` has claimable for `_epochId`
     * @param _user Address to see `claimable_` for `_epochId`
     * @param _epochId Id of epoch wanting to get `claimable_` for
     * @return claimable_ Amount claimable
     */
    function claimAmountForEpoch(
        address _user,
        uint256 _epochId
    ) external view returns (uint256 claimable_) {
        if (epochId <= _epochId) revert InvalidEpoch();
        if (
            userClaimedEpoch[_user][_epochId] ||
            contractWeightAtEpoch(_epochId) == 0
        ) return 0;

        Epoch memory _epoch = epoch[_epochId];

        claimable_ =
            (_epoch.totalToDistribute * userWeightAtEpoch(_user, _epochId)) /
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
        if (epochId <= _epochId) revert InvalidEpoch();
        uint256 _epochLeftOff = epochLeftOff[_user];
        Stake memory _stake = stakeDetails[_user];

        if (_epochLeftOff > _epochId)
            userWeight_ = _userWeightAtEpoch[_user][_epochId];
        else {
            Epoch memory _epoch = epoch[_epochId];
            if (_stake.amountStaked > 0) {
                uint256 _additionalWeight = _weightIncreaseSinceInteraction(
                    _epoch.endTime,
                    _stake.lastInteraction,
                    _stake.amountStaked
                );
                userWeight_ =
                    _additionalWeight +
                    _stake.weightAtLastInteraction;
            }
        }
    }

    /**
     * @notice Returns current total weight of contract
     * @return contractWeight_ Total current weight of contract
     */
    function contractWeight() external view returns (uint256 contractWeight_) {
        uint256 _weightIncrease = _weightIncreaseSinceInteraction(
            block.timestamp,
            lastInteraction,
            totalStaked
        );
        contractWeight_ = _weightIncrease + _contractWeight;
    }

    /// INTERNAL VIEW FUNCTION ///

    /**
     * @notice Returns additional weight since `_lastInteraction` at `_timestamp`
     * @param _timestamp Timestamp calculating on
     * @param _lastInteraction Last interaction time
     * @param _baseAmount Base amount of PDT to account for
     * @return additionalWeight_ Additional weight since `_lastinteraction` at `_timestamp`
     */
    function _weightIncreaseSinceInteraction(
        uint256 _timestamp,
        uint256 _lastInteraction,
        uint256 _baseAmount
    ) internal view returns (uint256 additionalWeight_) {
        uint256 _timePassed = _timestamp - _lastInteraction;
        uint256 _multiplierReceived = (1e18 * _timePassed) / timeToDouble;
        additionalWeight_ = (_baseAmount * _multiplierReceived) / 1e18;
    }

    /// INTERNAL FUNCTIONS ///

    /**
     * @notice Adjust contract weight since last interaction
     * @param _stake Bool if `_amount` is being staked or withdrawn
     * @param _amount Amount of PDT being staked or withdrawn
     */
    function _adjustContractWeight(bool _stake, uint256 _amount) internal {
        uint256 _weightReceivedSinceInteraction = _weightIncreaseSinceInteraction(
                block.timestamp,
                lastInteraction,
                totalStaked
            );
        _contractWeight += _weightReceivedSinceInteraction;

        if (_stake) {
            _contractWeight += _amount;
        } else {
            if (userTotalWeight(msg.sender) > _contractWeight)
                _contractWeight = 0;
            else _contractWeight -= userTotalWeight(msg.sender);
        }

        lastInteraction = block.timestamp;
    }

    /**
     * @notice Set epochs of `_user` that they left off on
     * @param _user Address of user being updated
     */
    function _setUserWeightAtEpoch(address _user) internal {
        uint256 _epochLeftOff = epochLeftOff[_user];

        if (_epochLeftOff != epochId) {
            Stake memory _stake = stakeDetails[_user];
            if (_stake.amountStaked > 0) {
                for (_epochLeftOff; _epochLeftOff < epochId; ++_epochLeftOff) {
                    Epoch memory _epoch = epoch[_epochLeftOff];
                    uint256 _additionalWeight = _weightIncreaseSinceInteraction(
                        _epoch.endTime,
                        _stake.lastInteraction,
                        _stake.amountStaked
                    );
                    _userWeightAtEpoch[_user][_epochLeftOff] =
                        _additionalWeight +
                        _stake.weightAtLastInteraction;
                }
            }

            epochLeftOff[_user] = epochId;
        }
    }

    /**
     * @notice Update epoch details if time
     */
    function _distribute() internal {
        if (block.timestamp >= currentEpoch.endTime) {
            uint256 _additionalWeight = _weightIncreaseSinceInteraction(
                currentEpoch.endTime,
                lastInteraction,
                totalStaked
            );
            epoch[epochId].weightAtEnd = _additionalWeight + _contractWeight;

            ++epochId;

            Epoch memory _epoch;
            _epoch.totalToDistribute =
                IERC20(prime).balanceOf(address(this)) -
                unclaimedRewards;
            _epoch.startTime = block.timestamp;
            _epoch.endTime = block.timestamp + epochLength;

            currentEpoch = _epoch;
            epoch[epochId] = _epoch;

            unclaimedRewards += _epoch.totalToDistribute;
        }
    }
}
