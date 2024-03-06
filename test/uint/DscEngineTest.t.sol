// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDsc} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DscEngineTest is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    DeployDsc public deployer;
    HelperConfig public helperConfig;
    address public ethPriceFeed;
    address public btcPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public AMOUNT_CALLATERAL = 10 ether;
    uint256 public STARTING_ERC20_BALANCE = 10 ether;

    address public USER = makeAddr("user");

    function setUp() public {
        deployer = new DeployDsc();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (weth, wbtc, ethPriceFeed, btcPriceFeed,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, AMOUNT_CALLATERAL);
    }

    address[] public tokenAddress;
    address[] public priceFeedAddress;

    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddress.push(weth);
        priceFeedAddress.push(ethPriceFeed);
        priceFeedAddress.push(btcPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesLengthAndPriceFeedAddressesLengthNotSame.selector);
        new DSCEngine(tokenAddress, priceFeedAddress, address(dsc));
    }

    function testGetAmountCollateralToCoverDebtInWei() public {
        uint256 usd = 100 ether;
        uint256 expectedAmount = 0.05 ether;
        uint256 amountCollateral = dscEngine.getAmountCollateralToCoverDebtInWei(weth, usd);
        assert(expectedAmount == amountCollateral);
    }

    function testGetUsdValueWeth() public {
        uint256 amount = 15e18;
        uint256 expectedPrice = 2000 * 15e18;
        console.log("Expected price: ", expectedPrice);
        uint256 valueInUsd = dscEngine.getUsdValue(weth, amount);
        assert(expectedPrice == valueInUsd);
    }

    function testGetUsdValueWBtcAndWEth() public {
        uint256 amount = 15e18;
        uint256 expectedPriceEth = 2000 * 15e18;
        uint256 expectedPriceBtc = 6000 * 15e18;
        console.log("Expected price: ", expectedPriceEth);
        console.log("Expected price: ", expectedPriceBtc);
        uint256 valueInUsdEth = dscEngine.getUsdValue(weth, amount);
        uint256 valueInUsdBtc = dscEngine.getUsdValue(wbtc, amount);
        assert(expectedPriceEth == valueInUsdEth);
        assert(valueInUsdBtc == expectedPriceBtc);
    }

    function testGetUsdValueWBtcAndWEthEq0() public {
        uint256 amount = 0;
        uint256 expectedPriceEth = 2000 * amount;
        uint256 expectedPriceBtc = 6000 * amount;
        console.log("Expected price: ", expectedPriceEth);
        console.log("Expected price: ", expectedPriceBtc);
        uint256 valueInUsdEth = dscEngine.getUsdValue(weth, amount);
        uint256 valueInUsdBtc = dscEngine.getUsdValue(wbtc, amount);
        assert(expectedPriceEth == valueInUsdEth);
        assert(valueInUsdBtc == expectedPriceBtc);
    }

    function testRevertCollateralZero() public {
        vm.prank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_CALLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock qqToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowToken.selector);
        dscEngine.depositCollateral(address(qqToken), AMOUNT_CALLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_CALLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_CALLATERAL);
        vm.stopPrank();
        _;
    }

    function testGetAccountInformation() public depositedCollateral {
        uint256 expectedDsc = 0;
        (uint256 dscM, uint256 debt) = dscEngine.getAccountInformation(USER);
        uint256 expectedDebt = dscEngine.getAmountCollateralToCoverDebtInWei(weth, debt);
        console.log("Debt: ", debt);
        console.log("Expected debt: ", expectedDebt);
        assert(dscM == expectedDsc);
        assert(20000 * 1e18 == debt);
        assert(expectedDebt == 10 ether);
    }
}
