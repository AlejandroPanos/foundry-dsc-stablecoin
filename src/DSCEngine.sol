// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "src/libraries/OracleLib.sol";

contract DSCEngine is ReentrancyGuard {
    /* Libraries */
    using OracleLib for AggregatorV3Interface;

    /* Errors */

    /* State variables */

    /* Constructor */
    constructor() {}

    /* Functions */
}
