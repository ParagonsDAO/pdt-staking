// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Contract imports
import {StakedPDTTestBase} from "./StakedPDT_base.sol";

contract StakedPDTRegisterNewRewardTokenTest is StakedPDTTestBase {
    function test_registerNewRewardToken_RevertIf_NonManagerCallFunction() public {
        vm.expectRevert();
        bStakedPDT.registerNewRewardToken(bPROMPTAddress);
    }

    function test_registerNewRewardToken_RevertIf_RegisterExistingToken() public {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(DuplicatedRewardToken.selector, bPRIMEAddress));
        bStakedPDT.registerNewRewardToken(bPRIMEAddress);
        vm.stopPrank();
    }

    function test_registerNewRewardToken_ManagerCanRegister() public {
        vm.startPrank(owner);
        // add PROMPT as a new active reward token
        bStakedPDT.registerNewRewardToken(bPROMPTAddress);

        // check reward token list
        assertEq(bStakedPDT.rewardTokenList(0), bPRIMEAddress);
        assertEq(bStakedPDT.rewardTokenList(1), bPROMPTAddress);

        // should not allow to add PDT token
        vm.expectRevert("Invalid reward token");
        bStakedPDT.registerNewRewardToken(bPDTOFTAddress);

        vm.stopPrank();
    }

    function test_registerNewRewardToken_DefaultAdminCanRegister() public {
        vm.startPrank(owner);
        // add PROMPT as a new active reward token
        bStakedPDT.registerNewRewardToken(bPROMPTAddress);

        // check reward token list
        assertEq(bStakedPDT.rewardTokenList(0), bPRIMEAddress);
        assertEq(bStakedPDT.rewardTokenList(1), bPROMPTAddress);

        vm.stopPrank();
    }
}
