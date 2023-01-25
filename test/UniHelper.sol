// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import { Gem } from '../lib/gemfab/src/gem.sol';
import { Ball } from '../src/ball.sol';
import { IUniswapV3Factory, IUniswapV3Pool } from '../src/TEMPinterface.sol';

struct Asset {
    address token;
    uint256 amountIn;
}

struct PoolArgs {
    Asset a1;
    Asset a2;
    uint24 fee;
    uint160 sqrtPriceX96;
}

abstract contract UniSetUp {
    address constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant ROUTER  = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant WETH    = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function create_path(address[] memory tokens, uint24[] memory fees)
            public pure returns (bytes memory fore, bytes memory rear) {
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

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) internal returns (address pool) {
        require(token0 < token1);
        pool = IUniswapV3Factory(FACTORY).getPool(token0, token1, fee);

        if (pool == address(0)) {
            pool = IUniswapV3Factory(FACTORY).createPool(token0, token1, fee);
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        } else {
            (uint160 sqrtPriceX96Existing, , , , , , ) = IUniswapV3Pool(pool).slot0();
            if (sqrtPriceX96Existing == 0) {
                IUniswapV3Pool(pool).initialize(sqrtPriceX96);
            }
        }
    }

    function create_pool(PoolArgs memory args) public {
        Asset memory a;
        Asset memory b;
        if (args.a1.token < args.a2.token){
            a = args.a1;
            b = args.a2;
        } else {
            a = args.a2;
            b = args.a1;
            // todo invert price
        }
        createAndInitializePoolIfNecessary(a.token, b.token, args.fee, args.sqrtPriceX96);
    }

    function create_and_join_pool(PoolArgs memory args) public {
        create_pool(args);
        join_pool(args);
    }

    function join_pool(PoolArgs memory args) public {
        Asset memory a;
        Asset memory b;

        if (args.a1.token < args.a2.token){
            a = args.a1;
            b = args.a2;
        } else {
            a = args.a2;
            b = args.a1;
        }

        address[] memory tokens  = new address[](2);
        tokens[0] = a.token;
        tokens[1] = b.token;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = a.amountIn;
        amounts[1] = b.amountIn;

        // todo
    }
}
