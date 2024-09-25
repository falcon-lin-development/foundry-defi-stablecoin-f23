// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DSCDeployScript} from "script/DSC.deploy.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {console} from "forge-std/console.sol";

contract DSCEngineTest is Test {
    DSCDeployScript deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address wethUsdPriceFeed;
    address weth;
    address wbtcUsdPriceFeed;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant TARGETED_MINT_DSC_BALANCE = 1_000 ether; // = 10/2*2000 /10 
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;


    function setUp() public {
        deployer = new DSCDeployScript();
        (dsc, engine, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
    }

    //////////////////
    // Test Section //
    //////////////////
    function testDeploy() public view {
        assertEq(address(dsc.owner()), address(engine));
    }

    function testSetUpCorrectlyDepositERC20ToUser() public view {
        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(userBalance, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    // Constructor Section //
    ///////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ///////////////////
    // Price Section //
    ///////////////////
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18
        uint256 expectedUsd = 30_000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        // $2,000 / ETH = 100/2000 = 0.05 ETH
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    //////////////////////////////////////
    // depositCollateral Section        //
    //////////////////////////////////////
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock();
        randomToken.mint(USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        uint256 expectedToDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedToDscMinted);
        assertNotEq(collateralValueInUsd, 0);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testDepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 5000e18);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, 5000e18);
        assertEq(collateralValueInUsd, AMOUNT_COLLATERAL * 2000); // Assuming 1 ETH = $2000
    }

    function testRedeemCollateralForDsc() public {
        // First, deposit collateral and mint DSC
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 5000e18);

        // Now redeem collateral for DSC
        dsc.approve(address(engine), 2500e18);
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL / 2, 2500e18);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, 2500e18);
        assertEq(collateralValueInUsd, (AMOUNT_COLLATERAL / 2) * 2000);
    }

    function testRedeemCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);

        uint256 balanceBefore = ERC20Mock(weth).balanceOf(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL / 2);
        uint256 balanceAfter = ERC20Mock(weth).balanceOf(USER);
        vm.stopPrank();

        assertEq(balanceAfter - balanceBefore, AMOUNT_COLLATERAL / 2);
    }

    function testMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDsc(5000e18);
        vm.stopPrank();

        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, 5000e18);
    }

    function testBurnDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 5000e18);

        dsc.approve(address(engine), 2500e18);
        engine.burnDsc(2500e18);
        vm.stopPrank();

        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, 2500e18);
    }

    function testLiquidate() public {
        // Setup: USER deposits collateral and mints DSC
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 7500e18); // 75% collateralization
        vm.stopPrank();

        // Setup: LIQUIDATOR gets some DSC
        address LIQUIDATOR = makeAddr("liquidator");
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).mint(LIQUIDATOR, AMOUNT_COLLATERAL*2);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL*2);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL*2, 7500e18);
        vm.stopPrank();

        // Simulate price drop
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(1000e8); // 1 ETH = $1000

        // Liquidate
        vm.startPrank(LIQUIDATOR);
        dsc.approve(address(engine), 7500e18);
        engine.liquidate(weth, USER, 7500e18);
        vm.stopPrank();

        // Check results
        (uint256 userDscMinted,) = engine.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }

    // Write Tests 
    function testHealthFactor() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, TARGETED_MINT_DSC_BALANCE);
        vm.stopPrank();

        uint256 healthFactor = engine.getUserHealthFactor(USER);
        assertEq(healthFactor, 10e18);

        // test other health factor
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL / 2);
        vm.stopPrank();

        healthFactor = engine.getUserHealthFactor(USER);
        assertEq(healthFactor, 5e18);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        
        uint256 collateralValue = engine.getAccountCollateralValue(USER);
        assertEq(collateralValue, AMOUNT_COLLATERAL * 2000);

        // Add WBTC collateral and check again
        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(wbtc, AMOUNT_COLLATERAL);
        vm.stopPrank();

        collateralValue = engine.getAccountCollateralValue(USER);
        assertEq(collateralValue, AMOUNT_COLLATERAL * 2000 + AMOUNT_COLLATERAL * 3000);
    }
}