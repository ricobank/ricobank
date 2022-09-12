/// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank

pragma solidity 0.8.15;

import { GemLike, VatLike, DockLike } from '../abi.sol';

contract MockFlashStrategist {
    DockLike public dock;
    VatLike public vat;
    GemLike public rico;
    bytes32 ilk0;

    constructor(address dock_, address vat_, address rico_, bytes32 ilk0_) {
        dock = DockLike(dock_);
        vat = VatLike(vat_);
        rico = GemLike(rico_);
        ilk0 = ilk0_;
    }

    function nop() public {
    }

    function approve_all(address[] memory gems, uint256[] memory amts) public {
        for (uint256 i = 0; i < gems.length; i++) {
            GemLike(gems[i]).approve(address(dock), amts[i]);
        }
    }

    function welch(address[] memory gems, uint256[] memory amts) public {
        approve_all(gems, amts);
        for (uint256 i = 0; i < gems.length; i++) {
            GemLike(gems[i]).transfer(address(0), 1);
        }
    }

    function failure(address[] memory gems, uint256[] memory amts) public pure {
        revert("failure");
    }

    function reenter(address[] memory gems, uint256[] memory amts) public {
        bytes memory data = abi.encodeCall(this.approve_all, (gems, amts));
        for( uint i = 0; i < gems.length; i++ ) {
            dock.flash(gems[i], amts[i], address(this), data);
        }
        approve_all(gems, amts);
    }

    function port_lever(address gem, uint256 lock_amt, uint256 draw_amt) public {
        _buy_gem(gem, draw_amt);
        GemLike(gem).approve(address(dock), lock_amt);
        dock.join_gem(address(vat), ilk0, address(this), lock_amt);
        vat.frob(ilk0, address(this), int(lock_amt), 0);
        vat.frob(ilk0, address(this), 0, int(draw_amt));
        dock.exit_rico(address(vat), address(rico), address(this), draw_amt);
    }

    function port_release(address gem, uint256 free_amt, uint256 wipe_amt) public {
        dock.join_rico(address(vat), address(rico), address(this), wipe_amt);
        vat.frob(ilk0, address(this), 0, -int(wipe_amt));
        vat.frob(ilk0, address(this), -int(free_amt), 0);
        dock.exit_gem(address(vat), ilk0, address(this), free_amt);
        _sell_gem(gem, wipe_amt);
    }

    function plug_lever(address gem, uint256 lock_amt, uint256 draw_amt) public {
        GemLike(gem).approve(address(dock), lock_amt);
        dock.join_gem(address(vat), ilk0, address(this), lock_amt);
        vat.frob(ilk0, address(this), int(lock_amt), 0);
        vat.frob(ilk0, address(this), 0, int(draw_amt));
        dock.exit_rico(address(vat), address(rico), address(this), draw_amt);
        _buy_gem(gem, draw_amt);
        GemLike(gem).approve(address(dock), lock_amt);
    }

    function plug_release(address gem, uint256 free_amt, uint256 wipe_amt) public {
        _sell_gem(gem, wipe_amt);
        dock.join_rico(address(vat), address(rico), address(this), wipe_amt);
        vat.frob(ilk0, address(this), 0, -int(wipe_amt));
        vat.frob(ilk0, address(this), -int(free_amt), 0);
        dock.exit_gem(address(vat), ilk0, address(this), free_amt);
        GemLike(gem).approve(address(dock), wipe_amt);
    }

    function _buy_gem(address gem, uint256 amount) internal {
        rico.burn(address(this), amount);
        GemLike(gem).mint(address(this), amount);
    }

    function _sell_gem(address gem, uint256 amount) internal {
        GemLike(gem).burn(address(this), amount);
        rico.mint(address(this), amount);
    }
}
