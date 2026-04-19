// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "src/libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Alejandro Paños
 *
 * The system is designed to be as minimal as possible and it is built in a way
 * that the token always has the value of 1USD pegged to it.
 *
 * The token has the following characteristics:
 * 1. Exogenously collateralised
 * 2. Pegged to the value of the USD
 * 3. Is fully algorithmic
 *
 * @notice The system is created so that it always has to be overcollateralized. This
 * means that at no point, should the value of all collateral exceed the dollar value
 * pegged to the DSC token.
 * @dev This contract is the core of the implementation of the DeFi protocol. It controls
 * everything from minting, depositing, liquidating, etc.
 */

contract DSCEngine is ReentrancyGuard {
    /* Libraries */
    using OracleLib for AggregatorV3Interface;

    /* Errors */
    error DSCEngine__AddressesMustBeOfSameLength();

    /* State variables */
    mapping(address token => address priceFeed) private s_tokenToPriceFeed;
    address[] private s_collateralTokens;

    DecentralisedStableCoin private immutable i_dsc;

    /* Constructor */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dsc) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__AddressesMustBeOfSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_tokenToPriceFeed[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralisedStableCoin(dsc);
    }

    /* Functions */
    function depositCollateral() public {}

    function mintDsc() public {}

    function depositCollateralAndMint() public {}

    function redeemCollateral() public {}

    function burnDsc() public {}

    function redeemCollateralForDsc() public {}

    function liquidate() public {}

    /* Internal functions */
    function _revertIfHealthFactorIsBroken() internal {}
}
