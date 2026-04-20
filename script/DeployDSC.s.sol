// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";

contract DeployDSC is Script {
    /* Instantiate contracts */
    HelperConfig private helperConfig;
    DSCEngine private engine;

    /* State variables */

    /* Run function */
    function run() external returns (DSCEngine, HelperConfig) {}
}
