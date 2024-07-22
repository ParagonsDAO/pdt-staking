// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract WrappedStakedPDT is ERC20 {
    using SafeERC20 for IERC20;
    address public immutable stPDT;

    constructor(address _stPDT) ERC20("Wrapped stPDT", "wstPDT") {
        stPDT = _stPDT;
    }

    function wrap(uint256 _amount) external {
        require(IERC20(stPDT).transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        _mint(msg.sender, _amount);
    }

    function unwrap(uint256 _amount) external {
        _burn(msg.sender, _amount);
        require(IERC20(stPDT).transfer(msg.sender, _amount), "Transfer failed");
    }
}
