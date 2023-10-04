// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2023 halys

pragma solidity ^0.8.19;

import { Bank, Gem } from '../bank.sol';
import { Hook } from './hook.sol';

// hook that interprets ink as a single uint and dink as a single int.
contract ERC20Hook is Hook, Bank {

    struct ERC20HookStorage {
        mapping (address u => uint) inks; // amount
        address gem;   // this ilk's gem
        address fsrc;  // [obj] feedbase `src` address
        bytes32 ftag;  // [tag] feedbase `tag` bytes32
        uint    liqr;  // [ray] liquidation ratio
        uint    pep;   // [int] discount exponent
        uint    pop;   // [ray] sale price multiplier
    }

    function getStorage(bytes32 i) internal pure returns (ERC20HookStorage storage hs) {
        bytes32 pos = keccak256(abi.encodePacked(i));
        assembly {
            hs.slot := pos
        }
    }

    error ErrTransfer();
    error ErrDinkSize();

    function ink(bytes32 i, address u) external view returns (bytes memory data) {
        data = abi.encodePacked(getStorage(i).inks[u]);
    }

    function frobhook(
        address sender, bytes32 i, address u, bytes calldata _dink, int
    ) external returns (bool safer) {
        ERC20HookStorage storage hs = getStorage(i);

        // read dink as a single uint
        if (_dink.length != 32) revert ErrDinkSize();
        int dink = int(uint(bytes32(_dink)));

        // update balance before transfering tokens
        uint _ink  = add(hs.inks[u], dink);
        hs.inks[u] = _ink;
        emit NewPalmBytes2('ink', i, bytes32(bytes20(u)), abi.encodePacked(_ink));

        Gem gem = Gem(hs.gem);
        if (dink > 0) {

            // pull tokens from sender
            if (!gem.transferFrom(sender, address(this), uint(dink))) {
                revert ErrTransfer();
            }

        } else if (dink < 0) {

            // return tokens to sender
            if (!gem.transfer(sender, uint(-dink))) {
                revert ErrTransfer();
            }

        }

        // safer if this call added tokens to ink
        return dink >= 0;
    }

    function bailhook(
        bytes32 i, address u, uint256 bill, address keeper, uint256 deal, uint tot
    ) external returns (bytes memory) {
        ERC20HookStorage storage hs  = getStorage(i);
        VatStorage       storage vs  = getVatStorage();

        // tot is RAD, deal is RAY, so bank earns a WAD.
        // sell - sold collateral
        // earn - rico "earned" by bank in this liquidation
        uint sell = hs.inks[u];
        uint earn = rmul(tot / RAY, rmul(rpow(deal, hs.pep), hs.pop));

        // clamp `sell` so bank only gets enough to underwrite urn.
        if (earn > bill) {
            sell = sell * bill / earn;
            earn = bill;
        }

        // update collateral balance
        uint _ink  = hs.inks[u] - sell;
        hs.inks[u] = _ink;
        emit NewPalmBytes2('ink', i, bytes32(bytes20(u)), abi.encodePacked(_ink));

        // update joy to help cancel out sin
        uint mood = vs.joy + earn;
        vs.joy    = mood;
        emit NewPalm0('joy', bytes32(mood));

        // trade collateral with keeper for rico
        getBankStorage().rico.burn(keeper, earn);
        if (!Gem(hs.gem).transfer(keeper, sell)) revert ErrTransfer();

        return abi.encodePacked(sell);
    }

    function safehook(bytes32 i, address u) view public returns (uint tot, uint cut, uint ttl) {
        ERC20HookStorage storage hs  = getStorage(i);

        // total value of collateral == ink * price feed val
        (bytes32 val, uint _ttl) = getBankStorage().fb.pull(hs.fsrc, hs.ftag);
        tot = uint(val) * hs.inks[u];
        cut = uint(val) * rdiv(hs.inks[u], hs.liqr);
        ttl = _ttl;
    }

    function file(bytes32 key, bytes32 i, bytes32[] calldata xs, bytes32 val)
      external {
        ERC20HookStorage storage hs  = getStorage(i);

        if (xs.length == 0) {
            if (key == 'gem') { hs.gem = address(bytes20(val));
            } else if (key == 'fsrc') { hs.fsrc = address(bytes20(val));
            } else if (key == 'ftag') { hs.ftag = val;
            } else if (key == 'liqr') { hs.liqr = uint(val);
            } else if (key == 'pep')  { hs.pep  = uint(val);
            } else if (key == 'pop')  { hs.pop  = uint(val);
            } else { revert ErrWrongKey(); }
            emit NewPalm1(key, i, val);
        } else {
            revert ErrWrongKey();
        }
    }

    function get(bytes32 key, bytes32 i, bytes32[] calldata xs)
      view external returns (bytes32) {
        ERC20HookStorage storage hs  = getStorage(i);

        if (xs.length == 0) {
            if (key == 'gem') { return bytes32(bytes20(hs.gem));
            } else if (key == 'fsrc') { return bytes32(bytes20(hs.fsrc));
            } else if (key == 'ftag') { return hs.ftag;
            } else if (key == 'liqr') { return bytes32(hs.liqr);
            } else if (key == 'pep')  { return bytes32(hs.pep);
            } else if (key == 'pop')  { return bytes32(hs.pop);
            } else { revert ErrWrongKey(); }
        } else {
            revert ErrWrongKey();
        }
    }
}
