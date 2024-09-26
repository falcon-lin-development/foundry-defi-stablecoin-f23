// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;
// Have our invariants

// What are our invariants?
// 1. The total supply of DSC should be less than total value of collateral

// 2. Getter view functions should never revert <= evergreen invariant

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCDeployScript} from "../../script/DSC.deploy.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DSCDeployScript deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DSCDeployScript();
        (dsc, engine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        // targetContract(address(engine));
        handler = new Handler(engine, dsc);
        targetContract(address(handler));
        // don't call redeemCollateral unless there's collateral to redeem

    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get the value of all the collateral in the protocol
        // compare it to all the debt (dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalBtcDeposited);


        console.log("wethValue: ", wethValue);
        console.log("wbtcValue: ", wbtcValue);
        console.log("totalSupply: ", totalSupply);
        console.log("timesMintIsCalled: ", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        /**
         * 
         * "getAccountCollateralValue(address)": "7d1a4450",
            "getAccountInformation(address)": "7be564fc",
            "getCollateralBalanceOfUser(address,address)": "31e92b83",
            "getCollateralTokens()": "b58eb63f",
            "getLiquidationThreshold()": "4ae9b8bc",
            "getTokenAmountFromUsd(address,uint256)": "afea2e48",
            "getUsdValue(address,uint256)": "c660d112",
            "getUserHealthFactor(address)": "71cbfc98",
         */
        engine.getAccountInformation(address(this));
        engine.getCollateralBalanceOfUser(address(this), address(weth));
        engine.getCollateralTokens();
        engine.getLiquidationThreshold();
        engine.getTokenAmountFromUsd(address(weth), 1e18);
        engine.getUsdValue(address(weth), 1e18);
        engine.getUserHealthFactor(address(this));
    }
}
