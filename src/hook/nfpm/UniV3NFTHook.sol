// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2023 halys

pragma solidity ^0.8.19;

import { Bank, Gem, Feedbase } from '../../bank.sol';
import { Hook } from '../hook.sol';

import { IUniswapV3Pool } from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import { INonfungiblePositionManager } from './interfaces/INonfungiblePositionManager.sol';

// uniswap libraries to get total token amounts in uniswap positions
interface IUniWrapper {
    function total(INonfungiblePositionManager nfpm, uint tokenId, uint160 sqrtPriceX96) view external returns (uint amount0, uint amount1);
    function computeAddress(address factory, address t0, address t1, uint24 fee) view external returns (address);
}

// hook for uni NonfungiblePositionManager
// calculates token amounts for each uniswap position in the CDP
// and adds them to `cut`
contract UniNFTHook is Hook, Bank {

    struct Source {
        address fsrc;  // [obj] feedbase `src` address
        bytes32 ftag;  // [tag] feedbase `tag` bytes32
    }

    struct UniNFTIlk {
        mapping(address gem => Source source) sources;
        uint liqr;  // [ray] liquidation ratio
        uint pep;   // [int] discount exponent
        uint pop;   // [ray] sale price multiplier
    }

    struct UniNFTHookStorage {
        INonfungiblePositionManager nfpm; // uni NFT
        uint256 ROOM;     // maximum position list length
        IUniWrapper wrap; // wrapper for uniswap libraries that use earlier solc
        UniNFTIlk ilk;
        mapping(address usr => uint[] tokenIds) inks;
    }

    bytes32 constant public INFO = bytes32(abi.encodePacked('uninfthook.0'));
    function getStorage(bytes32 i) internal pure returns (UniNFTHookStorage storage hs) {
        bytes32 pos = keccak256(abi.encodePacked(i));
        assembly {
            hs.slot := pos
        }
    }

    function ink(bytes32 i, address u) view external returns (bytes memory) {
        return abi.encode(getStorage(i).inks[u]);
    }

    int256 internal constant LOCK = 1;
    int256 internal constant FREE = -1;

    error ErrDinkLength();
    error ErrNotFound();
    error ErrDir();
    error ErrFull();

    function frobhook(
        address sender, bytes32 i, address u, bytes calldata dink, int
    ) external returns (bool safer) {
        UniNFTHookStorage storage hs = getStorage(i);
        uint[] storage tokenIds      = hs.inks[u];

        // dink is a nonempty packed list of uint tokenIds
        if (dink.length < 32 || dink.length % 32 != 0) revert ErrDinkLength();

        {
            int dir = int(uint(bytes32(dink[:32])));
            if (dir != LOCK && dir != FREE) revert ErrDir();
            safer = dir == LOCK;
        }

        if (safer) { 
            // add uni positions

            for (uint idx = 32; idx < dink.length; idx += 32) {
                uint tokenId = uint(bytes32(dink[idx:idx+32]));

                // transfer position from user
                hs.nfpm.transferFrom(sender, address(this), tokenId);

                // record it in ink
                tokenIds.push(tokenId);

                // limit the positions in the CDP
                if (tokenIds.length > hs.ROOM) revert ErrFull();
            }

        } else { 
            // remove uni positions

            if ((dink.length - 32) / 32 > tokenIds.length) revert ErrDinkLength();

            for (uint j = 32; j < dink.length; j += 32) {
                uint toss  = uint(bytes32(dink[j:j+32]));

                // search ink for toss
                bool found;
                for (uint k = 0; k < tokenIds.length; ++k) {

                    uint tokenId = tokenIds[k];
                    if (found = tokenId == toss) {
                        // id found; pop
                        tokenIds[k] = tokenIds[tokenIds.length - 1];
                        tokenIds.pop();
                        break;
                    }
                }

                if (!found) revert ErrNotFound();
            }

            // send dinked tokens back to user
            for (uint j = 32; j < dink.length; j += 32) {
                uint toss = uint(bytes32(dink[j:j+32]));
                hs.nfpm.transferFrom(address(this), u, toss);
            }

        }
        emit NewPalmBytes2('ink', i, bytes32(bytes20(u)), abi.encodePacked(tokenIds));
    }

    function bailhook(
        bytes32 i, address u, uint256 bill, address keeper, uint256 deal, uint256 tot
    ) external returns (bytes memory) {
        UniNFTHookStorage storage hs  = getStorage(i);
        UniNFTIlk         storage ilk = hs.ilk;
        uint[]            memory  ids = hs.inks[u];

        // bail all the uni positions
        delete hs.inks[u];
        emit NewPalmBytes2('ink', i, bytes32(bytes20(u)), bytes(''));

        // tot is RAD, deal is RAY, so bank earns a WAD
        uint earn = rmul(tot / RAY, rmul(rpow(deal, ilk.pep), ilk.pop));
        uint over = earn > bill ? earn - bill : 0;

        // take from keeper to underwrite urn, return what's left to urn owner.
        Gem rico = getBankStorage().rico;
        rico.burn(keeper, earn);
        rico.mint(u, over);

        {
            // increase joy just by what was used to underwrite urn.
            VatStorage storage vs = getVatStorage();
            uint mood = vs.joy + earn - over;
            vs.joy = mood;
            emit NewPalm0('joy', bytes32(mood));
        }

        // send the uni positions to keeper
        uint len = ids.length;
        uint idx;
        while (true) {
            uint id = ids[idx];
            hs.nfpm.transferFrom(address(this), keeper, id);
            unchecked{ idx++; }
            if (idx >= len) break;
        }
        return abi.encodePacked(ids);
    }

    // respective amounts of token0 and token1 that this position
    // would yield if burned now
    function amounts(uint tokenId, UniNFTHookStorage storage hs) view internal returns (
        address t0, address t1, uint a0, uint a1
    ) {
        uint24 fee;
        (,,t0,t1,fee,,,,,,,) = hs.nfpm.positions(tokenId);

        // get the current price
        address pool = hs.wrap.computeAddress(hs.nfpm.factory(), t0, t1, fee);
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        // uni library function to get amounts
        (a0, a1) = hs.wrap.total(hs.nfpm, tokenId, sqrtPriceX96);
    }

    function safehook(bytes32 i, address u) public view returns (uint tot, uint cut, uint minttl) {
        UniNFTHookStorage storage hs       = getStorage(i);
        UniNFTIlk         storage ilk      = hs.ilk;
        uint[]            storage tokenIds = hs.inks[u];

        minttl = type(uint).max;

        for (uint idx = 0; idx < tokenIds.length; ++idx) {
            // get amounts of token0 and token1
            (
                address token0, address token1, uint amount0, uint amount1
            ) = amounts(tokenIds[idx], hs);
            Feedbase fb = getBankStorage().fb;

            // find total value value of tok0 + tok1, and allowed debt cut off
            {
                Source storage src0 = ilk.sources[token0];
                (bytes32 val, uint ttl) = fb.pull(src0.fsrc, src0.ftag);
                minttl = min(minttl, ttl);
                tot   += amount0 * uint(val);
                cut   += amount0 * rdiv(uint(val), ilk.liqr);
            }

            {
                Source storage src1 = ilk.sources[token1];
                (bytes32 val, uint ttl) = fb.pull(src1.fsrc, src1.ftag);
                minttl = min(minttl, ttl);
                tot   += amount1 * uint(val);
                cut   += amount1 * rdiv(uint(val), ilk.liqr);
            }
        }

    }

    function file(bytes32 key, bytes32 i, bytes32[] calldata xs, bytes32 val)
      external {
        UniNFTHookStorage storage hs  = getStorage(i);
        UniNFTIlk         storage ilk = hs.ilk;

        if (xs.length == 0) {
            if (key == 'nfpm') { hs.nfpm = INonfungiblePositionManager(address(bytes20(val)));
            } else if (key == 'ROOM') { hs.ROOM = uint(val);
            } else if (key == 'wrap') { hs.wrap = IUniWrapper(address(bytes20(val)));
            } else if (key == 'liqr') { ilk.liqr = uint(val);
            } else if (key == 'pep')  { ilk.pep = uint(val);
            } else if (key == 'pop')  { ilk.pop = uint(val);
            } else { revert ErrWrongKey(); }
            emit NewPalm1(key, i, val);
        } else if (xs.length == 1) {
            address gem = address(bytes20(xs[0]));

            if (key == 'fsrc') { ilk.sources[gem].fsrc = address(bytes20(val));
            } else if (key == 'ftag') { ilk.sources[gem].ftag = val;
            } else { revert ErrWrongKey(); }
            emit NewPalm2(key, i, xs[0], val);
        } else {
            revert ErrWrongKey();
        }
    }

    function get(bytes32 key, bytes32 i, bytes32[] calldata xs)
      view external returns (bytes32) {
        UniNFTHookStorage storage hs  = getStorage(i);
        UniNFTIlk         storage ilk = hs.ilk;

        if (xs.length == 0) {
            if (key == 'nfpm') { return bytes32(bytes20(address(hs.nfpm)));
            } else if (key == 'ROOM') { return bytes32(hs.ROOM);
            } else if (key == 'wrap') { return bytes32(bytes20(address(hs.wrap)));
            } else if (key == 'liqr') { return bytes32(ilk.liqr);
            } else if (key == 'pep') { return bytes32(ilk.pep);
            } else if (key == 'pop') { return bytes32(ilk.pop);
            } else { revert ErrWrongKey(); }
        } else if (xs.length == 1) {
            address gem = address(bytes20(xs[0]));

            if (key == 'fsrc') { return bytes32(bytes20(ilk.sources[gem].fsrc));
            } else if (key == 'ftag') { return ilk.sources[gem].ftag;
            } else { revert ErrWrongKey(); }
        } else {
            revert ErrWrongKey();
        }
    }

}
