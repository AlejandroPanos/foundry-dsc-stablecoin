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
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorBelowMinimum();

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
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

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

    /* ============================================================ */
    /* External and public functions                                */
    /* ============================================================ */
    /**
     * @notice Deposits collateral into the engine to back DSC minting
     * @dev This function deposits collateral in the engine contract. The collateral
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

    /**
     * @notice This function mints a specific amount of DSC token to a user.
     * @dev Calls the internal _revertIfHealthFactorIsBroken() function which
     * reverts with a custom error if the health factor of the user is broken.
     * @dev Calls the nonReentrant modifier from ReentranctyGuard.sol
     * @param amount The amount of DSC token to mint.
     */
    function mintDsc(uint256 amount) public moreThanZero(amount) nonReentrant {
        s_amountMinted[msg.sender] += amount;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amount);

        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * @notice External function that allows a user to deposit collateral and
     * mint DSC tokens all at once.
     * @dev Calls the depositCollateral() and mintDsc() function from this engine.
     * @param tokenAddress The address of the token used as collateral.
     * @param collateralAmount The amount of collateral deposited.
     * @param amount The amount of DSC token to mint.
     */
    function depositCollateralAndMint(address tokenAddress, uint256 collateralAmount, uint256 amount) external {
        depositCollateral(tokenAddress, collateralAmount);
        mintDsc(amount);
    }

    /**
     * @notice This function is called when the liquidating user is
     * the same as the liquidator. This means that one user liquidates
     * its own position in the protocol.
     * @dev Uses the nonReentrant modifier from ReentrancyGuard.sol
     * @dev Calls the private _redeemCollateral() function.
     * @dev Calls the internal _revertIfHealthFactorIsBroken() function.
     * @param token The address of the token used as collateral.
     * @param amount The amount of collateral to redeem.
     */
    function redeemCollateral(address token, uint256 amount) public moreThanZero(amount) nonReentrant {
        _redeemCollateral(msg.sender, msg.sender, token, amount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc() public {}

    function redeemCollateralForDsc() public {}

    function liquidate() public {}

    /* ============================================================ */
    /* Internal and private functions                               */
    /* ============================================================ */
    /**
     * @notice Gets the following information about a specific user:
     * 1. The total amount minted.
     * 2. The value of the user's collateral in USD
     * @dev Calls the getCollateralInUsd() function to get the actual
     * amount of collateral translated into USD.
     * @param user The address of the user we want to check the information on.
     * @return uint256 The total amount of DSC minted by the user.
     * @return uint256 The collateral value in USD.
     */
    function _getAccountInformation(address user) private returns (uint256, uint256) {
        uint256 totalMinted = s_amountMinted[user];
        uint256 collateralValueInUsd = getCollateralInUsd(user);
        return (totalMinted, collateralValueInUsd);
    }

    /**
     * @notice This function returns the health factor of a specific user.
     * @dev This function is internal and only intended to be called by
     * functions within the engine contract.
     * @param user The user for which we want to check the health factor.
     * @return uint256 The health factor of the user.
     */
    function _healthFactor(address user) private returns (uint256) {
        (uint256 totalMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 adjustedCollateral = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (adjustedCollateral * PRECISION) / totalMinted;
    }

    /**
     * @notice This is a private function that redeems collateral.
     * @notice The user that liquidates and the liquidator can be the same
     * address. If someone liquidates another user's position, they will not
     * be the same address.
     * @param from The address that liquidates.
     * @param to The address of the liquidator.
     * @param token The token used as collateral.
     * @param amount The amount of token to redeem.
     */
    function _redeemCollateral(address from, address to, address token, uint256 amount) private {
        s_collateralAmount[from][token] -= amount;
        emit CollateralRedeemed(from, to, token, amount);
        bool success = IERC20(token).transfer(to, amount);
        if (!success) {
            revert DSCEngine__ERC20TranferFailed();
        }
    }

    /**
     * @notice Reverts with custom error is the health factor of the user
     * is broken. The health factor of a user is broken if the user is too close
     * to liquidation.
     * @param user The user for which we want to check the health factor.
     */
    function _revertIfHealthFactorIsBroken(address user) internal {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorBelowMinimum();
        }
    }

    /* Public functions */
    /**
     * @notice Function that allows anyone to calculate the value in USD of
     * a specific token and amount.
     * @dev Uses the OracleLib.sol library to check for stale data. It will revert
     * if the data returned is stale.
     * @dev Uses the AggregatorV3Interface from chainlink-evm.
     * @param token The address of the token to be checked.
     * @param amount The amount of token passed.
     * @return uint256 Returns the USD value of the amount of token passed.
     */
    function getUsdValue(address token, uint256 amount) public returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenToPriceFeed[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRound();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /**
     * @notice This function gets called to get the total amount of collateral
     * value in USD deposited by a specific user.
     * @dev Calls the getUsdValue() function to get the value in USD.
     * @param user The address of the user we want to get the USD collateral value for.
     * @return totalCollateralInUsd The total amount of collateral deposited by
     * the user in USD.
     */
    function getCollateralInUsd(address user) public returns (uint256 totalCollateralInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralAmount[user][token];
            totalCollateralInUsd += getUsdValue(token, amount);
        }

        return totalCollateralInUsd;
    }
}
