// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script} from 'forge-std/Script.sol';
import {DecentraliseStableCoin} from "../src/DecentraliseStableCoin.sol";
import {DSCEngine} from '../src/DSCEngine.sol';
import {HelperConfig} from './HelperConfig.s.sol';

contract DesployDSCStableCoin is Script {

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run () external returns (DecentraliseStableCoin, DSCEngine) {
        HelperConfig config = new HelperConfig();
        
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentraliseStableCoin stablecoin = new DecentraliseStableCoin();

        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, stablecoin);
        stablecoin.transferOwnershit(address(engine));

        vm.stopBroadcast();

        return (stablecoin, engine);
    }

}