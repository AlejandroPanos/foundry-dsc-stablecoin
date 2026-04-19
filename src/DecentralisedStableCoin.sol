// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralisedStableCoin is ERC20Burnable, Ownable {
    /* Constructor */
    constructor() ERC20("Decentralised Stable Coin", "DSC") Ownable(msg.sender) {}

    /* Functions */
    function burn(uint256 _value) public override onlyOwner {}

    function mint(address _to, _uint256 amount) external onlyOwner returns (bool) {}
}
