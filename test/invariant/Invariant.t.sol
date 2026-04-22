// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "test/invariant/Handler.t.sol";

contract Invariant is StdInvariant, Test {
    /* Instantiate contracts */
    DeployDSC deployer;
    DSCEngine engine;
    DecentralisedStableCoin dsc;
    HelperConfig helperConfig;
    Handler handler;

    address weth;
    address wbtc;

    HelperConfig.NetworkConfig config;

    /* Set up function */
    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        config = helperConfig.getActiveNetworkConfig();
        weth = config.weth;
        wbtc = config.wbtc;
        handler = new Handler(engine, dsc);
        targetContract(address(handler));
    }

    /* Invariants */
    function invariant_valueOfCollateralGreaterOrEqualToTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethUsdValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcUsdValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        assert(wethUsdValue + wbtcUsdValue >= totalSupply);
    }
}
