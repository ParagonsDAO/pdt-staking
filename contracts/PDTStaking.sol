pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

/// @title   PDT Staking
/// @notice  Contract that allows users to stake PDT
/// @author  JeffX
contract PDTStaking {
    /// ERRORS ///

    /// @notice Error for if epoch is invalid
    error InvalidEpoch();
    /// @notice Error for if user has claimed for epoch
    error EpochClaimed();
    /// @notice Error for if there is nothing to claim
    error NothingToClaim();
    /// @notice Error for if staking more than balance
    error MoreThanBalance();
    /// @notice Error for if unstaking more than staked
    error MoreThanStaked();

    /// STRUCTS ///

    /// @notice                     Details for epoch
    /// @param totalToDistirbute    Total amount of token to distirbute for epoch
    /// @param totalClaimed         Total amount of tokens claimed from epoch
    /// @param startTime            Timestamp epoch started
    /// @param endTime              Timestamp epoch ends
    /// @param meanMultiplierAtEnd  Mean multiplier at end of epoch
    /// @param weightAtEnd          Weight of staked tokens at end of epoch
    struct Epoch {
        uint256 totalToDistirbute;
        uint256 totalClaimed;
        uint256 startTime;
        uint256 endTime;
        uint256 meanMultiplierAtEnd;
        uint256 weightAtEnd;
    }

    /// @notice                    Stake details for user
    /// @param amountStaked        Amount user has staked
    /// @param adjustedTimeStaked  Adjusted time user staked
    /// @param lastInteraction     Timestamp last interacted
    struct Stake {
        uint256 amountStaked;
        uint256 adjustedTimeStaked;
        uint256 lastInteraction;
    }

    /// STATE VARIABLES ///

    /// @notice Starting multiplier
    uint256 public constant multiplierStart = 1e18;
    /// @notice Length of epoch
    uint256 public immutable epochLength;

    /// @notice Timestmap contract was deplpoyed
    uint256 public immutable startTime;
    /// @notice Time to double multiplier
    uint256 public immutable timeToDouble;

    /// @notice Adjusted time for contract
    uint256 public adjustedTime;

    /// @notice Total amount of PDT staked
    uint256 public totalStaked;
    /// @notice Last interaction with contract
    uint256 private lastInteraction;
    /// @notice Amount of unclaimed rewards
    uint256 private unclaimedRewards;

    /// @notice Epoch id
    uint256 public epochId;

    /// @notice Current epoch
    Epoch public currentEpoch;

    /// @notice Address of PDT
    address public immutable pdt;
    /// @notice Address of reward token
    address public immutable rewardToken;

    /// @notice If user has claimed for certain epoch
    mapping(address => mapping(uint256 => bool)) public userClaimedEpoch;
    /// @notice User's multiplier at end of epoch
    mapping(address => mapping(uint256 => uint256)) public userMultiplierAtEpoch;
    /// @notice User's weight at an epoch
    mapping(address => mapping(uint256 => uint256)) public userWeightAtEpoch;
    /// @notice Epoch user has last claimed
    mapping(address => uint256) public epochLeftOff;
    /// @notice Id to epoch details
    mapping(uint256 => Epoch) public epoch;
    /// @notice Stake details of user
    mapping(address => Stake) public stakeDetails;

    /// CONSTRUCTOR ///

    /// @param _timeToDouble  Time for multiplier to double
    /// @param _epochLength   Length of epoch
    /// @param _pdt           PDT token address
    /// @param _rewardToken   Address of reward token
    constructor(
        uint256 _timeToDouble,
        uint256 _epochLength,
        address _pdt,
        address _rewardToken

    ) {
        startTime = block.timestamp;
        lastInteraction = block.timestamp;
        adjustedTime = block.timestamp;
        currentEpoch.endTime = block.timestamp;
        timeToDouble = _timeToDouble;
        epochLength = _epochLength;
        pdt = _pdt;
        rewardToken = _rewardToken;
    }

    /// PUBLIC FUNCTIONS ///

    /// @notice  Update epoch details if time
    function distirbute() public {
        if (block.timestamp >= currentEpoch.endTime) {
            uint256 multiplier_ = _multiplier(currentEpoch.endTime, adjustedTime);
            epoch[epochId].meanMultiplierAtEnd = multiplier_;
            epoch[epochId].weightAtEnd = multiplier_ * totalStaked;

            ++epochId;
            Epoch memory _epoch;
            _epoch.totalToDistirbute = IERC20(rewardToken).balanceOf(address(this)) - unclaimedRewards;
            _epoch.startTime = block.timestamp;
            _epoch.endTime = block.timestamp + epochLength;

            currentEpoch = _epoch;
            epoch[epochId] = _epoch;

            unclaimedRewards += _epoch.totalToDistirbute;
        }
    }

    /// @notice         Stake PDT
    /// @param _to      Address that will recieve credit for stake
    /// @param _amount  Amount of PDT to stake
    function stake(address _to, uint256 _amount) external {
        if (IERC20(pdt).balanceOf(msg.sender) < _amount) revert MoreThanBalance();
        distirbute();
        _setUserMultiplierAtEpoch(_to);
        IERC20(pdt).transferFrom(msg.sender, address(this), _amount);

        _adjustMeanMultilpier(true, _amount);

        totalStaked += _amount;

        Stake memory stakeDetail = stakeDetails[_to];

        uint256 previousStakeAmount = stakeDetail.amountStaked;

        if (previousStakeAmount > 0) {
            uint256 previousTimeStaked = stakeDetail.adjustedTimeStaked;
            uint256 percentStakeIncreased = (1e18 * _amount) / (previousStakeAmount + _amount);
            stakeDetail.adjustedTimeStaked = previousTimeStaked + ((percentStakeIncreased * (block.timestamp - previousTimeStaked)) / 1e18);
        } else {
            stakeDetail.adjustedTimeStaked = block.timestamp;
        }

        stakeDetail.amountStaked += _amount;
        stakeDetail.lastInteraction = block.timestamp;
        lastInteraction = block.timestamp;

        stakeDetails[_to] = stakeDetail;
    }

    /// @notice         Unstake PDT
    /// @param _to      Address that will recieve PDT unstaked
    /// @param _amount  Amount of PDT to unstake
    function unstake(address _to, uint256 _amount) external {
        Stake memory stakeDetail = stakeDetails[msg.sender];

        if (stakeDetail.amountStaked < _amount) revert MoreThanStaked();
        distirbute();
        _setUserMultiplierAtEpoch(msg.sender);
        _adjustMeanMultilpier(false, _amount);

        totalStaked -= _amount;

        uint256 previousStakeAmount = stakeDetail.amountStaked;
        uint256 previousTimeStaked = stakeDetail.adjustedTimeStaked;

        uint256 percentStakeDecreased = (1e18 * _amount) / previousStakeAmount / 1e18;
        console.log("DECREASE %: %s", percentStakeDecreased);

        stakeDetail.amountStaked -= _amount;
        console.log("TIMESTAMP: %s", block.timestamp);
        console.log("PREV STAKE: %s", previousTimeStaked);
        console.log("DIFFERECE: %s", block.timestamp - previousTimeStaked);
        stakeDetail.adjustedTimeStaked = previousTimeStaked - ((percentStakeDecreased * (block.timestamp - previousTimeStaked)));
        stakeDetail.lastInteraction = block.timestamp;
        lastInteraction = block.timestamp;

        IERC20(pdt).transfer(_to, _amount);
        stakeDetails[msg.sender] = stakeDetail;
    }

    /// @notice           Claims rewards tokens for msg.sender of `_epochIds`
    /// @param _to        Address to send rewards to
    /// @param _epochIds  Array of epoch ids to claim for
    function claim(address _to, uint256[] calldata _epochIds) external {
        _setUserMultiplierAtEpoch(msg.sender);

        uint256 _pendingRewards;

        for (uint256 i; i < _epochIds.length; ++i) {
            if (userClaimedEpoch[msg.sender][_epochIds[i]]) revert EpochClaimed();
            if (epochId <= _epochIds[i]) revert InvalidEpoch();

            userClaimedEpoch[msg.sender][_epochIds[i]] = true;
            Epoch memory _epoch = epoch[_epochIds[i]];
            uint256 _userWeightAtEpoch = userWeightAtEpoch[msg.sender][_epochIds[i]];
            uint256 _epochRewards = (_epoch.totalToDistirbute * _userWeightAtEpoch) / weightAtEpoch(_epochIds[i]);
            if (_epoch.totalClaimed + _epochRewards > _epoch.totalToDistirbute) {
                _epochRewards = _epoch.totalToDistirbute - _epoch.totalClaimed;
            }
            _pendingRewards += _epochRewards;
            _epoch.totalClaimed += _epochRewards;
            epoch[_epochIds[i]] = _epoch;
        }

        unclaimedRewards -= _pendingRewards;
        IERC20(rewardToken).transfer(_to, _pendingRewards);
    }

    /// VIEW FUNCTIONS ///

    /// @notice         Returns multiplier if staked from beginning
    /// @return index_  Multiplier index
    function multiplierIndex() public view returns (uint256 index_) {
        return _multiplier(block.timestamp, startTime);
    }

    /// @notice              Returns contracts mean multiplier
    /// @return multiplier_  Current mean multiplier of contract
    function meanMultiplier() public view returns (uint256 multiplier_) {
        return _multiplier(block.timestamp, adjustedTime);
    }

    /// @notice              Returns `multiplier_' of `_user`
    /// @param _user         Address of who getting `multiplier_` for
    /// @return multiplier_  Current multiplier of `_user`
    function userStakeMultiplier(address _user) public view returns (uint256 multiplier_) {
        Stake memory stakeDetail = stakeDetails[_user];
        if (stakeDetail.amountStaked > 0) return _multiplier(block.timestamp, stakeDetail.adjustedTimeStaked);
    }

    /// @notice              Returns `multiplier_' of `_user` at `_epochId`
    /// @param _user         Address of user getting `multiplier_` of `_epochId`
    /// @param _epochId      Epoch of id to get user for
    /// @return multiplier_  Multiplier of `_user` at `_epochId`
    function userStakeMultiplierAtEpoch(address _user, uint256 _epochId) external view returns (uint256 multiplier_) {
        if (epochId <= _epochId) revert InvalidEpoch();
        uint256 _epochLeftOff = epochLeftOff[_user];
        Stake memory stakeDetail = stakeDetails[_user];

        if (_epochLeftOff > _epochId) multiplier_ = userMultiplierAtEpoch[_user][_epochId];
        else {
            Epoch memory _epoch = epoch[_epochId];
            if (stakeDetail.amountStaked > 0) return _multiplier(_epoch.endTime, stakeDetail.adjustedTimeStaked);
        }
    }

    /// @notice          Returns weight of contract at `_epochId`
    /// @param _epochId  Id of epoch wanting to get weight for
    /// @return uint256  Weight of contract for `_epochId`
    function weightAtEpoch(uint256 _epochId) public view returns (uint256) {
        if (epochId <= _epochId) revert InvalidEpoch();
        return epoch[_epochId].weightAtEnd;
    }

    /// INTERNAL VIEW FUNCTION ///

    /// @notice               Returns multiplier using `_timestamp` and `_adjustedTime`
    /// @param _timeStamp     Timestamp to use to calcaulte `multiplier_`
    /// @param _adjustedTime  Adjusted stake time to use to calculate `multiplier_`
    /// @return multiplier_   Multitplier using `_timeStamp` and `adjustedTime`
    function _multiplier(uint256 _timeStamp, uint256 _adjustedTime) internal view returns (uint256 multiplier_) {
        uint256 _adjustedTimePassed = _timeStamp - _adjustedTime;
        multiplier_ = multiplierStart + ((multiplierStart * _adjustedTimePassed) / timeToDouble);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice         Adjust mean multiplier of the contract
    /// @param _stake   Bool if `_amount` is being staked or withdrawn
    /// @param _amount  Amount of PDT being staked or withdrawn
    function _adjustMeanMultilpier(bool _stake, uint256 _amount) internal {
        uint256 previousTotalStaked = totalStaked;
        uint256 previousTimeStaked = adjustedTime;

        uint256 timePassed = block.timestamp - previousTimeStaked;

        uint256 percent;

        if (_stake) {
            percent = (1e18 * _amount) / (previousTotalStaked + _amount);
            adjustedTime = previousTimeStaked + ((timePassed * percent) / 1e18);
        } else {
            percent = (1e18 * _amount) / (previousTotalStaked);
            adjustedTime = previousTimeStaked - ((timePassed * percent) / 1e18);
        }
    }

    /// @notice        Set epochs of `_user` that they left off on
    /// @param _user   Address of user being updated
    function _setUserMultiplierAtEpoch(address _user) internal {
        uint256 _epochLeftOff = epochLeftOff[_user];

        if (_epochLeftOff != epochId) {
            Stake memory stakeDetail = stakeDetails[_user];

            for (_epochLeftOff; _epochLeftOff < epochId; ++_epochLeftOff) {
                Epoch memory _epoch = epoch[_epochLeftOff];
                if (stakeDetail.amountStaked > 0) {
                    uint256 _adjustedTimePassed = _epoch.endTime - stakeDetail.adjustedTimeStaked;
                    uint256 _multiplier = multiplierStart + ((multiplierStart * _adjustedTimePassed) / timeToDouble);
                    userMultiplierAtEpoch[_user][_epochLeftOff] = _multiplier;
                    userWeightAtEpoch[_user][_epochLeftOff] = _multiplier * stakeDetail.amountStaked;
                }
            }

            epochLeftOff[_user] = epochId;
        }
    }

    function timestamp() external view returns (uint256) {
        return block.timestamp;
    }
}
