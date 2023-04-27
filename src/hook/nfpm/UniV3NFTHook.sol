// SPDX-License-Identifier: AGPL-3.0-or-later
// copyright (c) 2023 the bank
pragma solidity 0.8.19;

import '../../../lib/feedbase/src/Feedbase.sol';
import '../../../lib/feedbase/src/mixin/ward.sol';
import '../../../lib/gemfab/src/gem.sol';
import '../../mixin/lock.sol';
import '../../mixin/flog.sol';
import '../../vat.sol';
import '../hook.sol';
import { LiquidityAmounts } from './lib/LiquidityAmounts.sol';
import { TickMath } from './lib/TickMath.sol';
import './lib/PoolAddress.sol';
import { DutchNFTFlower } from './DutchNFTFlower.sol';

interface IUniswapV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96, int24, uint16,uint16,uint16,uint8,bool
    );
}

interface IERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
}

interface INonfungiblePositionManager is IERC721 {
    function positions(uint256 tokenId) external view returns (
        uint96, address, address token0, address token1, uint24 fee, 
        int24 tickLower, int24 tickUpper, uint128 liquidity,
        uint256, uint256, uint128 tokensOwed0, uint128 tokensOwed1
    );
    function factory() external view returns (address);
}

// hook for uni NonfungiblePositionManager
contract UniNFTHook is Hook, Ward, Lock, Flog, Math {
    struct Source {
        address fsrc;  // [obj] feedbase `src` address
        bytes32 ftag;  // [tag] feedbase `tag` bytes32
    }

    // unlike ERC20 hook, flowback sends rico to sender; no need to identify urn
    mapping (uint256 aid => address urn) public sales;
    mapping (bytes32 ilk => mapping(address gem => Source source))   public sources;
    mapping (bytes32 ilk => mapping(address usr => uint[] tokenIds)) public inks;

    int256  internal constant  LOCK = 1;
    int256  internal constant  FREE = -1;
    uint256 internal immutable ROOM;

    Feedbase       public feed;
    DutchNFTFlower public flow;
    Gem            public rico;
    Vat            public vat;
    INonfungiblePositionManager public immutable nfpm;

    error ErrBigFlowback();
    error ErrDinkLength();
    error ErrDir();
    error ErrFull();

    constructor(address _feed, address _vat, address _flow, address _rico, address _nfpm, uint _ROOM) {
        feed = Feedbase(_feed);
        flow = DutchNFTFlower(_flow);
        rico = Gem(_rico);
        vat  = Vat(_vat);
        ROOM = _ROOM;
        nfpm = INonfungiblePositionManager(_nfpm);
    }

    function frobhook(
        address sender,
        bytes32 ilk,
        address urn,
        bytes calldata dink,
        int  // dart
    ) _ward_ _flog_ external returns (bool safer) {
        if (dink.length < 32 || dink.length % 32 != 0) revert ErrDinkLength();
        int dir = int(uint(bytes32(dink[:32])));
        if (dir == LOCK) {
            // dink is an array of tokenIds
            uint[] storage tokenIds = inks[ilk][urn];
            for (uint i = 32; i < dink.length; i += 32) {
                // transfer position from user, record it in inks
                uint tokenId = uint(bytes32(dink[i:i+32]));
                nfpm.transferFrom(sender, address(this), tokenId);
                tokenIds.push(tokenId);
                if (tokenIds.length > ROOM) revert ErrFull();
            }
        } else if (dir == FREE) {
            // dink is an array of indexes into inks
            uint[] storage tokenIds = inks[ilk][urn];
            for (uint i = 32; i < dink.length; i += 32) {
                // transfer position back to user, then remove position from inks
                uint idx = uint(bytes32(dink[i:i+32]));
                nfpm.transferFrom(address(this), sender, tokenIds[idx]);
                // swap current and last elements, then pop
                tokenIds[idx] = tokenIds[tokenIds.length - 1];
                tokenIds.pop();
            }
        } else {
            revert ErrDir();
        }
        return dir == LOCK;
    }

    function grabhook(
        address vow,
        bytes32 ilk,
        address urn,
        uint256, // art
        uint256 bill,
        address payable keeper
    ) _ward_ _flog_ external returns (uint aid) {
        uint[] memory hat = inks[ilk][urn];
        delete inks[ilk][urn];
        aid = flow.flow(vow, hat, bill, keeper);
        sales[aid] = urn;
    }

    // respective amounts of token0 and token1 that this position
    // would yield if burned now
    function amounts(uint tokenId) view internal returns (
        address t0, address t1, uint a0, uint a1
    ) {
        uint128 liquidity; int24 tickLower; int24 tickUpper; uint24 fee;
        // tokens, fee, tick bounds, liquidity, amounts owed in trade fees
        (,,t0,t1,fee,tickLower,tickUpper,liquidity,,,a0,a1) =
            nfpm.positions(tokenId);

        // get the current price
        address pool = PoolAddress.computeAddress(
            nfpm.factory(), PoolAddress.getPoolKey(t0, t1, fee)
        );
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        // convert the position's tick bounds to sqrtX96 price bounds
        // convert the price bounds, current price, and liquidity to amounts
        uint160 sqrtX96Lower = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtX96Upper = TickMath.getSqrtRatioAtTick(tickUpper);
        (uint amt0, uint amt1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96, sqrtX96Lower, sqrtX96Upper, liquidity
        );
        a0 += amt0; a1 += amt1;
    }

    function safehook(bytes32 ilk, address urn) public view returns (uint tot, uint minttl) {
        uint[] storage ink = inks[ilk][urn];
        minttl = type(uint).max;
        for (uint i = 0; i < ink.length; i++) {
            uint tokenId = ink[i];
            // get amounts of token0 and token1
            // multiply them by their prices in rico, add to tot
            (
                address token0, address token1, uint amount0, uint amount1
            ) = amounts(tokenId);
            {
                Source storage src0 = sources[ilk][token0];
                bytes32 val; uint ttl;
                if (src0.fsrc == address(0)) {
                    // if no feed, assume price is 0
                    // todo fail to frob tokens with no feed?
                    (val, ttl) = (0, type(uint).max);
                } else {
                    (val, ttl) = feed.pull(src0.fsrc, src0.ftag);
                }
                minttl = min(minttl, ttl);
                tot += amount0 * uint(val);
            }

            {
                Source storage src1 = sources[ilk][token1];
                bytes32 val; uint ttl;
                if (src1.fsrc == address(0)) {
                    (val, ttl) = (0, type(uint).max);
                } else {
                    (val, ttl) = feed.pull(src1.fsrc, src1.ftag);
                }
                minttl = min(minttl, ttl);
                tot += amount1 * uint(val);
            }
        }
    }

    function grant(uint tokenId) _flog_ external {
        nfpm.approve(address(flow), tokenId);
    }

    function flowback(uint256 aid, uint refund) _ward_ _flog_ external {
        if (refund != 0) rico.transfer(sales[aid], refund);
        delete sales[aid];
    }

    function pair(bytes32 key, uint val) _ward_ _flog_ external {
        flow.curb(key, val);
    }

    function wire(bytes32 ilk, address gem, address fsrc, bytes32 ftag) _ward_ _flog_ external {
        sources[ilk][gem] = Source(fsrc, ftag);
    }

}
