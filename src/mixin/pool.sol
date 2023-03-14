/// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.19;

import {IUniswapV3Factory, IUniswapV3Pool} from '../TEMPinterface.sol';

contract Pool {
    uint160 internal constant X96 = 2 ** 96;

    function create_pool(
        address factory,
        address token0,
        address token1,
        uint24  fee,
        uint160 sqrtPriceX96
    ) internal returns (IUniswapV3Pool pool) {
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
            sqrtPriceX96 = x96inv(sqrtPriceX96);
        }
        pool = IUniswapV3Pool(IUniswapV3Factory(factory).getPool(token0, token1, fee));

        if (address(pool) == address(0)) {
            pool = IUniswapV3Pool(IUniswapV3Factory(factory).createPool(token0, token1, fee));
            pool.initialize(sqrtPriceX96);
        } else {
            (uint160 sqrtPriceX96Existing, , , , , ,) = pool.slot0();
            if (sqrtPriceX96Existing == 0) {
                pool.initialize(sqrtPriceX96);
            }
        }
    }

    function create_path(
        address[] memory tokens,
        uint24[]  memory fees
    ) internal pure returns (bytes memory fore, bytes memory rear) {
        require(tokens.length == fees.length + 1, "invalid path");

        for (uint i = 0; i < tokens.length - 1; i++) {
            fore = abi.encodePacked(fore, tokens[i], fees[i]);
        }
        fore = abi.encodePacked(fore, tokens[tokens.length - 1]);

        rear = abi.encodePacked(rear, tokens[tokens.length - 1]);
        for (uint j = tokens.length - 1; j > 0; j--) {
            rear = abi.encodePacked(rear, fees[j - 1], tokens[j - 1]);
        }
    }

    function x96inv(uint160 x) internal pure returns (uint160) {
        return x96div(X96, x);
    }

    function x96div(uint160 x, uint160 y) internal pure returns (uint160) {
        return uint160(uint(x) * uint(X96) / uint(y));
    }
}
