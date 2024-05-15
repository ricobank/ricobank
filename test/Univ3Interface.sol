// SPDX-License-Identifier: AGPL-3.0-or-later
//
// UniswapV3 interfaces needed for testing
// Copied and modified from
//   UniswapV3 periphery https://github.com/Uniswap/v3-periphery
//   UniswapV3 core https://github.com/Uniswap/v3-core

pragma solidity ^0.8.25;

import { Ward } from '../lib/feedbase/src/mixin/ward.sol';

interface IERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

interface INonfungiblePositionManager is IERC721 {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params) external
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function positions(uint256 tokenId)
        external view returns (
            uint96 nonce, address operator, address token0, address token1,
            uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity,
            uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0, uint128 tokensOwed1
        );

    function factory() external view returns (address);
}

interface IUniswapV3Pool {
    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // whether the pool is locked
        bool unlocked;
    }

    function slot0()
      external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );

    function initialize(uint160) external;
    function mint(address,int24,int24,uint128,bytes calldata) external returns (uint,uint);
    function swap(address,bool,int,uint160,bytes calldata) external returns (int,int);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function tickSpacing() external view returns (int24);
    function fee() external view returns (uint24);
}

interface IUniswapV3Factory {
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);

    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);

    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);
}
