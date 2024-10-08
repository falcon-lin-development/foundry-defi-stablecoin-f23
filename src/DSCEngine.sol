// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./library/OracleLib.sol";
import {console} from "forge-std/console.sol";
/**
 * @title DSC Engine
 * @author  Falcon Lin
 *
 * The system is design to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no goverance, no fees, and was only backed by WTH and WBTC.
 *
 * Our DSC system should always be "over-collateralized". At no point, should the value of all collateral <= the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the DSC System. It handles all the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    /////////////////////////
    // Errors              //
    /////////////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsGood();
    error DSCEngine__HealthFactorNotImproved();


    /////////////////////////
    // Type Declarations   //
    /////////////////////////
    using OracleLib for AggregatorV3Interface;

    //////////////////////////////////
    // State Variables              //
    //////////////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    // maximum possible number for health factor
    uint256 private constant MAX_HEALTH_FACTOR = type(uint256).max;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus liquidation
    uint256 private constant LIQUIDATION_PRECISION = 100;
    // $150 ETH / 100 DSC = 1.5

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    //////////////////////////////////
    // Event                        //
    //////////////////////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    /////////////////////////
    // Modifiers           //
    /////////////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /////////////////////////
    // Functions           //
    /////////////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // For example ETH / USD, BTC / USD, MKR / USD, etc
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
        s_collateralTokens = tokenAddresses;
    }

    //////////////////////////////////
    // External Functions           //
    //////////////////////////////////

    /**
     * @notice Follows CEI pattern
     * @notice This function is used to deposit collateral and mint DSC in a single transaction
     * @param tokenCollateralAddress : address of the token to be deposited as collateral
     * @param amountCollateral : amount of the token to be deposited as collateral
     * @param amountDscToMint : amount of decentralized stable coin to mint
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice follows CEI
     * @param tokenCollaterlAddress : address of the token to be deposited as collateral
     * @param amountCollateral : amount of the token to be deposited as collateral
     */
    function depositCollateral(address tokenCollaterlAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollaterlAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollaterlAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollaterlAddress, amountCollateral);

        bool success = IERC20(tokenCollaterlAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress : The collateral token to redeem
     * @param amountCollateral : The amount of collateral to redeem
     * @param amountDscToBurn : The amount of DSC to burn
     * This function burns DSC and redeems collateral in a single transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // CEI: Checks, Effects, Interactions
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @param amountDscToMint: The amount of decentralized stable coin to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // if they mintied too much ($150, $100ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) nonReentrant {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...
    }

    /**
     * @notice This function is used to liquidate undercollateralized positions
     * @param collateralTokenAddress The address of the collateral token
     * @param userToBeLiquidated The user who has broken the health factor. Their _healthFactor is below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC to burn
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized for this to work
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentivise the liquidators.
     * for example, if the price of the collateral plummeted before anyone could be liquidated.
     *
     * Follow CEI, Checks, Effects, Interactions
     */
    function liquidate(address collateralTokenAddress, address userToBeLiquidated, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // check health factor of user to be liquidated
        uint256 startingUserHealthFactor = _healthFactor(userToBeLiquidated);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsGood();
        }
        // we want to burn their "DSC debt"
        // and take their collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralTokenAddress, debtToCover);
        // And give them a 10% bonus
        // So we are giving the liquidator a 10% bonus for taking over the position
        // We should implement a feature to liquidate in the event the protocol is insolent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(userToBeLiquidated, msg.sender, collateralTokenAddress, totalCollateralToRedeem);

        // burn their DSC
        _burnDsc(debtToCover, userToBeLiquidated, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(userToBeLiquidated);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //////////////////////////////////////////////
    // Privat Internal View Functions           //
    //////////////////////////////////////////////

    /**
     * @dev Low-level internal function, do not call unless the function
     * calling it is checking for health factors begin broken
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        // health factor must be greater than 1 after redeeming
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        // _calculateHealthFactorAfter();
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsed)
    {
        // total DSC minted
        totalDscMinted = s_DSCMinted[user];
        // totla collateral value
        collateralValueInUsed = getAccountCollateralValue(user);
    }

    /**
     * Returns how close to liquidation a user is
     * if a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total DSC minted
        // totla collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUsed) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsed * LIQUIDATION_THRESHOLD) / 100;

        // if the totalDscMinted is 0, then we can return MAX_HEALTH_FACTOR
        if (totalDscMinted == 0) {
            return MAX_HEALTH_FACTOR;
        }

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) private view {
        // 1. Check health factor (do they have enough collateral?)
        uint256 userHealthFactor = _healthFactor(user);

        // 2. Revert if they don't
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    //////////////////////////////////////////////////
    // Public and External View Functions           //
    //////////////////////////////////////////////////

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / ((uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have deposited, and map it to
        // the price, to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];

            totalCollateralValueInUsd += getUsdValue(token, amount);
            // amount * price
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);

        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        // 1 ETH = $1000
        // The returned value from CL = 1000*1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; // (1000 * 1e8 ) * 1000 * 1e18
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsed)
    {
        (totalDscMinted, collateralValueInUsed) = _getAccountInformation(user);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getUserHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
}
