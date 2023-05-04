pragma solidity 0.7.6;
import { PoolAddress, INonfungiblePositionManager, PositionValue } from '@uniswap/v3-periphery/contracts/libraries/PositionValue.sol';

contract UniWrapper {
    function total(INonfungiblePositionManager nfpm, uint tokenId, uint160 sqrtPriceX96) view public returns (uint amount0, uint amount1) {
        return PositionValue.total(nfpm, tokenId, sqrtPriceX96);
    }

    function computeAddress(address factory, address t0, address t1, uint24 fee) view public returns (address) {
        return PoolAddress.computeAddress(factory, PoolAddress.getPoolKey(t0, t1, fee));
    }
}
