// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
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
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author ChenBaiYu
 * The system is designed to be as minimal as possible, and have the token maintain a 1 token == $1 peg.
 * this stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Peg
 * - Algoritically Stable
 *
 * It is similar to DAI had no governance, no fee, and was backed by WETH and WBTC
 *
 * @notice This contract is the core of the DSC System, it handle all the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS(DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    ////////////////
    //Errors      //
    ////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__NotAllowToken();
    error DSCEngine__TokenAddressesLengthAndPriceFeedAddressesLengthNotSame();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFacotr();
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFacotrOK();
    error DSCEngine__HealthFacotrNotImproved();

    ////////////////////
    //State Variables //
    ////////////////////
    uint256 private constant LIQUIDATION_THREHOLD = 50; //this mean you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposted;
    mapping(address user => uint256 token) private s_minted;
    address[] private s_collateralToken;

    DecentralizedStableCoin private immutable i_dsc;

    ////////////////
    //Events      //
    ////////////////
    event CollateralDeposted(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    ////////////////
    //Modifier    //
    ////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowToken();
        }
        _;
    }

    ////////////////
    //Funtions    //
    ////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesLengthAndPriceFeedAddressesLengthNotSame();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralToken.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountCollateral The amout of token to deposit as collateral.
     * @param dscAmountToMint The amount of DSC to mint.
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 dscAmountToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(dscAmountToMint);
    }

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountCollateral The amout of token to deposit as collateral.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposted[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposted(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     *
     * @param tokenCollateralAddress The collateral address to redeem.
     * @param amountCollateral  The amount of collateral to redeem.
     * @param dscAmountToBurn  The amount of DSC to burn.
     * @notice This function is used to burn DSC and redeem collateral.
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 dscAmountToBurn)
        external
        moreThanZero(amountCollateral)
    {
        burnDsc(dscAmountToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        //redeemCollateral already checks if health factor is broken
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposted[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintDsc(uint256 dscAmountToMint) public moreThanZero(dscAmountToMint) nonReentrant {
        s_minted[msg.sender] += dscAmountToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, dscAmountToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 dscAmountToBurn) public moreThanZero(dscAmountToBurn) nonReentrant {
        s_minted[msg.sender] -= dscAmountToBurn;
        bool success = i_dsc.transferFrom(msg.sender, address(this), dscAmountToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(dscAmountToBurn);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would be hit
    }

    /**
     * @notice This function is used to liquidate a user's position.
     */
    function liquidate(address tokenCollateralAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFacotrOK();
        }

        uint256 amountCollateralToCoverDebt = getAmountCollateralToCoverDebtInWei(tokenCollateralAddress, debtToCover);

        uint256 bonusCollateral = amountCollateralToCoverDebt * LIQUIDATION_BONUS / LIQUIDATION_PRECISION;

        uint256 totalCollateral = amountCollateralToCoverDebt + bonusCollateral;

        _redeemCollateral(tokenCollateralAddress, totalCollateral, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFacotrNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    /////////////////////////////////
    //Internal Private Funtions    //
    /////////////////////////////////
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposted[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDsc(uint256 dscAmountToBurn, address DscFrom, address onBehalfOf) private {
        s_minted[onBehalfOf] -= dscAmountToBurn;
        bool success = i_dsc.transferFrom(DscFrom, address(this), dscAmountToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(dscAmountToBurn);
    }

    function _getAccountInfomation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 totalUsdValueInCollateral)
    {
        totalDscMinted = s_minted[user];
        totalUsdValueInCollateral = getAccountCollateralValue(user);
    }

    /**
     * Return how close a user is to liquidation.
     * If health factor is less than 1, user can be liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 totalValueInCollateral) = _getAccountInfomation(user);
        uint256 collateralAjustForThrehold = (totalValueInCollateral * LIQUIDATION_THREHOLD) / LIQUIDATION_PRECISION;
        return (collateralAjustForThrehold * PRECISION) / totalDscMinted;
    }

    /**
     * Check if health factor of the user if it is below the liquidation threhold
     * revert if it is
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFacotr();
        }
    }

    /////////////////////////////////
    //External&Public View&Pure Funtions    //
    /////////////////////////////////
    function getAmountCollateralToCoverDebtInWei(address tokenCollateralAddress, uint256 weiDebt)
        public
        view
        returns (uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenCollateralAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (weiDebt * 1e18) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalValueInCollateral) {
        for (uint256 i = 0; i < s_collateralToken.length; i++) {
            address token = s_collateralToken[i];
            uint256 amount = s_collateralDeposted[user][token];
            totalValueInCollateral += getUsdValue(token, amount);
        }
    }

    /**
     *
     * @param token  Collateral token address
     * @param amount The amount of token in wei
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 totalValueInCollateral)
    {
        return _getAccountInfomation(user);
    }
}
