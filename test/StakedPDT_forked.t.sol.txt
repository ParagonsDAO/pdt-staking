// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// Forge imports
import {Test, console} from "forge-std/Test.sol";

// Contract imports
import {IForkedPDTStakingV2} from "../src/interfaces/IForkedPDTStakingV2.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ForkedPDTStakingV2Test is Test {
    using SafeERC20 for IERC20;

    address private owner = 0xde6789416001dB6F295E47D5C58B9e17DE70cE65;
    address private user = 0x7E6D003c0A3AA5BE66e3fbDb4Cddb7Ac22F045dB;
    address private bPRIME = 0xeff2A458E464b07088bDB441C21A42AB4b61e07E;
    address private bPROMPT = 0xB160977a4596DDf96255FCD5F012B267623A56C0;
    address private bPDTStakingV2Address = 0x540ac83541951739Ff47AE94D2316a8193641586;

    function testFork_distribute() public {
        IForkedPDTStakingV2 bPDTStakingV2 = IForkedPDTStakingV2(bPDTStakingV2Address);

        vm.startPrank(owner);
        bPDTStakingV2.upsertRewardToken(bPROMPT, false);
        bPDTStakingV2.distribute();
        bPDTStakingV2.upsertRewardToken(bPROMPT, true);
        vm.stopPrank();

        vm.startPrank(user);
        bPDTStakingV2.claim(user);
        vm.stopPrank();
    }
}
