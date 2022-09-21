// SPDX-License-Identifier: AGPL-3.0-or-later

/// vat.sol -- Dai CDP database

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

pragma solidity 0.8.15;

import './mixin/math.sol';
import './mixin/ward.sol';
import './mixin/flog.sol';

import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';

interface Hook {
    function hook(address urn, bytes calldata data) external;
}

contract Vat is Math, Ward, Flog {
    struct Ilk {
        uint256 tart;  // [wad] Total Normalised Debt
        uint256 rack;  // [ray] Accumulated Rate

        address fsrc;  // [obj] feedbase `src` address
        bytes32 ftag;  // [tag] feedbase `tag` bytes32

        uint256 line;  // [rad] Debt Ceiling
        uint256 dust;  // [rad] Urn Debt Floor

        uint256 duty;  // [ray] Collateral-specific, per-second compounding rate
        uint256  rho;  // [sec] Time of last drip

        uint256 chop;  // [ray] Liquidation Penalty
        uint256 liqr;  // [ray] Liquidation Ratio

        address hook;  // [obj] Frob hook

        address gem;   // [gem] Collateral token
    }

    struct Urn {
        uint256 ink;   // [wad] Locked Collateral
        uint256 art;   // [wad] Normalised Debt
    }

    mapping (bytes32 => Ilk)                       public ilks;
    mapping (bytes32 => mapping (address => Urn )) public urns;
    mapping (bytes32 => mapping (address => uint)) public gem;  // [wad]
    mapping (address => uint256)                   public joy;  // [rad]
    mapping (address => uint256)                   public sin;  // [rad]

    enum Spot {Sunk, Iffy, Safe}

    uint256 public debt;  // [rad] Total Dai Issued
    uint256 public vice;  // [rad] Total Unbacked Dai
    uint256 public ceil;  // [rad] Total Debt Ceiling

    uint256 public par;   // [wad] System Price (joy/ref)

    Feedbase public feeds;

    constructor() {
        par = RAY;
    }

    function init(bytes32 ilk, address gem, address fsrc, bytes32 ftag)
      _ward_ _flog_ external
    {
        require(ilks[ilk].rack == 0, "Vat/ilk-already-init");
        ilks[ilk] = Ilk({
            rack: RAY,
            duty: RAY,
            liqr: RAY,
            hook: address(0),
            gem : gem,
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
        uint256    ref = rmul(par, mark);
        uint256    liq = rmul(ref, ilk.liqr);
        uint256    tab = urn.art * ilk.rack;
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
        address v = msg.sender;
        Urn storage urn = urns[i][u];
        Ilk storage ilk = ilks[i];

        // ilk has been initialised
        require(ilk.rack != 0, "Vat/ilk-not-init");

        if (ilk.hook != address(0)) {
            Hook(ilk.hook).hook(msg.sender, msg.data);
        }

        urn.ink = add(urn.ink, dink);
        urn.art = add(urn.art, dart);
        ilk.tart = add(ilk.tart, dart);

        int dtab = mul(ilk.rack, dart);
        uint tab = ilk.rack * urn.art;
        debt     = add(debt, dtab);

        // either debt has decreased, or debt ceilings are not exceeded
        require(either(dart <= 0, both(ilk.tart * ilk.rack <= ilk.line, debt <= ceil)), "Vat/ceiling-exceeded");
        // urn is either less risky than before, or it is safe
        require(either(both(dart <= 0, dink >= 0), safe(i, u) == Spot.Safe), "Vat/not-safe");
        // either urn is more safe, or urn is caller
        require(either(both(dart <= 0, dink >= 0), u == v), "Vat/frob/not-allowed-u");
        // urn has no debt, or a non-dusty amount
        require(either(urn.art == 0, tab >= ilk.dust), "Vat/dust");


        gem[i][v] = sub(gem[i][v], dink);
        joy[v]    = add(joy[v],    dtab);
    }

    function grab(bytes32 i, address u, int dink, int dart)
        _ward_ _flog_ external returns (uint256)
    {
        Urn storage urn = urns[i][u];
        Ilk storage ilk = ilks[i];

        uint tab = rmul(urn.art, ilk.rack);
        uint bill = rmul(ilk.chop, tab);

        urn.ink = add(urn.ink, dink);
        urn.art = add(urn.art, dart);
        ilk.tart = add(ilk.tart, dart);

        int dtab = mul(ilk.rack, dart);

        address vow = msg.sender;
        gem[i][vow] = sub(gem[i][vow], dink);
        sin[vow]    = sub(sin[vow],    dtab);
        vice        = sub(vice,        dtab);

        return bill;
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
        uint256 rack = grow(prev, ilks[i].duty, block.timestamp - ilks[i].rho);
        int256  delt = diff(rack, prev);
        int256  rad  = mul(ilks[i].tart, delt);
        ilks[i].rho  = block.timestamp;
        ilks[i].rack = add(ilks[i].rack, delt);
        joy[vow]     = add(joy[vow], rad);
        debt         = add(debt, rad);
    }

    function slip(bytes32 ilk, address usr, int256 wad)
      _ward_ _flog_ external
    {
        gem[ilk][usr] = add(gem[ilk][usr], wad);
    }

    function flux(bytes32 ilk, address dst, uint256 wad) _flog_ external {
        address src = msg.sender;
        gem[ilk][src] = gem[ilk][src] - wad;
        gem[ilk][dst] = gem[ilk][dst] + wad;
    }

    function gift(address dst, uint256 rad) _flog_ external {
        move(msg.sender, dst, rad);
    }

    function move(address src, address dst, uint256 rad) _ward_ _flog_ public {
        joy[src] = joy[src] - rad;
        joy[dst] = joy[dst] + rad;
    }

    function heal(uint rad) _flog_ external {
        address u = msg.sender;
        sin[u] = sin[u] - rad;
        joy[u] = joy[u] - rad;
        vice   = vice   - rad;
        debt   = debt   - rad;
    }

    function suck(address u, address v, uint rad)
      _ward_ _flog_ external
    {
        sin[u] = sin[u] + rad;
        joy[v] = joy[v] + rad;
        vice   = vice   + rad;
        debt   = debt   + rad;
    }

    function file(bytes32 key, uint256 val)
      _ward_ _flog_ external
    {
        if (key == "ceil") { ceil = val;
        } else { revert("ERR_FILE_KEY"); }
    }
    function link(bytes32 key, address val) external
      _ward_ {
        if (key == "feeds") { feeds = Feedbase(val); }
        else revert("ERR_LINK_KEY");
    }
    function filk(bytes32 ilk, bytes32 key, uint val)
      _ward_ _flog_ external
    {
        Ilk storage i = ilks[ilk];
               if (key == "line") { i.line = val;
        } else if (key == "dust") { i.dust = val;
        } else if (key == "duty") { i.duty = val; // WARN must drip first
        } else if (key == "hook") { i.hook = address(bytes20(bytes32(val)));
        } else if (key == "liqr") { i.liqr = val;
        } else if (key == "chop") { i.chop = val;
        } else { revert("ERR_FILK_KEY"); }
    }
}
