// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2022 the bank

pragma solidity 0.8.15;

import { Flow, Flowback } from './flow.sol';
import { VatLike, GemLike, DockLike } from './abi.sol';
import { Math } from './mixin/math.sol';
import { Ward } from './mixin/ward.sol';

contract Vow is Flowback, Math, Ward {
    struct Sale {
        bytes32 ilk;
        address urn;
    }

    mapping(bytes32 => Sale) public sales;

    address  public immutable FLOP = address(0);
    address  public immutable self = address(this);

    uint256  public bar;  // [rad] Surplus buffer
    Flow     public flow;
    DockLike public dock;
    VatLike  public vat;
    GemLike  public RICO;
    GemLike  public RISK;

    function keep(bytes32[] calldata ilks) external {
        for (uint256 i = 0; i < ilks.length; i++) {
            vat.drip(ilks[i]);
        }
        uint rico = RICO.balanceOf(address(this));
        uint risk = RISK.balanceOf(address(this));
        RISK.burn(address(this), risk);
        dock.join_rico(address(vat), address(RICO), address(this), rico);

        uint sin = vat.sin(address(this));
        uint joy = vat.joy(address(this));
        uint surplus = joy > sin + bar ? (joy - sin - bar) / RAY : 0;
        uint deficit = sin > joy ? sin - joy : 0;

        if (surplus > 0) {
            vat.heal(sin);
            dock.exit_rico(address(vat), address(RICO), self, surplus);
            bytes32 aid = flow.flow(address(RICO), surplus, address(RISK), type(uint256).max);
            flow.glug(aid);
        } else if (deficit > 0) {
            vat.heal(joy);
            (uint flop, uint dust) = flow.clip(FLOP, type(uint256).max);
            require(flop > dust, 'Vow/risk-dust');
            RISK.mint(self, flop);
            flow.flow(address(RISK), flop, address(RICO), type(uint256).max);
            // TODO glug and test for glug
        } else if (sin != 0) {
            vat.heal(min(joy, sin));
        }
    }

    function bail(bytes32 ilk, address urn) external {
        vat.drip(ilk);
        require( !vat.safe(ilk, urn), 'ERR_SAFE' );
        (uint ink, uint art) = vat.urns(ilk, urn);
        uint bill = vat.grab(ilk, urn, -int(ink), -int(art));
        address gem = dock.exit_gem(address(vat), ilk, self, ink);
        bytes32 aid = flow.flow(gem, ink, address(RICO), bill);
        sales[aid] = Sale({ ilk: ilk, urn: urn });
        flow.glug(aid);
    }

    // todo missing proceeds param
    function flowback(bytes32 aid, address gem, uint refund) external
      _ward_ {
        if (refund > 0) {
            Sale storage sale = sales[aid];
            dock.join_gem(address(vat), sale.ilk, sale.urn, refund);
        }
        // todo is it worth 'delete sales[aid];' after EIP-3529?
        // assume 'delete auctions[aid];' in flow uses up max refund
        // reusing slots later instead is real saving, two changes better than one zero to something
    }

    function reapprove_gem(address gem) external {
        GemLike(gem).approve(address(dock), type(uint256).max);
        GemLike(gem).approve(address(flow), type(uint256).max);
    }

    function file(bytes32 key, uint val)
      _ward_ external {
        if (key == "bar") { bar = val;
        } else { revert("ERR_FILE_KEY"); }
    }

    function pair(address gem, bytes32 key, uint val)
      _ward_ external {
        flow.curb(gem, key, val);
    }

    function link(bytes32 key, address val) external
      _ward_ {
             if (key == "flow") { flow = Flow(val); }
        else if (key == "dock") { dock = DockLike(val); }
        else if (key == "RISK") { RISK = GemLike(val); }
        else if (key == "RICO") { RICO = GemLike(val); }
        else if (key == "vat")  { vat  = VatLike(val); }
        else revert("ERR_LINK_KEY");
    }

    fallback () external payable {}
}
