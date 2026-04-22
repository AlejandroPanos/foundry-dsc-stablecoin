// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    /* Instantiate contracts */
    DeployDSC deployer;
    DSCEngine engine;
    DecentralisedStableCoin dsc;
    HelperConfig helperConfig;

    /* State variables */
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    HelperConfig.NetworkConfig config;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    /* Set up function */
    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        config = helperConfig.getActiveNetworkConfig();
        wethUsdPriceFeed = config.wethUsdPriceFeed;
        wbtcUsdPriceFeed = config.wbtcUsdPriceFeed;
        weth = config.weth;
        wbtc = config.wbtc;

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /* ============================================================ */
    /* Constructor Tests                                            */
    /* ============================================================ */
    function testRevertsIfLegthsAreNotEqual() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__AddressesMustBeOfSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testConstructorAddsToMapping() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        assertEq(engine.getCollateralTokenPriceFeed(weth), priceFeedAddresses[0]);
        assertEq(engine.getCollateralTokenPriceFeed(wbtc), priceFeedAddresses[1]);
    }

    function testConstructorAddsToArray() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        assertEq(engine.getCollateralTokens().length, 2);
    }

    /* ============================================================ */
    /* External and public functions tests                          */
    /* ============================================================ */
    function testDepositCollateralAddsCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        assertEq(engine.getCollateralBalanceOfUser(USER, weth), AMOUNT_COLLATERAL);
    }
}
