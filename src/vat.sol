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

pragma solidity 0.8.18;

import './mixin/lock.sol';
import './mixin/math.sol';
import './mixin/ward.sol';
import './mixin/flog.sol';

import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { Gem }      from '../lib/gemfab/src/gem.sol';

interface Hook {
    function frobhook(
        address urn, bytes32 i, address u, int dink, int dart
    ) external;
    function grabhook(
        address urn, bytes32 i, address u, int dink, int dart, uint bill
    ) external returns (uint);
}

contract Vat is Lock, Math, Ward, Flog {
    struct Ilk {
        uint256 tart;  // [wad] Total Normalised Debt
        uint256 rack;  // [ray] Accumulated Rate

        address fsrc;  // [obj] feedbase `src` address
        bytes32 ftag;  // [tag] feedbase `tag` bytes32

        uint256 line;  // [rad] Debt Ceiling
        uint256 dust;  // [rad] Urn Debt Floor

        uint256  fee;  // [ray] Collateral-specific, per-second compounding rate
        uint256  rho;  // [sec] Time of last drip

        uint256 chop;  // [ray] Liquidation Penalty
        uint256 liqr;  // [ray] Liquidation Ratio

        address hook;  // [obj] Frob/grab hook
    }

    struct Urn {
        uint256 ink;   // [wad] Locked Collateral
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

    uint256 public rest;  // [rad] Remainder from
    uint256 public debt;  // [rad] Total Rico Issued
    uint256 public ceil;  // [rad] Total Debt Ceiling
    uint256 public par;   // [ray] System Price (rico/ref)

    Feedbase public feeds;
    Gem      public rico;

    constructor() {
        par = RAY;
    }

    function init(bytes32 ilk, address fsrc, bytes32 ftag)
      _ward_ _flog_ external
    {
        if (ilks[ilk].rack != 0) revert ErrMultiIlk();
        ilks[ilk] = Ilk({
            rack: RAY,
            fee : RAY,
            liqr: RAY,
            hook: address(0),
            rho : block.timestamp,
            tart: 0,
            fsrc: fsrc,
            ftag: ftag,
            chop: 0, line: 0, dust: 0
        });
    }

    function safe(bytes32 i, address u)
      public view returns (Spot)
    {
        Urn storage urn = urns[i][u];
        Ilk storage ilk = ilks[i];
        (bytes32 mark_, uint ttl) = feeds.pull(ilk.fsrc, ilk.ftag);
        uint mark = uint(mark_);
        if (block.timestamp > ttl) {
            return Spot.Iffy;
        }
        uint256    liq = rmul(mark, ilk.liqr);
        uint256    tab = urn.art * rmul(par, ilk.rack);
        uint256    cut = urn.ink * liq;
        if (tab <= cut) {
            return Spot.Safe;
        } else {
            return Spot.Sunk;
        }
    }

    function frob(bytes32 i, address u, int dink, int dart)
      _flog_ public
    {
        Urn storage urn = urns[i][u];
        Ilk storage ilk = ilks[i];

        // ilk has been initialised
        if (ilk.rack == 0) revert ErrIlkInit();

        urn.ink = add(urn.ink, dink);
        urn.art = add(urn.art, dart);
        ilk.tart = add(ilk.tart, dart);

        int dtab = mul(ilk.rack, dart);
        uint tab = ilk.rack * urn.art;
        debt     = add(debt, dtab);

        // either debt has decreased, or debt ceilings are not exceeded
        if (both(dart > 0, either(ilk.tart * ilk.rack > ilk.line, debt > ceil))) revert ErrDebtCeil();
        // urn is either less risky than before, or it is safe
        if (both(either(dart > 0, dink < 0), safe(i, u) != Spot.Safe)) revert ErrNotSafe();
        // either urn is more safe, or urn is caller
        if (both(either(dart > 0, dink < 0), u != msg.sender)) revert ErrWrongUrn();
        // urn has no debt, or a non-dusty amount
        if (both(urn.art != 0, tab < ilk.dust)) revert ErrUrnDust();

        if (dtab > 0) {
            rico.mint(msg.sender, uint(dtab) / RAY);
            rest += uint(dtab) % RAY;
        } else if (dtab < 0) {
            uint wad = uint(-dtab) / RAY + 1;
            rest += add(wad * RAY, dtab);
            rico.burn(msg.sender, wad);
        }

        Hook(ilk.hook).frobhook(msg.sender, i, u, dink, dart);
    }

    function grab(bytes32 i, address u, int dink, int dart)
        _ward_ _flog_ external returns (uint bill, uint aid)
    {
        Urn storage urn = urns[i][u];
        Ilk storage ilk = ilks[i];

        uint tab  = rmul(urn.art, ilk.rack);
        bill = rmul(ilk.chop, tab);

        urn.ink  = add(urn.ink, dink);
        urn.art  = add(urn.art, dart);
        ilk.tart = add(ilk.tart, dart);

        int dtab = mul(ilk.rack, dart);

        address vow = msg.sender;
        sin[vow]    = sub(sin[vow],    dtab);

        aid = Hook(ilk.hook).grabhook(msg.sender, i, u, dink, dart, bill);
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
        rest         = all % RAY;
        ilks[i].rho  = block.timestamp;
        ilks[i].rack = rack;
        debt         = debt + rad;
        rico.mint(vow, all / RAY);
    }

    function heal(uint wad) _flog_ external {
        uint256 rad = wad * RAY;
        address u = msg.sender;
        sin[u] = sin[u] - rad;
        debt   = debt   - rad;
        rico.burn(u, wad);
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
               if (key == "feeds") { feeds = Feedbase(val);
        } else if (key == "rico" ) { rico  = Gem(val);
        } else { revert ErrWrongKey(); }
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
