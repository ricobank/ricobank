// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2023 the bank
// Copyright (C) 2022 the bank

pragma solidity 0.8.19;

import { Gem }  from '../lib/gemfab/src/gem.sol';
import { Ward } from '../lib/feedbase/src/mixin/ward.sol';
import { Flog } from './mixin/flog.sol';
import { Math } from './mixin/math.sol';
import { Vat }  from './vat.sol';
import { ERC20Hook, NO_CUT } from '../src/hook/ERC20hook.sol';

// accounting mechanism
// triggers collateral (flip), surplus (flap), and deficit (flop) auctions
contract Vow is Math, Ward, Flog {
    error ErrSafeBail();
    error ErrWrongKey();
    error ErrReflop();

    // RISK mint rate
    // flop uses min(vel rate, rel rate)
    struct Ramp {
        uint vel; // [wad] RISK/s
        uint rel; // [wad] fraction of RISK supply/s
        uint bel; // [sec] last flop timestamp
        uint cel; // [sec] max seconds flop can ramp up
    }

    Ramp public ramp;

    address internal immutable self = address(this);
    uint256 internal constant  DASH = 2 * RAY;

    ERC20Hook public flow;
    Vat  public vat;
    Gem  public RICO;
    Gem  public RISK;

    function keep(bytes32[] calldata ilks) 
      _flog_ external {
        for (uint256 i = 0; i < ilks.length; i++) {
            vat.drip(ilks[i]);
        }
        uint rico = RICO.balanceOf(self);
        uint risk = RISK.balanceOf(self);
        RISK.burn(self, risk);

        // rico is a wad, sin is a rad
        uint sin = vat.sin(self) / RAY;
        uint rush = DASH;
        if (rico > sin) {
            // pay down sin, then auction off surplus RICO for RISK
            if (sin > 1) vat.heal(sin - 1);
            // buy-and-burn risk with remaining rico
            uint flap = rico - sin;
            uint debt = vat.debt();
            if (debt > 0) rush = min(rush, rdiv(debt + flap, debt));
            flow.flow(
                self, "flap", flap, address(RISK), type(uint256).max,
                msg.sender, self, rush, NO_CUT
            );
        } else if (sin > rico) {
            // pay down as much sin as possible
            if (rico > 1) vat.heal(rico - 1);
            uint debt = vat.debt();
            if (debt > 0) rush = min(rush, rdiv(debt + sin - rico, debt));
            uint slope = min(ramp.vel, wmul(ramp.rel, RISK.totalSupply()));
            uint flop  = slope * min(block.timestamp - ramp.bel, ramp.cel);
            if (0 == flop) revert ErrReflop();
            ramp.bel = block.timestamp;
            // mint-and-sell risk to cover remaining sin
            RISK.mint(self, flop);
            flow.flow(
                self, "flop", flop, address(RICO), type(uint256).max,
                msg.sender, self, rush, NO_CUT
            );
        }
    }

    function bail(bytes32 i, address u) _flog_ external {
        vat.drip(i);
        (Vat.Spot spot, uint rush, uint cut) = vat.safe(i, u);
        if (spot != Vat.Spot.Sunk) revert ErrSafeBail();
        vat.grab(i, u, msg.sender, rush, cut);
    }

    // drip to mint accumulated fees
    // minted rico will later heal sin or be auctioned as surplus
    function drip(bytes32 i) _flog_ external {
        vat.drip(i);
    }

    function grant(address gem) _flog_ external {
        Gem(gem).approve(address(flow), type(uint256).max);
    }

    function link(bytes32 key, address val) _ward_ _flog_ external {
             if (key == "flow") { flow = ERC20Hook(val); }
        else if (key == "RISK") { RISK = Gem(val); }
        else if (key == "RICO") { RICO = Gem(val); }
        else if (key == "vat")  { vat  = Vat(val); }
        else revert ErrWrongKey();
    }

    function file(bytes32 key, uint val) _ward_ _flog_ external {
             if (key == "vel") { ramp.vel = val; }
        else if (key == "rel") { ramp.rel = val; }
        else if (key == "bel") { ramp.bel = val; }
        else if (key == "cel") { ramp.cel = val; }
        else revert ErrWrongKey();
    }
}
