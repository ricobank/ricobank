// SPDX-License-Identifier: AGPL-3.0-or-later

/// vat.sol -- Rico CDP database

// Copyright (C) 2021-2024 halys
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

import { Bank } from "./bank.sol";
import { Hook } from "./hook/hook.sol";

contract Vat is Bank {
    function ilks(bytes32 i) external view returns (Ilk memory) {
        return getVatStorage().ilks[i];
    }
    function urns(bytes32 i, address u) external view returns (uint) {
        return getVatStorage().urns[i][u];
    }
    function joy()  external view returns (uint) {return getVatStorage().joy;}
    function sin()  external view returns (uint) {return getVatStorage().sin;}
    function rest() external view returns (uint) {return getVatStorage().rest;}
    function debt() external view returns (uint) {return getVatStorage().debt;}
    function ceil() external view returns (uint) {return getVatStorage().ceil;}
    function par()  external view returns (uint) {return getVatStorage().par;}
    function ink(bytes32 i, address u) external view returns (bytes memory) {
        return abi.decode(_hookview(i, abi.encodeWithSelector(
            Hook.ink.selector, i, u
        )), (bytes));
    }
    function MINT() external pure returns (uint) {return _MINT;}
    function FEE_MAX() external pure returns (uint) {return _FEE_MAX;}

    enum Spot {Sunk, Iffy, Safe}

    uint256 constant _MINT    = 2 ** 128;
    uint256 constant _FEE_MAX = 1000000072964521287979890107; // ~10x/yr

    error ErrIlkInit();
    error ErrNotSafe();
    error ErrUrnDust();
    error ErrDebtCeil();
    error ErrMultiIlk();
    error ErrHookData();
    error ErrLock();
    error ErrSafeBail();
    error ErrHookCallerNotBank();
    error ErrNoHook();

    // lock for CDP manipulation functions
    // not necessary for drip, because frob and bail drip
    modifier _lock_ {
        VatStorage storage vs = getVatStorage();
        if (vs.lock == LOCKED) revert ErrLock();
        vs.lock = LOCKED;
        _;
        vs.lock = UNLOCKED;
    }

    function init(bytes32 ilk, address hook)
      external payable onlyOwner _flog_
    {
        VatStorage storage vs = getVatStorage();
        if (vs.ilks[ilk].rack != 0) revert ErrMultiIlk();
        vs.ilks[ilk] = Ilk({
            rack: RAY,
            fee : RAY,
            hook: hook,
            rho : block.timestamp,
            tart: 0,
            chop: 0, line: 0, dust: 0
        });
        emit NewPalm1("rack", ilk, bytes32(RAY));
        emit NewPalm1("fee",  ilk, bytes32(RAY));
        emit NewPalm1("hook", ilk, bytes32(bytes20(hook)));
        emit NewPalm1("rho",  ilk, bytes32(block.timestamp));
        emit NewPalm1("tart", ilk, bytes32(uint(0)));
        emit NewPalm1("chop", ilk, bytes32(uint(0)));
        emit NewPalm1("line", ilk, bytes32(uint(0)));
        emit NewPalm1("dust", ilk, bytes32(uint(0)));
    }

    function safe(bytes32 i, address u)
      public view returns (Spot, uint, uint)
    {
        VatStorage storage vs = getVatStorage();
        Ilk storage ilk = vs.ilks[i];
        bytes memory data = _hookview(i, abi.encodeWithSelector(
            Hook.safehook.selector, i, u
        ));
        if (data.length != 96) revert ErrHookData();
 
        (uint tot, uint cut, uint ttl) = abi.decode(data, (uint, uint, uint));
        uint art = vs.urns[i][u];
        if (art == 0) return (Spot.Safe, RAY, tot);
        if (block.timestamp > ttl) return (Spot.Iffy, 0, tot);

        // par acts as a multiplier for collateral requirements
        // par increase has same effect on cut as fee accumulation through rack
        // par decrease acts like a negative fee
        uint256 tab = art * rmul(vs.par, ilk.rack);
        if (tab <= cut) {
            return (Spot.Safe, RAY, tot);
        } else {
            uint256 deal = cut / (tab / RAY);
            return (Spot.Sunk, deal, tot);
        }
    }

    // modify CDP
    // locked with bail to make individual urn manipulations atomic
    // e.g. avoid making the urn safe in the middle of an unsafe borrow
    function frob(bytes32 i, address u, bytes calldata dink, int dart)
      external payable _flog_ _lock_
    {
        VatStorage storage vs = getVatStorage();
        Ilk storage ilk = vs.ilks[i];

        uint rack = _drip(i);

        // modify normalized debt
        uint256 art   = add(vs.urns[i][u], dart);
        vs.urns[i][u] = art;
        emit NewPalm2("art", i, bytes32(bytes20(u)), bytes32(art));

        // keep track of total so it denorm doesn't exceed line
        ilk.tart      = add(ilk.tart, dart);
        emit NewPalm1("tart", i, bytes32(ilk.tart));

        uint _debt;
        uint _rest;
        {
            // rico mint/burn amount increases with rack
            int dtab = mul(rack, dart);
            if (dtab > 0) {
                // borrow
                // dtab is a rad, debt is a wad
                uint wad = uint(dtab) / RAY;
                _debt    = vs.debt += wad;
                emit NewPalm0("debt", bytes32(_debt));

                // remainder is a ray
                _rest = vs.rest += uint(dtab) % RAY;
                emit NewPalm0("rest", bytes32(_rest));

                getBankStorage().rico.mint(msg.sender, wad);
            } else if (dtab < 0) {
                // paydown
                // dtab is a rad, so burn one extra to round in system's favor
                uint wad = (uint(-dtab) / RAY) + 1;
                _debt = vs.debt -= wad;
                emit NewPalm0("debt", bytes32(_debt));

                // accrue excess from rounding to rest
                _rest = vs.rest += add(wad * RAY, dtab);
                emit NewPalm0("rest", bytes32(_rest));

                getBankStorage().rico.burn(msg.sender, wad);
            }
        }

        // safer if less/same art and more/same ink
        Hook.FHParams memory p = Hook.FHParams(msg.sender, i, u, dink, dart);
        bytes memory data      = _hookcall(
            i, abi.encodeWithSelector(Hook.frobhook.selector, p)
        );
        if (data.length != 32) revert ErrHookData();

        // urn is safer, or it is safe
        if (!abi.decode(data, (bool))) {
            (Spot spot,,) = safe(i, u);
            if (spot != Spot.Safe) revert ErrNotSafe();
        }

        // urn has no debt, or a non-dusty amount
        if (art != 0 && rack * art < ilk.dust) revert ErrUrnDust();

        // either debt has decreased, or debt ceilings are not exceeded
        if (dart > 0) {
            if (ilk.tart * rack > ilk.line) revert ErrDebtCeil();
            else if (_debt + (_rest / RAY) > vs.ceil) revert ErrDebtCeil();
        }
    }

    // liquidate CDP
    // locked with frob to make individual urn manipulations atomic
    // e.g. avoid making the urn safe in the middle of a liquidation
    function bail(bytes32 i, address u)
      external payable _flog_ _lock_ returns (bytes memory)
    {
        uint rack = _drip(i);
        uint deal; uint tot;
        {
            Spot spot;
            (spot, deal, tot) = safe(i, u);
            if (spot != Spot.Sunk) revert ErrSafeBail();
        }
        VatStorage storage vs = getVatStorage();
        Ilk storage ilk = vs.ilks[i];

        uint art = vs.urns[i][u];
        delete vs.urns[i][u];
        emit NewPalm2("art", i, bytes32(bytes20(u)), bytes32(uint(0)));

        // bill is the debt hook will attempt to cover when auctioning ink
        uint dtab = art * rack;
        uint owed = dtab / RAY;
        uint bill = rmul(ilk.chop, owed);

        ilk.tart -= art;
        emit NewPalm1("tart", i, bytes32(ilk.tart));

        if (vs.sin / RAY <= vs.joy && (vs.sin + dtab) / RAY > vs.joy ) {
            getVowStorage().ramp.bel = block.timestamp;
            emit NewPalm0("bel", bytes32(block.timestamp));
        }

        // record the bad debt for vow to heal
        vs.sin += dtab;
        emit NewPalm0("sin", bytes32(vs.sin));

        // ink auction
        Hook.BHParams memory p = Hook.BHParams(
            i, u, bill, owed, msg.sender, deal, tot
        );
        return abi.decode(_hookcall(
            i, abi.encodeWithSelector(Hook.bailhook.selector, p)
        ), (bytes));
    }

    function drip(bytes32 i) external payable _flog_ { _drip(i); }

    // drip without flog
    function _drip(bytes32 i) internal returns (uint rack) {
        VatStorage storage vs = getVatStorage();
        Ilk storage ilk       = vs.ilks[i];
        // multiply rack by fee every second
        uint prev = ilk.rack;
        if (prev == 0) revert ErrIlkInit();
 
        if (block.timestamp == ilk.rho) {
            return ilk.rack;
        }

        // multiply rack by fee every second
        rack = grow(prev, ilk.fee, block.timestamp - ilk.rho);

        // difference between current and previous rack determines interest
        uint256 delt = rack - prev;
        uint256 rad  = ilk.tart * delt;
        uint256 all  = vs.rest + rad;

        ilk.rho      = block.timestamp;
        emit NewPalm1("rho", i, bytes32(block.timestamp));

        ilk.rack     = rack;
        emit NewPalm1("rack", i, bytes32(rack));

        vs.debt      = vs.debt + (all / RAY);
        emit NewPalm0("debt", bytes32(vs.debt));

        // tart * rack is a rad, interest is a wad, rest is the change
        vs.rest      = all % RAY;
        emit NewPalm0("rest", bytes32(vs.rest));

        vs.joy       = vs.joy + (all / RAY);
        emit NewPalm0("joy", bytes32(vs.joy));
    }

    // flash borrow
    // locked with itself to avoid flashing more than MINT
    function flash(address code, bytes calldata data)
      external payable returns (bytes memory result) {
        // lock->mint->call->burn->unlock
        VatStorage storage vs = getVatStorage();
        if (vs.flock == LOCKED) revert ErrLock();
        vs.flock = LOCKED;

        getBankStorage().rico.mint(code, _MINT);
        bool ok;
        (ok, result) = code.call(data);
        if (!ok) bubble(result);
        getBankStorage().rico.burn(code, _MINT);

        vs.flock = UNLOCKED;
    }

    function filk(bytes32 ilk, bytes32 key, bytes32 val)
      external payable onlyOwner _flog_
    {
        uint _val = uint(val);
        VatStorage storage vs = getVatStorage();
        Ilk storage i = vs.ilks[ilk];
               if (key == "line") { i.line = _val;
        } else if (key == "dust") { i.dust = _val;
        } else if (key == "hook") { i.hook = address(bytes20(val));
        } else if (key == "chop") {
            must(_val, RAY, 10 * RAY);
            i.chop = _val;
        } else if (key == "fee") {
            must(_val, RAY, _FEE_MAX);
            _drip(ilk);
            i.fee = _val;
        } else { revert ErrWrongKey(); }
        emit NewPalm1(key, ilk, bytes32(val));
    }

    // delegatecall the ilk's hook
    function _hookcall(bytes32 i, bytes memory indata)
      internal returns (bytes memory outdata) {
        // call will succeed if nonzero hook has no code (i.e. EOA)
        address hook = getVatStorage().ilks[i].hook;
        if (hook == address(0)) revert ErrNoHook();

        bool ok;
        (ok, outdata) = hook.delegatecall(indata);
        if (!ok) bubble(outdata);
    }

    // similar to _hookcall, but uses staticcall to avoid modifying state
    // can't delegatecall within a view function
    // so, _hookview calls hookcallext instead, which delegatecalls _hookcall
    function _hookview(bytes32 i, bytes memory indata)
      internal view returns (bytes memory outdata) {
        bool ok;
        (ok, outdata) = address(this).staticcall(
            abi.encodeWithSelector(Vat.hookcallext.selector, i, indata)
        );
        if (!ok) bubble(outdata);
        outdata = abi.decode(outdata, (bytes));
    }

    // helps caller call hook functions without delegatecall
    function hookcallext(bytes32 i, bytes memory indata)
      external payable returns (bytes memory) {
        if (msg.sender != address(this)) revert ErrHookCallerNotBank();
        return _hookcall(i, indata);
    }

    function filh(bytes32 ilk, bytes32 key, bytes32[] calldata xs, bytes32 val)
      external payable onlyOwner _flog_ {
        _hookcall(ilk, abi.encodeWithSignature(
            "file(bytes32,bytes32,bytes32[],bytes32)", key, ilk, xs, val
        ));
    }

    function geth(bytes32 ilk, bytes32 key, bytes32[] calldata xs)
      external view returns (bytes32) {
        return abi.decode(
            _hookview(ilk, abi.encodeWithSignature(
                "get(bytes32,bytes32,bytes32[])", key, ilk, xs
            )), (bytes32)
        );
    }

}
