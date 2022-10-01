/// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank

pragma solidity 0.8.15;

import { GemLike, VatLike } from '../src/abi.sol';

contract Flasher {
    VatLike public vat;
    GemLike public rico;
    bytes32 ilk0;
    error ErrBroken();

    constructor(address vat_, address rico_, bytes32 ilk0_) {
        vat = VatLike(vat_);
        rico = GemLike(rico_);
        ilk0 = ilk0_;
    }

    function nop() public {
    }

    function approve_vat(address gem, uint256 wad) public {
        GemLike(gem).approve(address(vat), wad);
    }

    function welch(address gem, uint256 wad) public {
        approve_vat(gem, wad);
        GemLike(gem).transfer(address(0), 3);
    }

    function failure() public pure {
        revert ErrBroken();
    }

    function reenter(address gem, uint256 wad) public {
        bytes memory data = abi.encodeCall(this.approve_vat, (gem, wad));
        vat.flash(gem, wad, address(this), data);
        approve_vat(gem, wad);
    }

    function rico_lever(address gem, uint256 lock_amt, uint256 draw_amt) public {
        _buy_gem(gem, draw_amt);
        approve_vat(gem, lock_amt);
        vat.frob(ilk0, address(this), int(lock_amt), int(draw_amt));
    }

    function rico_release(address gem, uint256 free_amt, uint256 wipe_amt) public {
        vat.frob(ilk0, address(this), -int(free_amt), -int(wipe_amt));
        _sell_gem(gem, wipe_amt);
    }

    function gem_lever(address gem, uint256 lock_amt, uint256 draw_amt) public {
        approve_vat(gem, lock_amt);
        vat.frob(ilk0, address(this), int(lock_amt), int(draw_amt));
        _buy_gem(gem, draw_amt);
        approve_vat(gem, lock_amt);
    }

    function gem_release(address gem, uint256 free_amt, uint256 wipe_amt) public {
        _sell_gem(gem, wipe_amt);
        vat.frob(ilk0, address(this), -int(free_amt), -int(wipe_amt));
        approve_vat(gem, wipe_amt);
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
