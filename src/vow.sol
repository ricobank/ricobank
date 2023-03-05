// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2023 the bank
// Copyright (C) 2022 the bank

pragma solidity 0.8.18;

import { UniFlower, Flowback } from './flow.sol';
import { Math } from './mixin/math.sol';
import { Vat } from './vat.sol';
import { Gem } from '../lib/gemfab/src/gem.sol';
import { Ward } from './mixin/ward.sol';

contract Vow is Flowback, Math, Ward {
    struct Sale {
        bytes32 ilk;
        address urn;
    }

    mapping(uint256 aid => Sale) public sales;

    error ErrBigFlowback();
    error ErrSafeBail();
    error ErrWrongKey();

    address internal immutable yank = address(0);
    address internal immutable self = address(this);

    UniFlower public flow;
    Vat  public vat;
    Gem  public RICO;
    Gem  public RISK;

    function keep(bytes32[] calldata ilks) external returns (uint256 aid) {
        for (uint256 i = 0; i < ilks.length; i++) {
            vat.drip(ilks[i]);
        }
        uint rico = RICO.balanceOf(self);
        uint risk = RISK.balanceOf(self);
        RISK.burn(self, risk);

        uint sin = vat.sin(self) / RAY;
        if (rico > sin) {
            if (sin > 1) vat.heal(sin - 1);
            uint over = (rico - sin);
            aid = flow.flow(address(RICO), over, address(RISK), type(uint256).max);
        } else if (sin > rico) {
            if (rico > 1) vat.heal(rico - 1);
            (, uint flop, uint bel) = flow.clip(self, yank, address(RISK), type(uint256).max);
            flow.curb(yank, "bel", bel);
            RISK.mint(self, flop);
            aid = flow.flow(address(RISK), flop, address(RICO), type(uint256).max);
        }
    }

    function bail(bytes32 ilk, address urn) external returns (uint256 aid) {
        vat.drip(ilk);
        if (vat.safe(ilk, urn) != Vat.Spot.Sunk) revert ErrSafeBail();
        (uint ink, uint art) = vat.urns(ilk, urn);
        (uint bill, address gem, bool hooked) = vat.grab(ilk, urn, -int(ink), -int(art));
        if (!hooked) {
            aid = flow.flow(gem, ink, address(RICO), bill);
            sales[aid] = Sale({ ilk: ilk, urn: urn });
        }
    }

    function flowback(uint256 aid, uint refund) external
      _ward_ {
        if (refund == 0)  return;
        if (refund >= 2 ** 255) revert ErrBigFlowback();
        Sale storage sale = sales[aid];
        bytes32 ilk = sale.ilk;
        address urn = sale.urn;
        delete sales[aid];
        vat.frob(ilk, urn, int(refund), 0);
    }

    function drip(bytes32 i) external {
        vat.drip(i);
    }

    function grant(address gem) external {
        Gem(gem).approve(address(flow), type(uint256).max);
        Gem(gem).approve(address(vat), type(uint256).max);
        flow.approve_gem(gem);
    }

    function pair(address gem, bytes32 key, uint val)
      _ward_ external {
        flow.curb(gem, key, val);
    }

    function link(bytes32 key, address val) external
      _ward_ {
             if (key == "flow") { flow = UniFlower(val); }
        else if (key == "RISK") { RISK = Gem(val); }
        else if (key == "RICO") { RICO = Gem(val); }
        else if (key == "vat")  { vat  = Vat(val); }
        else revert ErrWrongKey();
    }
}
