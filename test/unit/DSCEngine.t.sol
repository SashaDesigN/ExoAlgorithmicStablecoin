// SPDX-License-Identifier: MIT
// 1. Pragma
pragma solidity ^0.8.24;

import {Test} from 'forge-std/Test.sol';
import {DesployDSCStableCoin} from '../../script/DeployDSC.s.sol';
import {HelperConfig} from '../../script/HelperConfig.s.sol';
import {DSCEngine} from '../../src/DSCEngine.sol';
import {DecentraliseStableCoin} from '../../src/DecentraliseStableCoin.sol';
import {ERC20Mock} from '../mocks/ERC20Mock.sol';

contract DSCEngineTest is Test {
    // mirror the engine event so we can use it in expectEmit
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    DesployDSCStableCoin public deployer;
    DSCEngine public engine;
    DecentraliseStableCoin public coin;
    HelperConfig public config;

    uint256 public constant COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant STARTING_BALANCE = 10 ether;
    uint256 public constant MINT_AMOUNT = 1e18; // 1 DSC

    address weth;
    address wbtc;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;

    address bob = makeAddr('bob');
    address alice = makeAddr('alice');

    function setUp() public {
        deployer = new DesployDSCStableCoin();
        (coin, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(bob, STARTING_BALANCE);
        ERC20Mock(wbtc).mint(bob, STARTING_BALANCE);
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    function testConstructorRevertsOnTokenFeedLengthMismatch() public {
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](2);
        tokens[0] = weth;
        feeds[0] = ethUsdPriceFeed;
        feeds[1] = btcUsdPriceFeed;

        vm.expectRevert(DSCEngine.DSCEngine_TokenAddressesAndFeedsAddressesMustBeSameLength.selector);
        new DSCEngine(tokens, feeds, address(coin));
    }

    // -----------------------------------------------------------------------
    // Price feeds
    // -----------------------------------------------------------------------

    function testPriceInUSDIsCorrect() public view {
        uint256 amount = 15e18;
        uint256 extectedUSD = 30_000e18; // mock ETH = $2000
        uint256 actualUSD = engine.getUsdValue(weth, amount);
        assertEq(extectedUSD, actualUSD);
    }

    function testGetUsdValueWbtc() public view {
        uint256 amount = 1e18;
        uint256 expectedUSD = 1_000e18; // mock BTC = $1000
        assertEq(engine.getUsdValue(wbtc, amount), expectedUSD);
    }

    // -----------------------------------------------------------------------
    // depositCollateral
    // -----------------------------------------------------------------------

    function testDepozitWithZeroAmount() public {
        vm.startPrank(bob);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine_MustBeNonZeroAmount.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testDepositRevertsOnNotAllowedToken() public {
        ERC20Mock randomToken = new ERC20Mock("RND", "RND", bob, STARTING_BALANCE);
        vm.startPrank(bob);
        vm.expectRevert(DSCEngine.DSCEngine_TokenNotAllowed.selector);
        engine.depositCollateral(address(randomToken), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testDepositUpdatesCollateralRecord() public {
        vm.startPrank(bob);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();

        // 10 ETH at $2000 = $20 000
        assertEq(engine.getAccountCollateralValue(bob), 20_000e18);
    }

    function testDepositEmitsEvent() public {
        vm.startPrank(bob);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        vm.expectEmit(true, true, false, true, address(engine));
        emit CollateralDeposited(bob, weth, COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testDepositTransfersTokensToEngine() public {
        vm.startPrank(bob);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();

        assertEq(ERC20Mock(weth).balanceOf(address(engine)), COLLATERAL_AMOUNT);
        assertEq(ERC20Mock(weth).balanceOf(bob), 0);
    }

    // -----------------------------------------------------------------------
    // mintDSC
    // -----------------------------------------------------------------------

    function testMintRevertsWithZeroAmount() public {
        vm.startPrank(bob);
        vm.expectRevert(DSCEngine.DSCEngine_MustBeNonZeroAmount.selector);
        engine.mintDSC(0);
        vm.stopPrank();
    }

    function testMintRevertsWithNoCollateral() public {
        // health factor = 0 when collateral = 0
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_HealthFactorReached.selector, 0));
        engine.mintDSC(MINT_AMOUNT);
        vm.stopPrank();
    }

    function testMintWorksAfterDeposit() public {
        vm.startPrank(bob);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);
        engine.mintDSC(MINT_AMOUNT);
        vm.stopPrank();

        assertEq(coin.balanceOf(bob), MINT_AMOUNT);
    }

    // -----------------------------------------------------------------------
    // getAccountCollateralValue
    // -----------------------------------------------------------------------

    function testAccountCollateralValueZeroForNewUser() public view {
        assertEq(engine.getAccountCollateralValue(alice), 0);
    }

    function testAccountCollateralValueMultipleDeposits() public {
        vm.startPrank(bob);
        ERC20Mock(weth).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(weth, COLLATERAL_AMOUNT);

        ERC20Mock(wbtc).approve(address(engine), COLLATERAL_AMOUNT);
        engine.depositCollateral(wbtc, COLLATERAL_AMOUNT);
        vm.stopPrank();

        // 10 ETH @ $2000 + 10 WBTC @ $1000 = $30 000
        assertEq(engine.getAccountCollateralValue(bob), 30_000e18);
    }
}