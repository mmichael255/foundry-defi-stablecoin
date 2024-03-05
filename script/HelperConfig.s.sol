// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mock/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    uint8 private constant DECMALS = 8;
    int256 private constant ETH_PRICE = 2000e8;
    int256 private constant BTC_PRICE = 6000e8;

    struct NetworkConfig {
        address weth;
        address wbtc;
        address ethPriceFeed;
        address btcPriceFeed;
        uint256 deployKey;
    }

    uint256 private constant ANVIL_DEPLOY_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 11155111) {
            // Deployed on Sepolia
            activeNetworkConfig = getSepoliaConfig();
        } else {
            // Deployed on anvil
            activeNetworkConfig = getAnvilConfig();
        }
    }

    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            weth: 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            ethPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            btcPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            deployKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.ethPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethMockPriceFeed = new MockV3Aggregator(DECMALS, ETH_PRICE);
        ERC20Mock weth = new ERC20Mock();

        MockV3Aggregator btcMockPriceFeed = new MockV3Aggregator(DECMALS, BTC_PRICE);
        ERC20Mock wbtc = new ERC20Mock();
        vm.stopBroadcast();

        return NetworkConfig({
            weth: address(weth),
            wbtc: address(wbtc),
            ethPriceFeed: address(ethMockPriceFeed),
            btcPriceFeed: address(btcMockPriceFeed),
            deployKey: ANVIL_DEPLOY_KEY
        });
    }
}
