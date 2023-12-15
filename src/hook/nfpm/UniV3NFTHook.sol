// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2023 halys

pragma solidity ^0.8.19;

import { Gem, Feedbase } from "../../bank.sol";
import { HookMix } from "../hook.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { INonfungiblePositionManager as INFPM } from "./interfaces/INonfungiblePositionManager.sol";

// uniswap libraries to get total token amounts in uniswap positions
interface IUniWrapper {
    function total(INFPM nfpm, uint tokenId, uint160 sqrtPriceX96) external view returns (uint amount0, uint amount1);
}

// hook for uni NonfungiblePositionManager
// calculates token amounts for each uniswap position in the CDP
// and adds them to `cut`
contract UniNFTHook is HookMix {

    struct Source {
        Rudd    rudd;  // feed src,tag
        uint256 liqr;  // [ray] liquidation ratio. Greater value means collateral allows less debt
    }

    struct UniNFTHookStorage {
        mapping(address gem => Source source) sources;
        mapping(address usr => uint[] tokenIds) inks;
        IUniWrapper wrap; // wrapper for uniswap libraries that use earlier solc
        uint256 room;  // maximum position list length
        Plx     plot;  // [int] discount exponent, [ray] sale price multiplier
    }

    // avoids stack too deep
    struct Position {
        address tok0;
        address tok1;
        uint256 amt0;
        uint256 amt1;
        uint256 id;
        uint256 len;
    }

    function getStorage(bytes32 i) internal pure returns (UniNFTHookStorage storage hs) {
        bytes32 pos = keccak256(abi.encodePacked(i));
        assembly {
            hs.slot := pos
        }
    }

    error ErrNotFound();
    error ErrDir();
    error ErrFull();
    error ErrRatio();

    int256 internal constant  LOCK = 1;
    int256 internal constant  FREE = -1;
    uint160 internal constant X96 = 2 ** 96;
    uint256 internal constant MAX_SHIFT = 2**(256 - 96) - 1;
    INFPM  internal immutable NFPM;

    constructor(address nfpm) {
        NFPM = INFPM(nfpm);
    }

    function ink(bytes32 i, address u) external view returns (bytes memory) {
        return abi.encode(getStorage(i).inks[u]);
    }

    function frobhook(FHParams calldata p) external payable returns (bool safer) {
        UniNFTHookStorage storage hs = getStorage(p.i);
        uint[] storage tokenIds      = hs.inks[p.u];

        // dink is a nonempty packed list of uint tokenIds
        // first uint must either be LOCK (add token) or FREE (remove token)
        uint[] memory dink;
        int dir = LOCK;
        if (p.dink.length > 0) {
            dink = abi.decode(p.dink, (uint[]));
            dir  = int(dink[0]);
        }

        if (dir == LOCK) {
            // safer if locking ink and wiping art
            safer = p.dart <= 0;
            unchecked {
                // add uni positions
                for (uint idx = 1; idx < dink.length; idx++) {
                    // pull the token
                    uint tokenId = dink[idx];
                    NFPM.transferFrom(p.sender, address(this), tokenId);
                    // record it in ink
                    tokenIds.push(tokenId);
                }

                // limit loop iterations
                if (tokenIds.length > hs.room) revert ErrFull();
            }
        } else if (dir == FREE) {
            unchecked {
                // remove uni positions
                for (uint j = 1; j < dink.length; j++) {
                    uint toss = dink[j];
                    uint size = tokenIds.length;
                    for (uint k = 0; k < size; ++k) {
                        if (tokenIds[k] == toss) {
                            tokenIds[k] = tokenIds[size - 1];
                            tokenIds.pop();
                            NFPM.transferFrom(address(this), p.u, toss);
                            break;
                        }
                    }
                    if (tokenIds.length == size) revert ErrNotFound();
                }
            }
        } else revert ErrDir();

        // can't steal collateral or rico from others' urns
        if (!(safer || p.u == p.sender)) revert ErrWrongUrn();

        emit NewPalmBytes2("ink", p.i, bytes32(bytes20(p.u)), abi.encode(tokenIds));
    }

    function bailhook(BHParams calldata p) external payable returns (bytes memory) {
        UniNFTHookStorage storage hs  = getStorage(p.i);
        uint[]            memory  ids = hs.inks[p.u];

        // bail all the uni positions
        delete hs.inks[p.u];
        emit NewPalmBytes2("ink", p.i, bytes32(bytes20(p.u)), bytes(""));

        // tot is RAD, deal is RAY, so bank earns a WAD
        uint mash = rmash(p.deal, hs.plot.pep, hs.plot.pop, hs.plot.pup);
        uint earn = rmul(p.tot / RAY, mash);

        // take from keeper to underwrite urn, return what's left to urn owner.
        Gem rico = getBankStorage().rico;
        rico.burn(p.keeper, earn);

        unchecked {
            uint over = earn > p.bill ? earn - p.bill : 0;
            if (over > 0) rico.mint(p.u, over);
            vsync(p.i, earn, p.owed, over);
        }

        // send the uni positions to keeper
        uint len = ids.length;
        uint idx;
        while (idx < len) {
            uint id = ids[idx];
            NFPM.transferFrom(address(this), p.keeper, id);
            unchecked{ idx++; }
        }

        return abi.encode(ids);
    }

    function safehook(bytes32 i, address u)
      external view returns (uint tot, uint cut, uint minttl) {
        Feedbase fb = getBankStorage().fb;
        UniNFTHookStorage storage hs       = getStorage(i);
        uint256[]         storage tokenIds = hs.inks[u];

        minttl = type(uint256).max;
        Position memory pos;
        pos.len = tokenIds.length;

        for (uint idx = 0; idx < pos.len;) {
            pos.id = tokenIds[idx];
            (,, pos.tok0, pos.tok1,,,,,,,,) = NFPM.positions(pos.id);
            Source storage src0 = hs.sources[pos.tok0];
            Source storage src1 = hs.sources[pos.tok1];

            // pull prices for each token, scale prices down to wad, save minttl
            (bytes32 val0, uint ttl) = fb.pull(src0.rudd.src, src0.rudd.tag);
            val0 = bytes32(uint(val0) / BLN);
            if (uint(val0) > MAX_SHIFT) revert ErrRatio();
            if (ttl < minttl) minttl = ttl;

            bytes32 val1;
            (val1, ttl) = fb.pull(src1.rudd.src, src1.rudd.tag);
            val1 = bytes32(uint(val1) / BLN);
            if (ttl < minttl) minttl = ttl;


            // estimate pool's price based on quotient of tokens' prices vs ref
            uint160 sqrtRatioX96 = type(uint160).max;
            if(uint(val1) != 0) {
                // pool token1/token0 = (ref/token0)/(ref/token1) = val0/val1
                uint ratioX96 = (uint(val0) << 96) / uint(val1);

                // sqrt with as much precision as possible without overflow
                // note that (2**48)**2 == 2**96
                sqrtRatioX96 = ratioX96 < MAX_SHIFT ? sqrtu(ratioX96 << 96)
                                                    : sqrtu(ratioX96) << 48;
            }

            // based on pool price estimate, get amounts of each token
            (pos.amt0, pos.amt1) = hs.wrap.total(NFPM, pos.id, sqrtRatioX96);

            // find total value of tok0 + tok1, and allowed debt cut off
            uint256 liqr = max(src0.liqr, src1.liqr);
            tot += pos.amt0 * uint(val0) + pos.amt1 * uint(val1);
            cut += pos.amt0 * rdiv(uint(val0), liqr) + pos.amt1 * rdiv(uint(val1), liqr);
            unchecked {++idx;}
        }

        // scale output up to rad
        tot *= BLN;
        cut *= BLN;
    }

    // FROM https://github.com/abdk-consulting/abdk-libraries-solidity/blob/5e1e7c11b35f8313d3f7ce11c1b86320d7c0b554/ABDKMath64x64.sol#L725C7-L725C7
    /**
    * Calculate sqrt (x) rounding down, where x is unsigned 256-bit integer
    * number.
    *
    * @param x unsigned 256-bit integer number
    * @return unsigned 128-bit integer number
    */
    function sqrtu (uint256 x) private pure returns (uint128) {
        unchecked {
            if (x == 0) return 0;
            else {
                uint256 xx = x;
                uint256 r = 1;
                if (xx >= 0x100000000000000000000000000000000) { xx >>= 128; r <<= 64; }
                if (xx >= 0x10000000000000000) { xx >>= 64; r <<= 32; }
                if (xx >= 0x100000000) { xx >>= 32; r <<= 16; }
                if (xx >= 0x10000) { xx >>= 16; r <<= 8; }
                if (xx >= 0x100) { xx >>= 8; r <<= 4; }
                if (xx >= 0x10) { xx >>= 4; r <<= 2; }
                if (xx >= 0x4) { r <<= 1; }
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1;
                r = (r + x / r) >> 1; // Seven iterations should be enough
                uint256 r1 = x / r;
                return uint128 (r < r1 ? r : r1);
            }
        }
    }

    function file(bytes32 key, bytes32 i, bytes32[] calldata xs, bytes32 val)
      external payable {
        UniNFTHookStorage storage hs  = getStorage(i);

        if (xs.length == 0) {
                   if (key == "room") { hs.room = uint(val);
            } else if (key == "wrap") { hs.wrap = IUniWrapper(address(bytes20(val)));
            } else if (key == "pep")  { hs.plot.pep = uint(val);
            } else if (key == "pop")  { hs.plot.pop = uint(val);
            } else if (key == "pup")  { hs.plot.pup = int(uint(val));
            } else { revert ErrWrongKey(); }
            emit NewPalm1(key, i, val);
        } else if (xs.length == 1) {
            address gem = address(bytes20(xs[0]));
            if (key == "src") { hs.sources[gem].rudd.src = address(bytes20(val));
            } else if (key == "tag") { hs.sources[gem].rudd.tag = val;
            } else if (key == "liqr") { 
                must(uint(val), RAY, type(uint).max);
                hs.sources[gem].liqr = uint(val);
            } else { revert ErrWrongKey(); }
            emit NewPalm2(key, i, xs[0], val);
        } else {
            revert ErrWrongKey();
        }
    }

    function get(bytes32 key, bytes32 i, bytes32[] calldata xs)
      external view returns (bytes32) {
        UniNFTHookStorage storage hs  = getStorage(i);

        if (xs.length == 0) {
                   if (key == "room") { return bytes32(hs.room);
            } else if (key == "wrap") { return bytes32(bytes20(address(hs.wrap)));
            } else if (key == "pep")  { return bytes32(hs.plot.pep);
            } else if (key == "pop")  { return bytes32(hs.plot.pop);
            } else if (key == "pup")  { return bytes32(uint(hs.plot.pup));
            } else { revert ErrWrongKey(); }
        } else if (xs.length == 1) {
            address gem = address(bytes20(xs[0]));

            if (key == "src") { return bytes32(bytes20(hs.sources[gem].rudd.src));
            } else if (key == "tag") { return hs.sources[gem].rudd.tag;
            } else if (key == "liqr") { return bytes32(hs.sources[gem].liqr);
            } else { revert ErrWrongKey(); }
        } else {
            revert ErrWrongKey();
        }
    }

}
