/// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank

pragma solidity 0.8.15;

import { DockLike, GemLike, VatLike } from '../src/abi.sol';

contract Flasher {
    DockLike public dock;
    VatLike public vat;
    GemLike public rico;
    bytes32 ilk0;
    error ErrBroken();

    constructor(address dock_, address vat_, address rico_, bytes32 ilk0_) {
        dock = DockLike(dock_);
        vat = VatLike(vat_);
        rico = GemLike(rico_);
        ilk0 = ilk0_;
    }

    function nop() public {
    }

    function approve_dock(address gem, uint256 wad) public {
        GemLike(gem).approve(address(dock), wad);
    }

    function welch(address gem, uint256 wad) public {
        approve_dock(gem, wad);
        GemLike(gem).transfer(address(0), 1);
    }

    function failure(address gem, uint256 wad) public pure {
        revert ErrBroken();
    }

    function reenter(address gem, uint256 wad) public {
        bytes memory data = abi.encodeCall(this.approve_dock, (gem, wad));
        dock.flash(gem, wad, address(this), data);
        approve_dock(gem, wad);
    }

    function rico_lever(address gem, uint256 lock_amt, uint256 draw_amt) public {
        _buy_gem(gem, draw_amt);
        GemLike(gem).approve(address(dock), lock_amt);
        dock.join_gem(address(vat), ilk0, address(this), lock_amt);
        vat.frob(ilk0, address(this), int(lock_amt), int(draw_amt));
        dock.exit_rico(address(vat), address(rico), address(this), draw_amt);
    }

    function rico_release(address gem, uint256 free_amt, uint256 wipe_amt) public {
        dock.join_rico(address(vat), address(rico), address(this), wipe_amt);
        vat.frob(ilk0, address(this), -int(free_amt), -int(wipe_amt));
        dock.exit_gem(address(vat), ilk0, address(this), free_amt);
        _sell_gem(gem, wipe_amt);
    }

    function gem_lever(address gem, uint256 lock_amt, uint256 draw_amt) public {
        GemLike(gem).approve(address(dock), lock_amt);
        dock.join_gem(address(vat), ilk0, address(this), lock_amt);
        vat.frob(ilk0, address(this), int(lock_amt), int(draw_amt));
        dock.exit_rico(address(vat), address(rico), address(this), draw_amt);
        _buy_gem(gem, draw_amt);
        GemLike(gem).approve(address(dock), lock_amt);
    }

    function gem_release(address gem, uint256 free_amt, uint256 wipe_amt) public {
        _sell_gem(gem, wipe_amt);
        dock.join_rico(address(vat), address(rico), address(this), wipe_amt);
        vat.frob(ilk0, address(this), -int(free_amt), -int(wipe_amt));
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
