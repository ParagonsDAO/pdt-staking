// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address account_, uint256 amount_) external {
        _mint(account_, amount_);
    }
}
