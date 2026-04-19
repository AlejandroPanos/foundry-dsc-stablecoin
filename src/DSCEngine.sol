// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "src/libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Alejandro Paños
 *
 * The system is designed to be as minimal as possible and it is built in a way
 * that the token always has the value of 1USD pegged to it.
 *
 * The token has the following characteristics:
 * 1. Exogenously collateralised
 * 2. Pegged to the value of the USD
 * 3. Is fully algorithmic
 *
 * @notice The system is always overcollateralised — the value of all collateral must
 * always exceed the total value of DSC in circulation.
 * @dev This contract is the core of the implementation of the DeFi protocol. It controls
 * everything from minting, depositing, liquidating, etc.
 */

contract DSCEngine is ReentrancyGuard {
    /* ============================================================ */
    /* Libraries                                                    */
    /* ============================================================ */
    using OracleLib for AggregatorV3Interface;

    /* ============================================================ */
    /* Errors                                                       */
    /* ============================================================ */
    error DSCEngine__AddressesMustBeOfSameLength();
    error DSCEngine__AmountShouldBeMoreThanZero();
    error DSCEngine__PriceFeedNotAllowed();
    error DSCEngine__ERC20TransferFailed();

    /* ============================================================ */
    /* State variables                                              */
    /* ============================================================ */
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    /**
     * @dev Mapping to keep track of a token's price feed address.
     */
    mapping(address token => address priceFeed) private s_tokenToPriceFeed;

    /**
     * @dev Mapping to keep track of the amount of collateral
     * deposited by a specific user.
     */
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralAmount;

    /**
     * @dev Mapping to track the amount of DSC minted by a user.
     */
    mapping(address user => uint256 amountDSCMinted) private s_amountMinted;

    /**
     * @dev Array to push the addresses of the tokens that can be used as collateral.
     */
    address[] private s_collateralTokens;

    DecentralisedStableCoin private immutable i_dsc;

    /* ============================================================ */
    /* Events                                                       */
    /* ============================================================ */
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    /* ============================================================ */
    /* Modifiers                                                    */
    /* ============================================================ */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__AmountShouldBeMoreThanZero();
        }
        _;
    }

    modifier tokenAllowed(address token) {
        if (s_tokenToPriceFeed[token] == address(0)) {
            revert DSCEngine__PriceFeedNotAllowed();
        }
        _;
    }

    /* ============================================================ */
    /* Constructor                                                  */
    /* ============================================================ */
    /**
     * @dev Constructor takes the token addresses which will be the WETH and WBTC
     * addresses for this specific implementation, although more could be added
     * dynamically thanks to the array implementation here.
     * @dev Constructor takes the price feed addresses for the specified tokens. In
     * this case the price feed addresses will be those of ETH-USD and BTC-USD.
     * @dev Constructor takes in the deployed DSC contract address.
     * @notice The token addresses and the price feed addresses must be of same length.
     */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dsc) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__AddressesMustBeOfSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_tokenToPriceFeed[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralisedStableCoin(dsc);
    }

    /* Functions */
    /**
     * @notice Deposits collateral into the engine to back DSC minting
     * @dev This funciton deposits collateral in the engine contract. The collateral
     * will be locked in the engine contract until the collateral is redeemed.
     * @dev Uses the nonReentrant modifier from the ReentrancyGuard.sol contract
     * imported from the OpenZeppelin contract library.
     * @param tokenAddress The address of the token used as collateral.
     * @param collateralAmount The amount of collateral deposited.
     */
    function depositCollateral(address tokenAddress, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        tokenAllowed(tokenAddress)
        nonReentrant
    {
        s_collateralAmount[msg.sender][tokenAddress] += collateralAmount;
        emit CollateralDeposited(msg.sender, tokenAddress, collateralAmount);

        bool success = IERC20(tokenAddress).transferFrom(msg.sender, address(this), collateralAmount);
        if (!success) {
            revert DSCEngine__ERC20TransferFailed();
        }
    }

    function mintDsc() public {}

    function depositCollateralAndMint() public {}

    function redeemCollateral() public {}

    function burnDsc() public {}

    function redeemCollateralForDsc() public {}

    function liquidate() public {}

    /* Internal functions */
    function _revertIfHealthFactorIsBroken() internal {}
}
