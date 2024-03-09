// SPDX-License-Identifier: MIT

//what are our invariants
// 1. the total supply of dsc should be less than the value of collateral
// 2. Getter view function should never revert

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDsc} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDsc public deployer;
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;
    Handler public handler;
    address public weth;
    address public wbtc;
    address public wethPriceFeed;
    address public wbtcPriceFeed;

    function setUp() public {
        deployer = new DeployDsc();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (weth, wbtc, wethPriceFeed, wbtcPriceFeed,) = helperConfig.activeNetworkConfig();
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocalMustBeMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 wethAmount = IERC20(weth).balanceOf(address(dscEngine));
        uint256 wbtcAmount = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 valueOfwbtc = dscEngine.getUsdValue(wbtc, wbtcAmount);
        uint256 valueOfweth = dscEngine.getUsdValue(weth, wethAmount);
        console.log("Total supply: ", totalSupply);
        console.log("Value of wbtc: ", valueOfwbtc);
        console.log("Value of weth: ", valueOfweth);
        assert(totalSupply <= (valueOfweth + valueOfwbtc));
    }
}
