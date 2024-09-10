// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

import {console} from "forge-std/Console.sol";

contract DSCDeployScript is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        address deployerAddress = vm.addr(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin(deployerAddress);
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        // console.log("Logging contract addresses and owners:");
        // console.log("Deployer Address:", 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, deployerAddress);
        // console.log("Deployer key:", deployerKey);
        // console.log("This address:", address(this));
        // console.log("DSC address:", address(dsc));
        // console.log("DSC owner:", dsc.owner());
        // console.log("Engine address:", address(engine));

        dsc.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (dsc, engine, config);
    }
}