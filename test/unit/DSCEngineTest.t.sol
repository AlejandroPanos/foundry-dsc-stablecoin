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

    address public BOB = makeAddr("BOB");
    address public JOHN = makeAddr("JOHN");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100e18;
    uint256 private constant AMOUNT_TO_MINT_TOO_HIGH = 12_000e18; // just over the limit

    HelperConfig.NetworkConfig config;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    /* Events */
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    /* Set up function */
    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        config = helperConfig.getActiveNetworkConfig();
        wethUsdPriceFeed = config.wethUsdPriceFeed;
        wbtcUsdPriceFeed = config.wbtcUsdPriceFeed;
        weth = config.weth;
        wbtc = config.wbtc;

        ERC20Mock(weth).mint(BOB, STARTING_ERC20_BALANCE);
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
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        assertEq(engine.getCollateralBalanceOfUser(BOB, weth), AMOUNT_COLLATERAL);
    }

    function testDepositCollateralEmitsEvent() public {
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, false, true);
        emit CollateralDeposited(BOB, weth, AMOUNT_COLLATERAL);

        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testMintingAddsAmountMinted() public {
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);

        engine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        assertEq(engine.getAmountMinted(BOB), AMOUNT_TO_MINT);
    }

    function testMintRevertsIfHealthFactorBreaks() public {
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorBelowMinimum.selector);
        engine.mintDsc(AMOUNT_TO_MINT_TOO_HIGH);
        vm.stopPrank();
    }
}
