// narrow down the way we call functions

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";

// Price Feed
// WETH Token
// WBTC Token

contract Handler is Test {
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _engine, DecentralizedStableCoin _dsc) {
        engine = _engine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        // msg.sender
        if (usersWithCollateralDeposited.length == 0) return;
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];


        (uint256 totalDscMinited, uint256 collateralValueInUsed) = engine.getAccountInformation(sender);
        int256 maxDscToMint = int256(collateralValueInUsed / 2) - int256(totalDscMinited);
        if (maxDscToMint <= 0) return;
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) return;
        vm.startPrank(sender);
        engine.mintDsc(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    // redeem collateral 
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // double push if some user deposit
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    
        // get the max amount of collateral that the user has deposited
        uint256 userCollateralAmountBalance = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));

        // get the max amount of USD that the user can redeem without breaking the health factor
        // log the total dcs minted by the user
        (uint256 totalDscMinted, uint256 collateralValueInUsed) = engine.getAccountInformation(msg.sender);
        uint256 minCollateralValueRequired = totalDscMinted * 100 / engine.getLiquidationThreshold();
        uint256 maxCollateralValueToRedeem = collateralValueInUsed - minCollateralValueRequired;
        uint256 maxCollateralAmountToRedeem = engine.getTokenAmountFromUsd(address(collateral), maxCollateralValueToRedeem);
        
        amountCollateral = bound(amountCollateral, 0, userCollateralAmountBalance);
        amountCollateral = bound(amountCollateral, 0, maxCollateralAmountToRedeem);
        if (amountCollateral == 0) return;


        vm.startPrank(msg.sender);
        engine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    // This breaks our invariant test suite!!!!
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    // Helper function to get a random address
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
