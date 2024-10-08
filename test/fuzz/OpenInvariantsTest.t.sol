// // SPDX-License-Identifier: SEE LICENSE IN LICENSE
// pragma solidity ^0.8.18;
// // Have our invariants

// // What are our invariants?
// // 1. The total supply of DSC should be less than total value of collateral

// // 2. Getter view functions should never revert <= evergreen invariant

// import {Test, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DSCDeployScript} from "../../script/DSC.deploy.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

// contract OpenInvariantsTest is StdInvariant, Test {
//     DSCDeployScript deployer;
//     DSCEngine engine;
//     DecentralizedStableCoin dsc;
//     HelperConfig config;
//     address weth;
//     address wbtc;

//     function setUp() external {
//         deployer = new DSCDeployScript();
//         (dsc, engine, config) = deployer.run();
//         (,, weth, wbtc,) = config.activeNetworkConfig();
//         console.log("engine address: ", address(engine));
//         targetContract(address(engine));

//     }

//     function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
//         // get the value of all the collateral in the protocol
//         // compare it to all the debt (dsc)
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
//         uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(engine));

//         uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
//         uint256 wbtcValue = engine.getUsdValue(wbtc, totalBtcDeposited);

//         assert(wethValue + wbtcValue >= totalSupply);
//     }


// }
