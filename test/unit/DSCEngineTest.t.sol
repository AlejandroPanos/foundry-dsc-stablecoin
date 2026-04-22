// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";

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
    address public ALICE = makeAddr("ALICE");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 private constant ALICE_COLLATERAL = 100 ether;
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
        ERC20Mock(weth).mint(ALICE, 100 ether);
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

    function testLiquidateReturnsIfHealthFactorIsOk() public {
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);

        engine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        vm.startPrank(ALICE);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, BOB, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testLiquidateRevertsIfAmountIsZero() public {
        vm.startPrank(ALICE);
        vm.expectRevert(DSCEngine.DSCEngine__AmountShouldBeMoreThanZero.selector);
        engine.liquidate(weth, BOB, 0);
        vm.stopPrank();
    }

    function testLiquidatorReceivesCollateralPlusBonus() public {
        // BOB deposits and mints
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        // ALICE deposits and mints BEFORE price crash
        vm.startPrank(ALICE);
        ERC20Mock(weth).approve(address(engine), ALICE_COLLATERAL);
        engine.depositCollateral(weth, ALICE_COLLATERAL);
        engine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        // NOW crash the price — both BOB and ALICE are affected
        // but ALICE already has her DSC to use as liquidator
        int256 crashedEthPrice = 18e8;
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(crashedEthPrice);

        // ALICE liquidates BOB
        vm.startPrank(ALICE);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        uint256 aliceWethBalanceBefore = ERC20Mock(weth).balanceOf(ALICE);
        engine.liquidate(weth, BOB, AMOUNT_TO_MINT);
        uint256 aliceWethBalanceAfter = ERC20Mock(weth).balanceOf(ALICE);
        vm.stopPrank();

        assert(aliceWethBalanceAfter > aliceWethBalanceBefore);
    }

    function testLiquidationImprovesHealthFactor() public {
        // Arrange — BOB deposits and mints to the limit
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        // Crash the price
        int256 crashedEthPrice = 18e8;
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(crashedEthPrice);

        uint256 bobHealthFactorBefore = engine.getHealthFactor(BOB);

        // ALICE liquidates BOB
        vm.startPrank(ALICE);
        ERC20Mock(weth).approve(address(engine), ALICE_COLLATERAL);
        engine.depositCollateral(weth, ALICE_COLLATERAL);
        engine.mintDsc(AMOUNT_TO_MINT);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.liquidate(weth, BOB, AMOUNT_TO_MINT);
        vm.stopPrank();

        uint256 bobHealthFactorAfter = engine.getHealthFactor(BOB);

        // Assert health factor improved
        assert(bobHealthFactorAfter > bobHealthFactorBefore);
    }
}
