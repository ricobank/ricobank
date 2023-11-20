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
    function computeAddress(address factory, address t0, address t1, uint24 fee) external view returns (address);
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

    struct Amounts {
        address tok0;
        address tok1;
        uint256 amt0;
        uint256 amt1;
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

    int256 internal constant  LOCK = 1;
    int256 internal constant  FREE = -1;
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
                uint room = hs.room;
                for (uint idx = 1; idx < dink.length; idx++) {
                    uint tokenId = dink[idx];
                    NFPM.transferFrom(p.sender, address(this), tokenId);

                    // record it in ink
                    tokenIds.push(tokenId);

                    // limit the number of positions in the CDP
                    // TODO probably can me moved outside the loop...
                    if (tokenIds.length > room) revert ErrFull();
                }
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
        uint earn = rmul(p.tot / RAY, rmul(rpow(p.deal, hs.plot.pep), hs.plot.pop));

        // take from keeper to underwrite urn, return what's left to urn owner.
        Gem rico = getBankStorage().rico;
        rico.burn(p.keeper, earn);
        uint over = earn > p.bill ? earn - p.bill : 0;
        if (over > 0) rico.mint(p.u, over);
        vsync(p.i, earn, p.owed, over);

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

    // respective amounts of token0 and token1 that this position
    // would yield if burned now
    function amounts(uint tokenId, UniNFTHookStorage storage hs)
      internal view returns (Amounts memory) {
        Amounts memory amts;
        uint24 fee;

        IUniWrapper wrap = hs.wrap;
        (,,amts.tok0, amts.tok1, fee,,,,,,,) = NFPM.positions(tokenId);

        // get the current price
        address pool = wrap.computeAddress(NFPM.factory(), amts.tok0, amts.tok1, fee);
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        // uni library function to get amounts
        (amts.amt0, amts.amt1) = wrap.total(NFPM, tokenId, sqrtPriceX96);
        return amts;
    }

    function safehook(bytes32 i, address u)
      external view returns (uint tot, uint cut, uint minttl) {
        Feedbase fb = getBankStorage().fb;
        UniNFTHookStorage storage hs       = getStorage(i);
        uint256[]         storage tokenIds = hs.inks[u];
        minttl = type(uint256).max;
        uint256 ttl; bytes32 val;

        for (uint idx = 0; idx < tokenIds.length;) {
            // get amounts of token0 and token1
            Amounts memory amts = amounts(tokenIds[idx], hs);
            Source storage src0 = hs.sources[amts.tok0];
            Source storage src1 = hs.sources[amts.tok1];
            uint256 liqr = max(src0.liqr, src1.liqr);

            // find total value of tok0 + tok1, and allowed debt cut off
            (val, minttl) = fb.pull(src0.rudd.src, src0.rudd.tag);
            tot += amts.amt0 * uint(val);
            cut += amts.amt0 * rdiv(uint(val), liqr);

            (val, ttl) = fb.pull(src1.rudd.src, src1.rudd.tag);
            minttl = min(minttl, ttl);
            tot += amts.amt1 * uint(val);
            cut += amts.amt1 * rdiv(uint(val), liqr);
            unchecked {++idx;}
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
