// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";

contract PDTOFTAdapter is OFTAdapter {
    constructor(
        address _token,
        address _layerZeroEndpoint,
        address _delegate
    ) OFTAdapter(_token, _layerZeroEndpoint, _delegate) Ownable(_delegate) {}
}
