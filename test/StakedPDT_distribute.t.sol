// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Contract imports
import {StakedPDTTestBase} from "./StakedPDT_base.sol";

contract StakedPDTDistributeTest is StakedPDTTestBase {
    function test_distribute_StartFirstEpochAfterEpoch0Ended() public {
        assertEq(bStakedPDT.currentEpochId(), 0);

        _creditPRIMERewardPool(1);
        _moveToNextEpoch(0);

        assertEq(bStakedPDT.currentEpochId(), 1);
    }

    function testFail_distribute_EmptyRewardPool() public {
        /// EPOCH 0

        uint256 defaultPoolSize = 100;
        _creditPRIMERewardPool(defaultPoolSize);
        _moveToNextEpoch(0);

        /// EPOCH 1 - active reward tokens: PRIME

        _creditPRIMERewardPool(defaultPoolSize);
        _creditPROMPTRewardPool(defaultPoolSize);
        _moveToNextEpoch(1);

        /// EPOCH 2 - active reward tokens: PRIME, PROMPT

        _moveToNextEpoch(2);
    }
}
