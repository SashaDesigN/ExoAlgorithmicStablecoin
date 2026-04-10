// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DecentraliseStableCoin} from "./DecentraliseStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {AggregatorV3Interface} from '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';

/*
* @title DSCEngine
* @author AlexBerg
* Collateral: Exogenous (wETH & wBTC)
* Minting: Algorithmic
* Relative Stability: Pegged to USD
*
* This is the contract meant to be governed by DSCEngine.
* System is created to be simple, 1 token = $1 peged
* @notice: it's similar to DAI, but without governance, fees and only backed by WETH & WBTC
* @notice: DSC should be always over-collateralazed. Should no be point when all collateral $ value is <= backend $ amount of collateral provided
* @notice: this contract handing all stablecoin logic: calling of minting & redeeming tokens, depositing/withdrewals collateral.
*/
contract DSCEngine is ReentrancyGuard {
    //is Ownable {

    ////////////
    // errors //
    ////////////
    error DSCEngine_MustBeNonZeroAmount();
    error DSCEngine_TokenAddressesAndFeedsAddressesMustBeSameLength();
    error DSCEngine_TokenNotAllowed();
    error DSCEngine_TransferFail();
    error DSCEngine_HealthFactorReached(uint256 healthFactor);
    error DSCEngine_MintFail();

    ///////////
    // state //
    ///////////
    mapping(address token => address priceFeed) private s_priceFeeds; // token to it price feed mapping

    mapping(address user => mapping(address token => uint256 amount)) private s_deposits;

    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;

    DecentraliseStableCoin private immutable i_dsc;

    address[] private s_collateralTokensList;

    uint256 private constant DECIMALS_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_TREESHOLD = 50;
    uint256 private constant MIN_HEALTH_FACTOR = 1;


    ////////////
    // events //
    ////////////
    event CollateralDeposited (address indexed user, address indexed token, uint256 amount);


    ///////////////
    // modifiers //
    ///////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine_MustBeNonZeroAmount();
        }
        _;
    }

    modifier isTokenAllowed(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine_TokenNotAllowed();
        }
        _;
    }

    ///////////////
    // functions //
    ///////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine_TokenAddressesAndFeedsAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokensList.push(tokenAddresses[i]);
        }

        i_dsc = DecentraliseStableCoin(dscAddress);
    }

    // (address ownerAddress) Ownable (ownerAddress) {

    ////////////////////////
    // External functions //
    ////////////////////////

    function depositCollateral(address tokenAddress, uint256 tokenAmount)
        external
        nonReentrant
        moreThanZero(tokenAmount)
        isTokenAllowed(tokenAddress)
    {
        s_deposits[msg.sender][tokenAddress] += tokenAmount;
        emit CollateralDeposited(msg.sender, tokenAddress, tokenAmount);
        bool success = IERC20(tokenAddress).transferFrom(msg.sender, address(this), tokenAmount);

        if (!success) {
            revert DSCEngine_TransferFail();
        }
    }

    function depositCollateralAndMintDSC() external {}
    function redeemCollateral() external {}
    function redeemCollateralForDSC() external {}
    function burnDSC() external {}
    
    function mintDSC(uint256 amount) 
        external 
        moreThanZero(amount)
        nonReentrant
    {
        s_DSCMinted[msg.sender] += amount;
        _revertIfHealthFactorBroken(msg.sender);
        bool minted = i_dcs.mint(msg.sender, amount);

        if (!minted) {
            revert DSCEngine_MintFail();
        }
    }

    function liquidate() external {}
    function getHealthFactor(address userAddress) external view {}


    //////////////////////////////////
    // Private & internal functions //
    //////////////////////////////////
    function _getUserCollateralInfo(address user) private view returns (uint256 totalDSCMinted, uint256 collateralUSDValue) {
        totalDSCMinted = s_DSCMinted[user];
        collateralUSDValue = getAccountCollateralValue(user);
        return (totalDSCMinted, collateralUSDValue);
    }

    // IF < 1 - going to be liquidated (atm require double overcollaterisation)
    function _healthFactor(address user) private view returns(uint256 healthFactorValue) {
        (uint256 totalDSCMinted, uint256 collateralUSDValue) = _getUserCollateralInfo(user);
        uint256 collateralTreeshold = (collateralUSDValue * LIQUIDATION_TREESHOLD) / 100;
        return (collateralTreeshold * PRECISION) / totalDSCMinted;
    }

    function _revertIfHealthFactorBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);

        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine_HealthFactorReached(healthFactor);
        }

    }


    /////////////////////////
    // Public and external //
    /////////////////////////
    
    function getAccountCollateralValue (address user) public view returns (uint256 amount) {
         for (uint256 i = 0; i < s_collateralTokensList.length; i++) {
            address token = s_collateralTokensList[i];
            uint256 deposited = s_deposits[user][token];
            amount += getUsdValue(token, deposited);
        }

        return amount;
    } 

    function getUsdValue (address token, uint256 amount) public view returns (uint256 usdValue) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(uint256(price) * DECIMALS_PRECISION) * amount) / PRECISION;
    }
}