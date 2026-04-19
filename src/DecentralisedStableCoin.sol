// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralisedStableCoin is ERC20Burnable, Ownable {
    /* Errors */
    error DecentralisedStableCoin__MustBeGreatedThanZero();
    error DecentralisedStableCoin__BalanceMustBeGreatedThanValue();
    error DecentralisedStableCoin__CannotMintToZeroAddress();

    /* Constructor */
    constructor() ERC20("Decentralised Stable Coin", "DSC") Ownable(msg.sender) {}

    /* Functions */
    /**
     * @dev This is the function that gets called for the burning mechanism of the token.
     * @dev It calls the ERC20Burnable burn function.
     * @param _value The amount of tokens that are to be burnt.
     */
    function burn(uint256 _value) public override onlyOwner {
        uint256 userBalance = balanceOf(msg.sender);

        if (_value <= 0) {
            revert DecentralisedStableCoin__MustBeGreatedThanZero();
        }

        if (userBalance < _value) {
            revert DecentralisedStableCoin__BalanceMustBeGreatedThanValue();
        }

        super.burn(_value);
    }

    /**
     * @dev This is the funciton used to mint tokens to a specific address.
     * @dev Calls the internal _mint function of an ERC20 token.
     * @param _to The address we want to mint the tokens to.
     * @param _amount The amount of tokens to be minted.
     * @return bool Returns true if the mint was done successfully.
     */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralisedStableCoin__CannotMintToZeroAddress();
        }

        if (_amount <= 0) {
            revert DecentralisedStableCoin__MustBeGreatedThanZero();
        }

        _mint(_to, _amount);

        return true;
    }
}
