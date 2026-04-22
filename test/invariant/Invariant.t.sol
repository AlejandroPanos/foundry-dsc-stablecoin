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

    /* State variables */
    address weth;
    address wbtc;

    HelperConfig.NetworkConfig config;

    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    /* Set up function */
    /**
     * @notice Deploys all contracts and sets up the invariant test environment.
     * @dev Deploys DSC, DSCEngine and HelperConfig via the DeployDSC script.
     * @dev Deploys the Handler contract and sets it as the target contract so
     * Foundry only calls functions through the handler during invariant runs.
     */
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
    /**
     * @notice Invariant asserting that the total USD value of all collateral held
     * by the engine always equals or exceeds the total DSC supply in circulation.
     * @notice This is the core solvency guarantee of the protocol — if this invariant
     * ever breaks the system is insolvent and DSC is no longer fully backed.
     * @dev Retrieves the WETH and WBTC balances held by the engine and converts
     * both to USD using Chainlink price feeds via the engine's getUsdValue() function.
     * @dev Compares the total collateral USD value against the DSC total supply.
     */
    function invariant_valueOfCollateralGreaterOrEqualToTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethUsdValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcUsdValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        assert(wethUsdValue + wbtcUsdValue >= totalSupply);
    }

    /**
     * @notice Invariant asserting that no user's health factor falls below the
     * minimum threshold after any sequence of valid protocol operations.
     * @notice A broken health factor means a user is undercollateralised and
     * eligible for liquidation — this invariant verifies the protocol never
     * allows a user to reach that state through normal operations alone.
     * @dev Iterates over all addresses that have deposited collateral via the
     * handler and checks each user's health factor against MIN_HEALTH_FACTOR.
     * @dev Uses the handler's getUsersWithCollateralDeposited() getter to access
     * the list of actors that Foundry has interacted with during the invariant run.
     */
    function invariant_healthFactorDoesNotFallBelowMinimum() public view {
        for (uint256 i = 0; i < handler.getUsersWithCollateralDeposited().length; i++) {
            address user = handler.getUsersWithCollateralDeposited()[i];
            uint256 healthFactor = engine.getHealthFactor(user);
            assert(healthFactor >= MIN_HEALTH_FACTOR);
        }
    }
}
