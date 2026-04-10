// SPDX-License-Identifier: MIT
// 1. Pragma
pragma solidity ^0.8.24;

import {Test} from 'forge-std/Test.sol';
import {DesployDSCStableCoin} from '../../script/DeployDSC.s.sol';
import {HelperConfig} from '../../script/HelperConfig.s.sol';
import { DSCEngine } from '../../src/DSCEngine.sol';
import { DecentraliseStableCoin } from '../../src/DecentraliseStableCoin.sol';
import {ERC20Mock} from '../mocks/ERC20Mock.sol';

contract DSCEngineTest is Test {
    
    DesployDSCStableCoin public deployer;
    DSCEngine public engine;
    DecentraliseStableCoin public coin;
    HelperConfig public config;
    uint256 public constant COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant STARTING_BALANCE = 10 ether;
    
    address weth;
    address ethUsdPriceFeed;

    address bob = makeAddr('bob');
    address alice = makeAddr('alice');

    function setUp() public {
        deployer = new DesployDSCStableCoin();
        (coin, engine, config) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(bob, STARTING_BALANCE);
    }

    ///////////////////
    // Price testing //
    ///////////////////
    function testPriceInUSDIsCorrect () public view {
        uint256 amount = 15e18;
        uint256 extectedUSD = 30000e18;
        uint256 actualUSD = engine.getUsdValue(weth, amount);   
        assertEq(extectedUSD, actualUSD);
    }

    function testDepozitWithZeroAmount () public {
        vm.startPrank(bob);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine_MustBeNonZeroAmount.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }
}