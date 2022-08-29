pragma solidity ^0.8.0;

interface IPDTStaking {
    struct Stake {
        uint256 amountStaked;
        uint256 adjustedTimeStaked;
    }

    function stakeDetails(address _user) external view returns (Stake memory);
    function totalStaked() external view returns (uint256);
    function adjustedTime() external view returns (uint256);
    function timeToDouble() external view returns (uint256);
    function multiplierStart() external view returns (uint256);
}

