//SPDX-License-Identifier: MIT

//Hanlder is going to narrow down the way we call functions

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    uint96 public AMOUNT_MAX = type(uint96).max;
    ERC20Mock public weth;
    ERC20Mock public wbtc;
    address[] public usersDeposited;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        address[] memory tokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(tokens[0]);
        wbtc = ERC20Mock(tokens[1]);
    }

    function depositCollateral(uint256 seed, uint256 amount) public {
        ERC20Mock collateral = depositCollateralWithSeed(seed);
        amount = bound(amount, 1, AMOUNT_MAX);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(dscEngine), amount);
        dscEngine.depositCollateral(address(collateral), amount);
        vm.stopPrank();
        usersDeposited.push(msg.sender);
    }

    function mintDsc(uint256 amount, uint256 userIndex) public {
        if (usersDeposited.length == 0) {
            return;
        }
        userIndex = (userIndex % usersDeposited.length);
        address user = usersDeposited[userIndex];
        amount = bound(amount, 1, AMOUNT_MAX);
        (uint256 dscMinted, uint256 totalCollateralValue) = dscEngine.getAccountInformation(user);
        uint256 maxDsc = (totalCollateralValue / 2) - dscMinted;
        if (maxDsc < 0) {
            return;
        }
        amount = bound(amount, 0, maxDsc);
        if (amount == 0) {
            return;
        }
        vm.startPrank(user);
        dscEngine.mintDsc(amount);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 seed, uint256 amount) public {
        ERC20Mock collateral = depositCollateralWithSeed(seed);
        uint256 maxCollateral = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amount = bound(amount, 0, maxCollateral);
        if (amount == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        dscEngine.redeemCollateral(address(collateral), amount);
        vm.stopPrank();
    }

    function depositCollateralWithSeed(uint256 seed) private view returns (ERC20Mock) {
        if (seed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
