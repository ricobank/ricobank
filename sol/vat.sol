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

pragma solidity 0.8.9;

import './mixin/math.sol';
import './mixin/ward.sol';

contract Vat is Math, Ward {
    struct Ilk {
        uint256 tart;  // [wad] Total Normalised Debt
        uint256 rack;  // [ray] Accumulated Rate

        uint256 mark;  // [ray] Last poked price

        uint256 line;  // [rad] Debt Ceiling
        uint256 dust;  // [rad] Urn Debt Floor

        uint256 duty;  // [ray] Collateral-specific, per-second compounding rate
        uint256  rho;  // [sec] Time of last drip

        uint256 chop;  // [ray] Liquidation Penalty
        uint256 liqr;  // [ray] Liquidation Ratio

        bool    open;  // [bit] Don't require ACL
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

    mapping (bytes32 => mapping (address => bool)) public sys;  // ilk ACL
    mapping (address => mapping (address => bool)) public can;  // urn approval

    uint256 public debt;  // [rad] Total Dai Issued
    uint256 public vice;  // [rad] Total Unbacked Dai
    uint256 public ceil;  // [rad] Total Debt Ceiling

    uint256 public par;   // [wad] System Price (joy/ref)
    uint256 public way;   // [ray] System Rate (SP growth rate)
    uint256 public tau;   // [sec] Last prod

    constructor() {
        par = RAY;
        way = RAY;
        tau = time();
    }

    function init(bytes32 ilk) external 
      _ward_
    {
        require(ilks[ilk].rack == 0, "Vat/ilk-already-init");
        ilks[ilk] = Ilk({
            rack: RAY,
            duty: RAY,
            liqr: RAY,
            open: true, // TODO consider defaults
            rho : time(),
            tart: 0, mark: 0, chop: 0, line: 0, dust: 0
        });
    }

    function owed(bytes32 i, address u) public returns (uint256 rad) {
      drip(i);
      return mul(ilks[i].rack, urns[i][u].art);
    }

    function safe(bytes32 i, address u) public returns (bool) {
        prod();
        drip(i);
        Urn memory urn = urns[i][u];
        Ilk memory ilk = ilks[i];
        uint256    ref = rmul(par, ilk.mark);
        uint256    liq = rmul(ref, ilk.liqr);
        uint256    tab = mul(urn.art, ilk.rack);
        uint256    cut = mul(urn.ink, liq);
        return (tab <= cut);
    }

    function lock(bytes32 i, uint amt) external {
        frob(i, msg.sender, msg.sender, msg.sender, int(amt), 0);
    }
    function free(bytes32 i, uint amt) external {
        frob(i, msg.sender, msg.sender, msg.sender, -int(amt), 0);
    }
    function draw(bytes32 i, uint amt) external {
        frob(i, msg.sender, msg.sender, msg.sender, 0, int(amt));
    }
    function wipe(bytes32 i, uint amt) external {
        frob(i, msg.sender, msg.sender, msg.sender, 0, -int(amt));
    }

    function frob(bytes32 i, address u, address v, address w, int dink, int dart) public {
        drip(i);
        Urn memory urn = urns[i][u];
        Ilk memory ilk = ilks[i];

        require(ilk.open || sys[i][msg.sender], 'err-sys');

        // ilk has been initialised
        require(ilk.rack != 0, "Vat/ilk-not-init");

        urn.ink = add(urn.ink, dink);
        urn.art = add(urn.art, dart);
        ilk.tart = add(ilk.tart, dart);

        int dtab = mul(ilk.rack, dart);
        uint tab = mul(ilk.rack, urn.art);
        debt     = add(debt, dtab);

        // either debt has decreased, or debt ceilings are not exceeded
        require(either(dart <= 0, both(mul(ilk.tart, ilk.rack) <= ilk.line, debt <= ceil)), "Vat/ceiling-exceeded");
        // urn is either less risky than before, or it is safe
        require(either(both(dart <= 0, dink >= 0), safe(i, u)), "Vat/not-safe");

        // urn is either more safe, or the owner consents
        require(either(both(dart <= 0, dink >= 0), wish(u, msg.sender)), "Vat/frob/not-allowed-u");
        // collateral src consents
        require(either(dink <= 0, wish(v, msg.sender)), "Vat/frob/not-allowed-v");
        // debt dst consents
        require(either(dart >= 0, wish(w, msg.sender)), "Vat/frob/not-allowed-w");

        // urn has no debt, or a non-dusty amount
        require(either(urn.art == 0, tab >= ilk.dust), "Vat/dust");

        gem[i][v] = sub(gem[i][v], dink);
        joy[w]    = add(joy[w],    dtab);

        urns[i][u] = urn;
        ilks[i]    = ilk;
    }

    function fork(bytes32 ilk, address src, address dst, int dink, int dart) external {
        drip(ilk);
        Urn storage u = urns[ilk][src];
        Urn storage v = urns[ilk][dst];
        Ilk storage i = ilks[ilk];

        require(i.open || sys[ilk][msg.sender], 'err-sys');

        u.ink = sub(u.ink, dink);
        u.art = sub(u.art, dart);
        v.ink = add(v.ink, dink);
        v.art = add(v.art, dart);

        uint utab = mul(u.art, i.rack);
        uint vtab = mul(v.art, i.rack);

        // both sides consent
        require(both(wish(src, msg.sender), wish(dst, msg.sender)), "Vat/not-allowed");

        // both sides safe
        require(safe(ilk, src), "Vat/not-safe-src");
        require(safe(ilk, dst), "Vat/not-safe-dst");

        // both sides non-dusty
        require(either(utab >= i.dust, u.art == 0), "Vat/dust-src");
        require(either(vtab >= i.dust, v.art == 0), "Vat/dust-dst");
    }

    function grab(bytes32 i, address u, address v, address w, int dink, int dart)
        //_ward_ _drip_(i) external returns (uint256)
        _ward_ external returns (uint256)
    {
        drip(i); // TODO use modifiers; stack too deep
        Urn storage urn = urns[i][u];
        Ilk storage ilk = ilks[i];

        uint tab = rmul(urn.art, ilk.rack);
        uint bill = rmul(ilk.chop, tab);

        urn.ink = add(urn.ink, dink);
        urn.art = add(urn.art, dart);
        ilk.tart = add(ilk.tart, dart);

        int dtab = mul(ilk.rack, dart);

        gem[i][v] = sub(gem[i][v], dink);
        sin[w]    = sub(sin[w],    dtab);
        vice      = sub(vice,      dtab);

        return bill;
    }

    function plot(bytes32 ilk, uint mark)
      _ward_ external
    {
        ilks[ilk].mark = mark;
    }

    function sway(uint256 r)
      _ward_ _prod_ external
    {
        way = r;
    }

    function spar(uint256 jam)
      _ward_ _prod_ external
    {
        par = jam;
    }

    modifier _prod_ {
        uint256 t = block.timestamp;
        if (t > tau) {
            par = grow(par, way, t - tau);
            tau = t;
        }
        _;
    }
    function prod() public // TODO external
      _prod_
    {}

    modifier _drip_(bytes32 i) {
        Ilk storage ilk = ilks[i];
        uint256 t = block.timestamp;
        require(t >= ilk.rho, 'Vat/invalid-now');
        if (t > ilk.rho) {
            address vow  = address(0);
            uint256 prev = ilk.rack;
            uint256 rack = grow(prev, ilk.duty, t - ilk.rho);
            int256  delt = diff(rack, prev);
            int256  rad  = mul(ilk.tart, delt);
            ilk.rho      = time();
            ilk.rack     = add(ilk.rack, delt);
            joy[vow]     = add(joy[vow], rad);
            debt         = add(debt, rad);
        }
        _;
    }
    function drip(bytes32 i) public // TODO external
      _drip_(i)
    {}

    function rake()
      _ward_ external
      returns (uint256)
    {
        uint256 amt = joy[address(0)];
        joy[msg.sender] = add(joy[msg.sender], amt);
        joy[address(0)] = 0;
        return amt;
    }

    function slip(bytes32 ilk, address usr, int256 wad)
      _ward_ external
    {
        gem[ilk][usr] = add(gem[ilk][usr], wad);
    }
    function flux(bytes32 ilk, address src, address dst, uint256 wad) external {
        require(wish(src, msg.sender), "Vat/not-allowed");
        gem[ilk][src] = sub(gem[ilk][src], wad);
        gem[ilk][dst] = add(gem[ilk][dst], wad);
    }
    function move(address src, address dst, uint256 rad) external {
        require(wish(src, msg.sender), "Vat/move/not-allowed");
        joy[src] = sub(joy[src], rad);
        joy[dst] = add(joy[dst], rad);
    }

    function heal(uint rad) external {
        address u = msg.sender;
        sin[u] = sub(sin[u], rad);
        joy[u] = sub(joy[u], rad);
        vice   = sub(vice,   rad);
        debt   = sub(debt,   rad);
    }
    function suck(address u, address v, uint rad)
      _ward_ external
    {
        sin[u] = add(sin[u], rad);
        joy[v] = add(joy[v], rad);
        vice   = add(vice,   rad);
        debt   = add(debt,   rad);
    }

    function hope(address usr) external {
        can[msg.sender][usr] = true;
    }
    function nope(address usr) external {
        can[msg.sender][usr] = false;
    }
    function wish(address bit, address usr) internal view returns (bool) {
        return either(bit == usr, can[bit][usr] == true);
    }

    function wire(bytes32 i, address u, bool bit)
      _ward_ external
    {
        sys[i][u] = bit;
    }

    function file(bytes32 key, uint256 val)
      _ward_ external
    {
        if (key == "ceil") { ceil = val;
        } else { revert("ERR_FILE_KEY"); }
    }
    function filk(bytes32 ilk, bytes32 key, uint val)
      _ward_ external
    {
        Ilk storage i = ilks[ilk];
               if (key == "line") { i.line = val;
        } else if (key == "dust") { i.dust = val;
        } else if (key == "duty") { drip(ilk); i.duty = val; // TODO check drip call
        } else if (key == "open") { i.open = (val == 0 ? false : true); // TODO check default
        } else if (key == "liqr") { i.liqr = val;
        } else if (key == "chop") { i.chop = val;
        } else { revert("ERR_FILK_KEY"); }
    }

    function time() public view returns (uint256) {
        return block.timestamp;
    }
}
