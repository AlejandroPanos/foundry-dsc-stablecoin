// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";

contract DeployDSC is Script {
    /* Instantiate contracts */
    HelperConfig private helperConfig;
    DSCEngine private engine;
    DecentralisedStableCoin private dsc;

    /* State variables */
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    address[] tokenAddresses;
    address[] priceFeedAddresses;

    /* Run function */
    function run() external returns (DecentralisedStableCoin, DSCEngine, HelperConfig) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();
        wethUsdPriceFeed = config.wethUsdPriceFeed;
        wbtcUsdPriceFeed = config.wbtcUsdPriceFeed;
        weth = config.weth;
        wbtc = config.wbtc;
        deployerKey = config.deployerKey;

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast();
        dsc = new DecentralisedStableCoin();
        engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        dsc.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (dsc, engine, helperConfig);
    }
}
