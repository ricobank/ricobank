// SPDX-License-Identifier: AGPL-3.0-or-later

/// vat.sol -- Rico CDP database

// Copyright (C) 2023 the bank
// Copyright (C) 2022 the bank
// Copyright (C) 2021 monospace
// Copyright (C) 2018 Rain <rainbreak@riseup.net>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity 0.8.20;

import { Lock } from './mixin/lock.sol';
import { Math } from './mixin/math.sol';
import { Flog } from './mixin/flog.sol';

import { Ward } from '../lib/feedbase/src/mixin/ward.sol';
import { Gem }  from '../lib/gemfab/src/gem.sol';
import { Hook } from './hook/hook.sol';
import { Bank } from './bank.sol';

contract Vat is Bank {
    function ilks(bytes32 i) view external returns (Ilk memory) {
        return getVatStorage().ilks[i];
    }
    function urns(bytes32 i, address u) view external returns (uint) {
        return getVatStorage().urns[i][u];
    }
    function sin() view external returns (uint) {return getVatStorage().sin;}
    function rest() view external returns (uint) {return getVatStorage().rest;}
    function debt() view external returns (uint) {return getVatStorage().debt;}
    function ceil() view external returns (uint) {return getVatStorage().ceil;}
    function par() view external returns (uint) {return getVatStorage().par;}
    function ink(bytes32 i, address u) external returns (bytes memory data) {
        data = abi.decode(hookcall(i, abi.encodeWithSelector(
            Hook.ink.selector, i, u
        )), (bytes));
    }
    function DASH() pure external returns (uint) {return _DASH;}
    function MINT() pure external returns (uint) {return _MINT;}

    enum Spot {Sunk, Iffy, Safe}

    uint256 constant _MINT = 2 ** 128;
    uint256 constant _DASH = 2 *  RAY;

    error ErrFeeMin();
    error ErrFeeRho();
    error ErrIlkInit();
    error ErrNotSafe();
    error ErrUrnDust();
    error ErrDebtCeil();
    error ErrMultiIlk();
    error ErrTransfer();
    error ErrWrongUrn();
    error ErrHookData();
    error ErrStatic();
    error ErrLock();

    function init(bytes32 ilk, address hook)
      _ward_ _flog_ external
    {
        VatStorage storage vs = getVatStorage();
        if (vs.ilks[ilk].rack != 0) revert ErrMultiIlk();
        vs.ilks[ilk] = Ilk({
            rack: RAY,
            fee : RAY,
            liqr: RAY,
            hook: hook,
            rho : block.timestamp,
            tart: 0,
            chop: 0, line: 0, dust: 0
        });
    }

    function safe(bytes32 i, address u)
      public returns (Spot, uint, uint)
    {
        VatStorage storage vs = getVatStorage();
        Ilk storage ilk = vs.ilks[i];
        bytes memory data = hookcall(i, abi.encodeWithSelector(
            Hook.safehook.selector, i, u
        ));
        if (data.length != 64) revert ErrHookData();
 
        (uint cut, uint ttl) = abi.decode(data, (uint, uint));
        if (block.timestamp > ttl) {
            return (Spot.Iffy, 0, 0);
        }
        // par acts as a multiplier for collateral requirements
        // par increase has same effect on cut as fee accumulation through rack
        // par decrease acts like a negative fee
        uint256 tab = vs.urns[i][u] * rmul(rmul(vs.par, ilk.rack), ilk.liqr);
        if (tab <= cut) {
            return (Spot.Safe, 0, cut);
        } else {
            uint256 rush = _DASH;
            if (cut > RAY) rush = min(rush, tab / (cut / RAY));
            return (Spot.Sunk, rush, cut);
        }
    }

    function frob(bytes32 i, address u, bytes calldata dink, int dart)
      _flog_ public
    {
        VatStorage storage vs = getVatStorage();
        Ilk storage ilk = vs.ilks[i];

        if (ilk.rack == 0) revert ErrIlkInit();

        vs.urns[i][u] = add(vs.urns[i][u], dart);
        uint art   = vs.urns[i][u];
        ilk.tart   = add(ilk.tart, dart);

        // rico mint/burn amount increases with rack
        int dtab = mul(ilk.rack, dart);
        uint tab = ilk.rack * art;

        if (dtab > 0) {
            uint wad = uint(dtab) / RAY;
            vs.debt += wad;
            vs.rest += uint(dtab) % RAY;
            getBankStorage().rico.mint(msg.sender, wad);
        } else if (dtab < 0) {
            // dtab is a rad, so burn one extra to round in system's favor
            uint wad = uint(-dtab) / RAY + 1;
            vs.rest += add(wad * RAY, dtab);
            vs.debt -= wad;
            getBankStorage().rico.burn(msg.sender, wad);
        }

        // either debt has decreased, or debt ceilings are not exceeded
        if (both(dart > 0, either(ilk.tart * ilk.rack > ilk.line, vs.debt > vs.ceil))) revert ErrDebtCeil();
        // urn has no debt, or a non-dusty amount
        if (both(art != 0, tab < ilk.dust)) revert ErrUrnDust();

        // safer if less/same art and more/same ink
        bool safer = dart <= 0;
        if (dink.length != 0) {
            bytes memory data = hookcall(i, abi.encodeWithSelector(
                Hook.frobhook.selector, msg.sender, i, u, dink, dart
            ));
            if (data.length != 32) revert ErrHookData();
            safer = both(safer, abi.decode(data, (bool)));
        }

        // urn is safer, or is safe
        (Spot spot,,) = safe(i, u);
        if (!either(safer, spot == Spot.Safe)) revert ErrNotSafe();
        // urn is safer, or urn is caller
        if (!either(safer, u == msg.sender)) revert ErrWrongUrn();
    }

    function hookcall(bytes32 i, bytes memory indata) internal returns (bytes memory outdata) {
        VatStorage storage vs = getVatStorage();
        bool success;
        (success, outdata) = vs.ilks[i].hook.delegatecall(indata);
        if (!success) {
            // bubble up revert reason, first 32 bytes is bytes length
            assembly {
                let size := mload(outdata)
                revert(add(32, outdata), size)
            }
        }
    }

    function grab(bytes32 i, address u, address k, uint rush, uint cut)
        _ward_ _flog_ external returns (bytes memory)
    {
        VatStorage storage vs = getVatStorage();
        // liquidate the urn
        Ilk storage ilk = vs.ilks[i];
        uint art = vs.urns[i][u];
        vs.urns[i][u] = 0;

        // bill is the debt hook will attempt to cover when auctioning ink
        // todo maybe make this +1?
        uint bill = rmul(ilk.chop, rmul(art, ilk.rack));

        ilk.tart -= art;

        // record the bad debt for vow to heal
        uint dtab = art * ilk.rack;
        vs.sin += dtab;

        // ink auction
        return hookcall(i, abi.encodeWithSelector(
            Hook.grabhook.selector, i, u, bill, k, rush, cut
        ));
    }

    function drip(bytes32 i)
      _ward_ _flog_ external
    {
        VatStorage storage vs = getVatStorage();
        // multiply rack by fee every second
        if (block.timestamp == vs.ilks[i].rho) return;
        uint256 prev = vs.ilks[i].rack;
        uint256 rack = grow(prev, vs.ilks[i].fee, block.timestamp - vs.ilks[i].rho);
        // difference between current and previous rack determines interest
        uint256 delt = rack - prev;
        uint256 rad  = vs.ilks[i].tart * delt;
        uint256 all  = vs.rest + rad;
        vs.ilks[i].rho  = block.timestamp;
        vs.ilks[i].rack = rack;
        vs.debt         = vs.debt + all / RAY;
        // tart * rack is a rad, interest is a wad, rest is the change
        vs.rest         = all % RAY;
        // optimistically mint the interest to the vow
        getBankStorage().rico.mint(address(this), all / RAY);
    }

    function heal(uint wad) _flog_ external {
        VatStorage storage vs = getVatStorage();
        // burn rico to pay down sin
        uint256 rad = wad * RAY;
        vs.sin = vs.sin - rad;
        vs.debt   = vs.debt   - wad;
        getBankStorage().rico.burn(msg.sender, wad);
    }

    function flash(address code, bytes calldata data)
      external returns (bytes memory result) {
        VatStorage storage vs = getVatStorage();
        if (vs.lock == LOCKED) revert ErrLock();
        vs.lock = LOCKED;
        bool ok;
        getBankStorage().rico.mint(code, _MINT);
        (ok, result) = code.call(data);
        require(ok, string(result));
        getBankStorage().rico.burn(code, _MINT);
        vs.lock = UNLOCKED;
    }

    function filk(bytes32 ilk, bytes32 key, uint val)
      _ward_ _flog_ external
    {
        VatStorage storage vs = getVatStorage();
        Ilk storage i = vs.ilks[ilk];
               if (key == "line") { i.line = val;
        } else if (key == "dust") { i.dust = val;
        } else if (key == "hook") { i.hook = address(bytes20(bytes32(val)));
        } else if (key == "liqr") { i.liqr = val;
        } else if (key == "chop") { i.chop = val;
        } else if (key == "fee") {
            if (val < RAY)                revert ErrFeeMin();
            if (block.timestamp != i.rho) revert ErrFeeRho();
            i.fee = val;
        } else { revert ErrWrongKey(); }
    }

    function filh(bytes32 ilk, bytes32 key, bytes32 val)
      _ward_ _flog_ external {
        hookcall(
            ilk, abi.encodeWithSignature("file(bytes32,bytes32)", key, val)
        );
    }

    function filhi(bytes32 ilk, bytes32 key, bytes32 idx, bytes32 val)
      _ward_ _flog_ external {
        hookcall(
            ilk, abi.encodeWithSignature(
                "fili(bytes32,bytes32,bytes32)", key, idx, val
        ));
    }

    function filhi2(bytes32 ilk, bytes32 key, bytes32 idx0, bytes32 idx1, bytes32 val)
      _ward_ _flog_ external {
        hookcall(ilk, abi.encodeWithSignature("fili2(bytes32,bytes32,bytes32,bytes32)", key, idx0, idx1, val));
    }
}
