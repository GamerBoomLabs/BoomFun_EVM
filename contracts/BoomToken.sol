// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract BoomToken is ERC20, ERC20Burnable {
    uint256 public constant INITIAL_SUPPLY = 10**9;

    constructor(
    ) ERC20("Boom Token", "BOOM") {
        _mint(msg.sender, INITIAL_SUPPLY * (10**decimals()));
    }
}
