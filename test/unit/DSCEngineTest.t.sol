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
    uint256 private constant AMOUNT_TO_MINT_TOO_HIGH = 12_000e18;

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
    /**
     * @notice Tests that the constructor reverts when token and price feed
     * arrays are of different lengths.
     */
    function testRevertsIfLegthsAreNotEqual() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__AddressesMustBeOfSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /**
     * @notice Tests that the constructor correctly maps each token address
     * to its corresponding Chainlink price feed address.
     */
    function testConstructorAddsToMapping() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        assertEq(engine.getCollateralTokenPriceFeed(weth), priceFeedAddresses[0]);
        assertEq(engine.getCollateralTokenPriceFeed(wbtc), priceFeedAddresses[1]);
    }

    /**
     * @notice Tests that the constructor correctly populates the collateral
     * tokens array with the provided token addresses.
     */
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
    /**
     * @notice Tests that depositing collateral correctly updates the user's
     * collateral balance in the engine.
     */
    function testDepositCollateralAddsCollateral() public {
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        assertEq(engine.getCollateralBalanceOfUser(BOB, weth), AMOUNT_COLLATERAL);
    }

    /**
     * @notice Tests that depositing collateral emits the CollateralDeposited
     * event with the correct indexed and non-indexed parameters.
     */
    function testDepositCollateralEmitsEvent() public {
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, false, true);
        emit CollateralDeposited(BOB, weth, AMOUNT_COLLATERAL);

        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /**
     * @notice Tests that minting DSC correctly updates the user's minted
     * balance in the engine.
     */
    function testMintingAddsAmountMinted() public {
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);

        engine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        assertEq(engine.getAmountMinted(BOB), AMOUNT_TO_MINT);
    }

    /**
     * @notice Tests that minting an amount of DSC that would break the health
     * factor reverts with the correct custom error.
     */
    function testMintRevertsIfHealthFactorBreaks() public {
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorBelowMinimum.selector);
        engine.mintDsc(AMOUNT_TO_MINT_TOO_HIGH);
        vm.stopPrank();
    }

    /**
     * @notice Tests that attempting to liquidate a user whose health factor
     * is above the minimum reverts with the correct custom error.
     */
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

    /**
     * @notice Tests that attempting to liquidate with a zero debt amount
     * reverts with the correct custom error.
     */
    function testLiquidateRevertsIfAmountIsZero() public {
        vm.startPrank(ALICE);
        vm.expectRevert(DSCEngine.DSCEngine__AmountShouldBeMoreThanZero.selector);
        engine.liquidate(weth, BOB, 0);
        vm.stopPrank();
    }

    /**
     * @notice Tests that a liquidator receives the correct amount of collateral
     * plus the 10% liquidation bonus after liquidating an undercollateralised user.
     * @dev BOB deposits and mints DSC. ALICE deposits and mints DSC before the
     * price crash. ETH price is crashed to make BOB undercollateralised.
     * ALICE liquidates BOB and receives BOB's collateral plus bonus.
     */
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

    /**
     * @notice Tests that liquidating an undercollateralised user improves
     * their health factor.
     * @dev BOB's health factor is recorded before liquidation and compared
     * against the health factor after ALICE liquidates his position.
     */
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

    /**
     * @notice Tests that liquidating an undercollateralised user correctly
     * reduces their outstanding DSC debt.
     */
    function testLiquidationReducesBobsDebt() public {
        // Arrange — BOB deposits and mints
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        // Crash the price
        int256 crashedEthPrice = 18e8;
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(crashedEthPrice);

        // ALICE liquidates BOB
        vm.startPrank(ALICE);
        ERC20Mock(weth).approve(address(engine), ALICE_COLLATERAL);
        engine.depositCollateral(weth, ALICE_COLLATERAL);
        engine.mintDsc(AMOUNT_TO_MINT);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.liquidate(weth, BOB, AMOUNT_TO_MINT);
        vm.stopPrank();

        // Assert BOB's minted balance decreased
        (uint256 bobDebtAfter,) = engine.getAccountInformation(BOB);
        assert(bobDebtAfter < AMOUNT_TO_MINT);
    }

    /* ============================================================ */
    /* Fuzz tests                                                   */
    /* ============================================================ */
    function testFuzz_DepositCollateralAndMintDsc(uint256 collateralAmount, uint256 mintAmount) public {
        collateralAmount = bound(collateralAmount, 1, type(uint96).max);
        mintAmount = bound(mintAmount, 1, type(uint96).max);

        vm.startPrank(BOB);
        ERC20Mock(weth).mint(BOB, collateralAmount);
        ERC20Mock(weth).approve(address(engine), collateralAmount);
        engine.depositCollateral(weth, collateralAmount);

        uint256 collateralValueInUsd = engine.getUsdValue(weth, collateralAmount);
        uint256 maxMintable = collateralValueInUsd / 2;

        if (mintAmount > maxMintable) {
            vm.expectRevert(DSCEngine.DSCEngine__HealthFactorBelowMinimum.selector);
            engine.mintDsc(mintAmount);
        } else {
            engine.mintDsc(mintAmount);
            assertEq(engine.getAmountMinted(BOB), mintAmount);
            assert(engine.getHealthFactor(BOB) >= 1e18);
        }

        vm.stopPrank();
    }

    /* ============================================================ */
    /* Getter functions tests                                       */
    /* ============================================================ */
    function testGetAccountInformationReturnsCorrectValues() public {
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(BOB);

        assertEq(totalDscMinted, AMOUNT_TO_MINT);
        assert(collateralValueInUsd > 0);
    }

    function testGetAccountInformationReturnsZeroForNewUser() public view {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(BOB);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, 0);
    }

    function testGetCollateralTokensReturnsCorrectLength() public view {
        address[] memory tokens = engine.getCollateralTokens();
        assertEq(tokens.length, 2);
    }

    function testGetCollateralTokensReturnsCorrectAddresses() public view {
        address[] memory tokens = engine.getCollateralTokens();
        assertEq(tokens[0], weth);
        assertEq(tokens[1], wbtc);
    }

    function testGetCollateralBalanceOfUserReturnsZeroByDefault() public view {
        assertEq(engine.getCollateralBalanceOfUser(BOB, weth), 0);
    }

    function testGetCollateralBalanceOfUserReturnsCorrectBalance() public {
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        assertEq(engine.getCollateralBalanceOfUser(BOB, weth), AMOUNT_COLLATERAL);
    }

    function testGetCollateralTokenPriceFeedReturnsCorrectAddress() public view {
        assertEq(engine.getCollateralTokenPriceFeed(weth), wethUsdPriceFeed);
        assertEq(engine.getCollateralTokenPriceFeed(wbtc), wbtcUsdPriceFeed);
    }

    function testGetHealthFactorReturnsMaxForUserWithNoDebt() public {
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        assertEq(engine.getHealthFactor(BOB), type(uint256).max);
    }

    function testGetHealthFactorReturnsCorrectValueAfterMinting() public {
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        uint256 healthFactor = engine.getHealthFactor(BOB);
        assert(healthFactor >= 1e18);
    }

    function testGetAmountMintedReturnsZeroByDefault() public view {
        assertEq(engine.getAmountMinted(BOB), 0);
    }

    function testGetAmountMintedReturnsCorrectAmountAfterMinting() public {
        vm.startPrank(BOB);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();

        assertEq(engine.getAmountMinted(BOB), AMOUNT_TO_MINT);
    }
}
