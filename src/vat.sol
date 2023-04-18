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

pragma solidity 0.8.19;

import './mixin/lock.sol';
import './mixin/math.sol';
import './mixin/flog.sol';

import { Ward } from '../lib/feedbase/src/mixin/ward.sol';
import { Gem }  from '../lib/gemfab/src/gem.sol';
import { Hook } from './hook/hook.sol';

contract Vat is Lock, Math, Ward, Flog {
    struct Ilk {
        uint256 tart;  // [wad] Total Normalised Debt
        uint256 rack;  // [ray] Accumulated Rate

        uint256 line;  // [rad] Debt Ceiling
        uint256 dust;  // [rad] Urn Debt Floor

        uint256  fee;  // [ray] Collateral-specific, per-second compounding rate
        uint256  rho;  // [sec] Time of last drip

        uint256 chop;  // [ray] Liquidation Penalty
        uint256 liqr;  // [ray] Liquidation Ratio

        address hook;  // [obj] Frob/grab hook
    }

    struct Urn {
        uint256 art;   // [wad] Normalised Debt
    }

    mapping (bytes32 ilk => Ilk)                           public ilks;
    mapping (bytes32 ilk => mapping (address usr => Urn )) public urns;
    mapping (address usr => uint256)                       public sin;  // [rad]

    enum Spot {Sunk, Iffy, Safe}

    error ErrFeeMin();
    error ErrFeeRho();
    error ErrIlkInit();
    error ErrNotSafe();
    error ErrUrnDust();
    error ErrDebtCeil();
    error ErrMultiIlk();
    error ErrTransfer();
    error ErrWrongKey();
    error ErrWrongUrn();

    uint256 public constant MINT = 2**128;

    uint256 public rest;  // [rad] Remainder from
    uint256 public debt;  // [wad] Total Rico Issued
    uint256 public ceil;  // [wad] Total Debt Ceiling
    uint256 public par;   // [ray] System Price (rico/ref)

    Gem public rico;

    constructor() {
        par = RAY;
    }

    function init(bytes32 ilk, address hook)
      _ward_ _flog_ external
    {
        if (ilks[ilk].rack != 0) revert ErrMultiIlk();
        ilks[ilk] = Ilk({
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
      public view returns (Spot)
    {
        Urn storage urn = urns[i][u];
        Ilk storage ilk = ilks[i];
        (bytes32 cut_, uint ttl) = Hook(ilk.hook).safehook(i, u);
        uint cut = uint(cut_);
        if (block.timestamp > ttl) {
            return Spot.Iffy;
        }
        uint256    tab = urn.art * rmul(rmul(par, ilk.rack), ilk.liqr);
        if (tab <= cut) {
            return Spot.Safe;
        } else {
            return Spot.Sunk;
        }
    }

    function frob(bytes32 i, address u, bytes calldata dink, int dart)
      _flog_ public
    {
        Urn storage urn = urns[i][u];
        Ilk storage ilk = ilks[i];

        // ilk has been initialised
        if (ilk.rack == 0) revert ErrIlkInit();

        urn.art  = add(urn.art,  dart);
        ilk.tart = add(ilk.tart, dart);

        int dtab = mul(ilk.rack, dart);
        uint tab = ilk.rack * urn.art;

        if (dtab > 0) {
            uint wad = uint(dtab) / RAY;
            debt += wad;
            rest += uint(dtab) % RAY;
            rico.mint(msg.sender, wad);
        } else if (dtab < 0) {
            uint wad = uint(-dtab) / RAY + 1;
            rest += add(wad * RAY, dtab);
            debt -= wad;
            rico.burn(msg.sender, wad);
        }

        // either debt has decreased, or debt ceilings are not exceeded
        if (both(dart > 0, either(ilk.tart * ilk.rack > ilk.line, debt > ceil))) revert ErrDebtCeil();
        // urn has no debt, or a non-dusty amount
        if (both(urn.art != 0, tab < ilk.dust)) revert ErrUrnDust();

        bool inksafer = true;
        if (dink.length != 0) {
            // manage ink
            inksafer = Hook(ilk.hook).frobhook(msg.sender, i, u, dink, dart);
        }
        bool safer = both(dart <= 0, inksafer);
        // urn is safer, or is safe
        if (both(!safer, safe(i, u) != Spot.Safe)) revert ErrNotSafe();
        // urn is safer, or urn is caller
        if (both(!safer, u != msg.sender)) revert ErrWrongUrn();
    }

    function grab(bytes32 i, address u, address k)
        _ward_ _flog_ external returns (uint aid)
    {
        Urn storage urn = urns[i][u];
        Ilk storage ilk = ilks[i];
        uint art = urn.art;

        uint bill = rmul(ilk.chop, rmul(art, ilk.rack));

        urn.art = 0;
        ilk.tart -= art;

        uint dtab = art * ilk.rack;
        sin[msg.sender] += dtab;

        aid = Hook(ilk.hook).grabhook(msg.sender, i, u, art, bill, payable(k));
    }

    function prod(uint256 jam)
      _ward_ _flog_ external
    {
        par = jam;
    }

    function drip(bytes32 i)
      _ward_ _flog_ external
    {
        if (block.timestamp == ilks[i].rho) return;
        address vow  = msg.sender;
        uint256 prev = ilks[i].rack;
        uint256 rack = grow(prev, ilks[i].fee, block.timestamp - ilks[i].rho);
        uint256 delt = rack - prev;
        uint256 rad  = ilks[i].tart * delt;
        uint256 all  = rest + rad;
        ilks[i].rho  = block.timestamp;
        ilks[i].rack = rack;
        debt         = debt + all / RAY;
        rest         = all % RAY;
        rico.mint(vow, all / RAY);
    }

    function heal(uint wad) _flog_ external {
        uint256 rad = wad * RAY;
        address u = msg.sender;
        sin[u] = sin[u] - rad;
        debt   = debt   - wad;
        rico.burn(u, wad);
    }

    function flash(address code, bytes calldata data)
      _lock_ external returns (bytes memory result) {
        bool ok;
        rico.mint(code, MINT);
        (ok, result) = code.call(data);
        require(ok, string(result));
        rico.burn(code, MINT);
    }

    function file(bytes32 key, uint256 val)
      _ward_ _flog_ external
    {
        if (key == "ceil") { ceil = val;
        } else { revert ErrWrongKey(); }
    }
    function link(bytes32 key, address val)
      _ward_ _flog_ external
    {
        if (key == "rico") rico = Gem(val);
        else revert ErrWrongKey();
    }
    function filk(bytes32 ilk, bytes32 key, uint val)
      _ward_ _flog_ external
    {
        Ilk storage i = ilks[ilk];
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
}
