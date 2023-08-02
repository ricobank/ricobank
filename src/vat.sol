// SPDX-License-Identifier: AGPL-3.0-or-later

/// vat.sol -- Rico CDP database

// Copyright (C) 2021-2023 halys
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

pragma solidity ^0.8.19;

import { Math } from './mixin/math.sol';
import { Flog } from './mixin/flog.sol';

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
    function ink(bytes32 i, address u) external view returns (bytes memory) {
        return abi.decode(_hookview(i, abi.encodeWithSelector(
            Hook.ink.selector, i, u
        )), (bytes));
    }
    function MINT() pure external returns (uint) {return _MINT;}

    enum Spot {Sunk, Iffy, Safe}

    uint256 constant _MINT = 2 ** 128;

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
    error ErrSafeBail();
    error ErrHookCallerNotBank();

    function init(bytes32 ilk, address hook)
      onlyOwner _flog_ external
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
        emit NewPalm1('rack', ilk, bytes32(RAY));
        emit NewPalm1('fee', ilk, bytes32(RAY));
        emit NewPalm1('hook', ilk, bytes32(bytes20(hook)));
        emit NewPalm1('rho', ilk, bytes32(block.timestamp));
        emit NewPalm1('tart', ilk, bytes32(uint(0)));
        emit NewPalm1('chop', ilk, bytes32(uint(0)));
        emit NewPalm1('line', ilk, bytes32(uint(0)));
        emit NewPalm1('dust', ilk, bytes32(uint(0)));
    }

    function safe(bytes32 i, address u)
      public view returns (Spot, uint, uint)
    {
        VatStorage storage vs = getVatStorage();
        Ilk storage ilk = vs.ilks[i];
        bytes memory data = _hookview(i, abi.encodeWithSelector(
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
            uint256 rush = type(uint256).max;
            if (cut > RAY) rush = tab / (cut / RAY);
            return (Spot.Sunk, rush, cut);
        }
    }

    function frob(bytes32 i, address u, bytes calldata dink, int dart)
      _flog_ public
    {
        VatStorage storage vs = getVatStorage();
        Ilk storage ilk = vs.ilks[i];

        if (ilk.rack == 0) revert ErrIlkInit();

        uint art   = add(vs.urns[i][u], dart);
        vs.urns[i][u] = art;
        emit NewPalm2('art', i, bytes32(bytes20(u)), bytes32(art));

        ilk.tart   = add(ilk.tart, dart);
        emit NewPalm1('tart', i, bytes32(ilk.tart));

        // rico mint/burn amount increases with rack
        int dtab = mul(ilk.rack, dart);
        uint tab = ilk.rack * art;

        if (dtab > 0) {
            uint wad = uint(dtab) / RAY;
            vs.debt += wad;
            emit NewPalm0('debt', bytes32(vs.debt));
            vs.rest += uint(dtab) % RAY;
            emit NewPalm0('rest', bytes32(vs.rest));
            getBankStorage().rico.mint(msg.sender, wad);
        } else if (dtab < 0) {
            // dtab is a rad, so burn one extra to round in system's favor
            uint wad = uint(-dtab) / RAY + 1;
            vs.rest += add(wad * RAY, dtab);
            emit NewPalm0('rest', bytes32(vs.rest));
            vs.debt -= wad;
            emit NewPalm0('debt', bytes32(vs.debt));
            getBankStorage().rico.burn(msg.sender, wad);
        }

        // either debt has decreased, or debt ceilings are not exceeded
        if (both(dart > 0, either(ilk.tart * ilk.rack > ilk.line, vs.debt > vs.ceil))) revert ErrDebtCeil();

        // urn has no debt, or a non-dusty amount
        if (both(art != 0, tab < ilk.dust)) revert ErrUrnDust();

        // safer if less/same art and more/same ink
        bool safer = dart <= 0;
        if (dink.length != 0) {
            bytes memory data = _hookcall(i, abi.encodeWithSelector(
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

    function bail(bytes32 i, address u) _flog_ external returns (bytes memory)
    {
        _drip(i);
        (Spot spot, uint rush, uint cut) = safe(i, u);
        if (spot != Spot.Sunk) revert ErrSafeBail();

        VatStorage storage vs = getVatStorage();
        // liquidate the urn
        Ilk storage ilk = vs.ilks[i];
        uint art = vs.urns[i][u];
        vs.urns[i][u] = 0;
        emit NewPalm2('art', i, bytes32(bytes20(u)), bytes32(uint(0)));

        // bill is the debt hook will attempt to cover when auctioning ink
        // todo maybe make this +1?
        uint bill = rmul(ilk.chop, rmul(art, ilk.rack));

        ilk.tart -= art;
        emit NewPalm1('tart', i, bytes32(ilk.tart));

        // record the bad debt for vow to heal
        uint dtab = art * ilk.rack;
        vs.sin += dtab;
        emit NewPalm0('sin', bytes32(vs.sin));

        // ink auction
        return abi.decode(_hookcall(i, abi.encodeWithSelector(
            Hook.bailhook.selector, i, u, bill, msg.sender, rush, cut
        )), (bytes));
    }

    function drip(bytes32 i) _flog_ external { _drip(i); }

    // drip without flog
    function _drip(bytes32 i) internal {
        VatStorage storage vs = getVatStorage();
        Ilk storage ilk       = vs.ilks[i];
        if (block.timestamp == ilk.rho) return;

        // multiply rack by fee every second
        uint prev = ilk.rack;
        uint rack = grow(prev, ilk.fee, block.timestamp - ilk.rho);

        // difference between current and previous rack determines interest
        uint256 delt = rack - prev;
        uint256 rad  = ilk.tart * delt;
        uint256 all  = vs.rest + rad;

        ilk.rho      = block.timestamp;
        emit NewPalm1('rho', i, bytes32(block.timestamp));

        ilk.rack     = rack;
        emit NewPalm1('rack', i, bytes32(rack));

        vs.debt      = vs.debt + all / RAY;
        emit NewPalm0('debt', bytes32(vs.debt));

        // tart * rack is a rad, interest is a wad, rest is the change
        vs.rest      = all % RAY;
        emit NewPalm0('rest', bytes32(vs.rest));

        // optimistically mint the interest
        getBankStorage().rico.mint(address(this), all / RAY);
    }

    function heal(uint wad) _flog_ external {
        VatStorage storage vs = getVatStorage();
        // burn rico to pay down sin
        uint256 rad = wad * RAY;

        vs.sin  = vs.sin - rad;
        emit NewPalm0('sin', bytes32(vs.sin));

        vs.debt = vs.debt   - wad;
        emit NewPalm0('debt', bytes32(vs.debt));

        getBankStorage().rico.burn(msg.sender, wad);
    }

    function flash(address code, bytes calldata data)
      external returns (bytes memory result) {
        // lock->mint->call->burn->unlock
        VatStorage storage vs = getVatStorage();
        if (vs.lock == LOCKED) revert ErrLock();
        vs.lock = LOCKED;

        getBankStorage().rico.mint(code, _MINT);
        bool ok;
        (ok, result) = code.call(data);
        if (!ok) bubble(result);
        getBankStorage().rico.burn(code, _MINT);

        vs.lock = UNLOCKED;
    }

    function filk(bytes32 ilk, bytes32 key, bytes32 val)
      onlyOwner _flog_ external
    {
        uint _val = uint(val);
        VatStorage storage vs = getVatStorage();
        Ilk storage i = vs.ilks[ilk];
               if (key == "line") { i.line = _val;
        } else if (key == "dust") { i.dust = _val;
        } else if (key == "hook") { i.hook = address(bytes20(val));
        } else if (key == "liqr") { i.liqr = _val;
        } else if (key == "chop") { i.chop = _val;
        } else if (key == "fee") {
            if (_val < RAY)                revert ErrFeeMin();
            if (block.timestamp != i.rho) revert ErrFeeRho();
            i.fee = _val;
        } else { revert ErrWrongKey(); }
        emit NewPalm1(key, ilk, bytes32(val));
    }

    function _hookcall(bytes32 i, bytes memory indata)
      internal returns (bytes memory outdata) {
        bool ok;
        (ok, outdata) = getVatStorage().ilks[i].hook.delegatecall(indata);
        if (!ok) bubble(outdata);
    }

    function _hookview(bytes32 i, bytes memory indata)
      internal view returns (bytes memory outdata) {
        bool ok;
        (ok, outdata) = address(this).staticcall(
            abi.encodeWithSelector(Vat.hookcallext.selector, i, indata)
        );
        if (!ok) bubble(outdata);
        outdata = abi.decode(outdata, (bytes));
    }

    function hookcallext(bytes32 i, bytes memory indata)
      external returns (bytes memory) {
        if (msg.sender != address(this)) revert ErrHookCallerNotBank();
        return _hookcall(i, indata);
    }

    function filh(bytes32 ilk, bytes32 key, bytes32 val)
      onlyOwner _flog_ external {
        _hookcall(ilk, abi.encodeWithSignature(
            "file(bytes32,bytes32)", key, val
        ));
    }

    function filhi(bytes32 ilk, bytes32 key, bytes32 idx, bytes32 val)
      onlyOwner _flog_ external {
        _hookcall(ilk, abi.encodeWithSignature(
            "fili(bytes32,bytes32,bytes32)", key, idx, val
        ));
    }

    function filhi2(bytes32 ilk, bytes32 key, bytes32 idx0, bytes32 idx1, bytes32 val)
      onlyOwner _flog_ external {
        _hookcall(ilk, abi.encodeWithSignature(
            "fili2(bytes32,bytes32,bytes32,bytes32)", key, idx0, idx1, val
        ));
    }

    function geth(bytes32 ilk, bytes32 key)
      external view returns (bytes32) {
        return abi.decode(
            _hookview(ilk, abi.encodeWithSignature(
                "get(bytes32)", key
            )), (bytes32)
        );
    }

    function gethi(bytes32 ilk, bytes32 key, bytes32 idx)
      external view returns (bytes32) {
        return abi.decode(
            _hookview(ilk, abi.encodeWithSignature(
                "geti(bytes32,bytes32)", key, idx
            )), (bytes32)
        );
    }

    function gethi2(bytes32 ilk, bytes32 key, bytes32 idx0, bytes32 idx1)
      external view returns (bytes32) {
        return abi.decode(
            _hookview(ilk, abi.encodeWithSignature(
                "geti2(bytes32,bytes32,bytes32)", key, idx0, idx1
            )), (bytes32)
        );
    }
}
