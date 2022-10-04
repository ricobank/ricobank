// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2022 the bank

pragma solidity 0.8.15;

import { Flow, Flowback } from './flow.sol';
import { GemLike } from './abi.sol';
import { Math } from './mixin/math.sol';
import { Vat } from './vat.sol';
import { Ward } from './mixin/ward.sol';

contract Vow is Flowback, Math, Ward {
    struct Sale {
        bytes32 ilk;
        address urn;
    }

    mapping(bytes32 => Sale) public sales;

    error ErrOverflow();
    error ErrSafeBail();
    error ErrWrongKey();

    address  public immutable self = address(this);

    Flow     public flow;
    Vat      public vat;
    GemLike  public RICO;
    GemLike  public RISK;

    function keep(bytes32[] calldata ilks) external {
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
            bytes32 aid = flow.flow(address(RICO), over, address(RISK), type(uint256).max);
            flow.glug(aid);
        } else if (sin > rico) {
            if (rico > 1) vat.heal(rico - 1);
            (, uint flop,) = flow.clip(self, address(RISK), type(uint256).max);
            RISK.mint(self, flop);
            bytes32 aid = flow.flow(address(RISK), flop, address(RICO), type(uint256).max);
            flow.glug(aid);
        }
    }

    function bail(bytes32 ilk, address urn) external {
        vat.drip(ilk);
        if (vat.safe(ilk, urn) != Vat.Spot.Sunk) revert ErrSafeBail();
        (uint ink, uint art) = vat.urns(ilk, urn);
        (uint bill, address gem) = vat.grab(ilk, urn, -int(ink), -int(art));
        bytes32 aid = flow.flow(gem, ink, address(RICO), bill);
        sales[aid] = Sale({ ilk: ilk, urn: urn });
        flow.glug(aid);
    }

    function flowback(bytes32 aid, uint refund) external
      _ward_ {
        if (refund == 0)  return;
        if (refund > 2 ** 255) revert ErrOverflow();
        Sale storage sale = sales[aid];
        vat.frob(sale.ilk, sale.urn, int(refund), 0);
        delete sales[aid];
    }

    function grant(address gem) external {
        GemLike(gem).approve(address(flow), type(uint256).max);
        GemLike(gem).approve(address(vat), type(uint256).max);
        flow.approve_gem(gem);
    }

    function pair(address gem, bytes32 key, uint val)
      _ward_ external {
        flow.curb(gem, key, val);
    }

    function link(bytes32 key, address val) external
      _ward_ {
             if (key == "flow") { flow = Flow(val); }
        else if (key == "RISK") { RISK = GemLike(val); }
        else if (key == "RICO") { RICO = GemLike(val); }
        else if (key == "vat")  { vat  = Vat(val); }
        else revert ErrWrongKey();
    }
}
