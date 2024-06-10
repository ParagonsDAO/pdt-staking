// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/PDTStakingV2.sol";

contract MyScript is Script {
    address immutable PDT = 0x7Bdc3eFBCfc97E56176Da8ac76B980246e959B3A;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        PDTStakingV2 stakingV2 = new PDTStakingV2(
            2 days,
            2 days,
            PDT,
            0xde6789416001dB6F295E47D5C58B9e17DE70cE65
        );

        vm.stopBroadcast();
    }
}
