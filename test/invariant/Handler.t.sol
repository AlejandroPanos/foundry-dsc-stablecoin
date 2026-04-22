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
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    /* Instantiate contracts */
    DSCEngine engine;
    DecentralisedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    /* State variables */
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint256).max;

    /* Constructor */
    constructor(DSCEngine _engine, DecentralisedStableCoin _dsc) {
        engine = _engine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
    }

    /* Functions */
    /**
     * @notice This function allows a user to mint a specific amount of DSC token.
     * @param amount The amount of token the user wants to mint.
     * @param addressSeed A random number used to select a user from the array
     * of addresses that have deposited collateral.
     * @dev The sender is selected by applying modulo to the address seed against the length
     * of the deposited collateral users array, producing a valid array index.
     * @dev Returns early if no users have deposited collateral or if the maximum
     * mintable amount is zero or negative, to avoid invalid state transitions.
     */
    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }

        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalMinted, uint256 collateralValue) = engine.getAccountInformation(sender);
        int256 maxDSCToMint = (int256(collateralValue) / 2) - int256(totalMinted);

        if (maxDSCToMint < 0) {
            return;
        }

        amount = bound(amount, 0, uint256(maxDSCToMint));

        if (amount == 0) {
            return;
        }

        vm.startPrank(sender);
        engine.mintDsc(amount);
        vm.stopPrank();
    }

    /**
     * @notice This function is used to deposit an amount of collateral by the
     * user that calls the function.
     * @param collateralSeed Is a random number that is used to get the specific
     * ERC20Mock contract for the specific collateral.
     * @param amountCollateral The amount of collateral to deposit, bounded between
     * 1 and MAX_DEPOSIT_SIZE.
     * @dev See _getCollateralFromSeed(uint256 collateralSeed) to get a better
     * understanding of the implementation of collateralSeed.
     * @dev Adds msg.sender to the usersWithCollateralDeposited array after a successful
     * deposit so they can be selected as actors in subsequent handler calls.
     * @dev Mints mock ERC20 tokens directly to msg.sender and approves the engine
     * before calling depositCollateral, simulating a user who already holds collateral tokens.
     */
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        usersWithCollateralDeposited.push(msg.sender);
    }

    /**
     * @notice This function is used to redeem an amount of collateral by the
     * user that calls the function.
     * @param collateralSeed Is a random number that is used to get the specific
     * ERC20Mock contract for the specific collateral.
     * @param amountCollateral The amount of collateral to redeem, bounded between
     * 1 and the maximum amount of collateral the user is able to redeem.
     * @dev See _getCollateralFromSeed(uint256 collateralSeed) to get a better
     * understanding of the implementation of collateralSeed.
     * @dev Returns early if the amount of collateral the user has available to
     * redeem is equal to zero.
     * @dev Calls redeemCollateral directly as msg.sender without pranking since
     * the handler itself is the caller in this context.
     */
    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 1, maxCollateralToRedeem);

        if (amountCollateral == 0) {
            return;
        }

        engine.redeemCollateral(address(collateral), amountCollateral);
    }

    /**
     * @notice Function that returns either a weth or wbtc ERC20 Mock contract depending
     * on the collateral seed that gets passed.
     * @param collateralSeed The seed that gets passed to the function.
     * @return ERC20Mock Returns weth if the seed is even, wbtc if the seed is odd.
     */
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

    /* Getter functions */
    /**
     * @notice This function exposes the array of users that have deposited collateral.
     * @return address[] The array of addresses that have deposited collateral.
     */
    function getUsersWithCollateralDeposited() external view returns (address[] memory) {
        return usersWithCollateralDeposited;
    }
}
