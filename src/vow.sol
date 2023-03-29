// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2023 the bank
// Copyright (C) 2022 the bank

pragma solidity 0.8.19;

import { DutchFlower, Flowback } from './flow.sol';
import { Math } from './mixin/math.sol';
import { Vat } from './vat.sol';
import { Gem } from '../lib/gemfab/src/gem.sol';
import { Ward } from '../lib/feedbase/src/mixin/ward.sol';
import { Flog } from './mixin/flog.sol';

contract Vow is Math, Ward, Flog {
    error ErrSafeBail();
    error ErrWrongKey();
    error ErrReflop();

    struct Ramp {
        uint vel;
        uint rel;
        uint bel;
        uint cel;
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

        uint sin = vat.sin(self) / RAY;
        if (rico > sin) {
            if (sin > 1) vat.heal(sin - 1);
            uint flap = rico - sin;
            aid = flow.flow(
                address(this), address(RICO), flap, address(RISK),
                type(uint256).max, payable(msg.sender)
            );
        } else if (sin > rico) {
            if (rico > 1) vat.heal(rico - 1);
            uint slope = min(ramp.vel, wmul(ramp.rel, RISK.totalSupply()));
            uint flop  = slope * min(block.timestamp - ramp.bel, ramp.cel);
            if (0 == flop) revert ErrReflop();
            ramp.bel = block.timestamp;
            RISK.mint(self, flop);
            aid = flow.flow(
                address(this), address(RISK), flop, address(RICO), 
                type(uint256).max, payable(msg.sender)
            );
        }
    }

    function flowback(uint aid, uint refund) _ward_ _flog_ external {}

    function bail(bytes32 ilk, address urn) _flog_ external returns (uint256 aid) {
        vat.drip(ilk);
        if (vat.safe(ilk, urn) != Vat.Spot.Sunk) revert ErrSafeBail();
        aid = vat.grab(ilk, urn, msg.sender);
    }

    function drip(bytes32 i) _flog_ external {
        vat.drip(i);
    }

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
