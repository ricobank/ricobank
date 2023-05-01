// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2023 the bank
// Copyright (C) 2022 the bank

pragma solidity 0.8.19;

import { Math } from './mixin/math.sol';
import { Flog } from './mixin/flog.sol';

import { Ward } from '../lib/feedbase/src/mixin/ward.sol';
import { Gem } from '../lib/gemfab/src/gem.sol';

import { DutchFlower, Flowback } from './flow.sol';
import { Vat } from './vat.sol';

// accounting mechanism
// triggers collateral (flip), surplus (flap), and deficit (flop) auctions
contract Vow is Math, Ward, Flog, Flowback {
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

    address internal immutable yank = address(0);
    address internal immutable self = address(this);

    DutchFlower public flow;
    Vat  public vat;
    Gem  public RICO;
    Gem  public RISK;

    function keep(bytes32[] calldata ilks) 
      _flog_ external returns (uint256 aid) {
        for (uint256 i = 0; i < ilks.length; i++) {
            vat.drip(ilks[i]);
        }
        uint rico = RICO.balanceOf(self);
        uint risk = RISK.balanceOf(self);
        RISK.burn(self, risk);

        // rico is a wad, sin is a rad
        uint sin = vat.sin(self) / RAY;
        if (rico > sin) {
            // pay down sin, then auction off surplus RICO for RISK
            if (sin > 1) vat.heal(sin - 1);
            // buy-and-burn risk with remaining rico
            uint flap = rico - sin;
            aid = flow.flow(
                address(this), address(RICO), flap, address(RISK),
                type(uint256).max, payable(msg.sender)
            );
        } else if (sin > rico) {
            // pay down as much sin as possible
            if (rico > 1) vat.heal(rico - 1);
            uint slope = min(ramp.vel, wmul(ramp.rel, RISK.totalSupply()));
            uint flop  = slope * min(block.timestamp - ramp.bel, ramp.cel);
            if (0 == flop) revert ErrReflop();
            ramp.bel = block.timestamp;
            // mint-and-sell risk to cover remaining sin
            RISK.mint(self, flop);
            aid = flow.flow(
                address(this), address(RISK), flop, address(RICO), 
                type(uint256).max, payable(msg.sender)
            );
        }
    }

    function bail(bytes32 i, address u) _flog_ external returns (uint256 aid) {
        vat.drip(i);
        if (vat.safe(i, u) != Vat.Spot.Sunk) revert ErrSafeBail();
        aid = vat.grab(i, u, msg.sender);
    }

    function flowback(uint aid, uint refund) _ward_ _flog_ external {}

    // drip to mint accumulated fees
    // minted rico will later heal sin or be auctioned as surplus
    function drip(bytes32 i) _flog_ external {
        vat.drip(i);
    }

    // TODO should not approve to vat; no need...should be just rico and risk
    function grant(address gem) _flog_ external {
        Gem(gem).approve(address(flow), type(uint256).max);
        Gem(gem).approve(address(vat), type(uint256).max);
    }

    function pair(address gem, bytes32 key, uint val)
      _ward_ _flog_ external {
        flow.curb(gem, key, val);
    }

    function link(bytes32 key, address val) _ward_ _flog_ external {
             if (key == "flow") { flow = DutchFlower(val); }
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
