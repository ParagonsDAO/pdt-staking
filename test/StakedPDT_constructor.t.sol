// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Contract imports
import {StakedPDTTestBase} from "./StakedPDT_base.sol";

contract StakedPDTConstructorTest is StakedPDTTestBase {
    function test_constructor() public {
        assertEq(bStakedPDT.epochLength(), initialEpochLength);

        (uint256 _startTime, uint256 _endTime, ) = bStakedPDT.epoch(0);
        assertEq(_endTime - _startTime, initialFirstEpochStartIn);

        assertEq(bStakedPDT.pdt(), address(bPDTOFT));
    }
}
