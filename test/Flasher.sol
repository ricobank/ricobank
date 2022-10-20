/// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank

pragma solidity 0.8.17;

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

    function approve_sender(address gem, uint256 wad) public {
        GemLike(gem).approve(msg.sender, wad);
    }

    function welch(address[] memory gems, uint256[] memory wads, uint256 welch_index) public {
        for (uint256 i = 0; i < gems.length; i++) {
            approve_vat(gems[i], wads[i]);
            if (i == welch_index) {
                GemLike(gems[i]).transfer(address(0), 1);
            }
        }
    }

    function failure() public pure {
        revert ErrBroken();
    }

    function reenter(address gem, uint256 wad) public {
        bytes memory data = abi.encodeCall(this.approve_vat, (gem, wad));
        address[] memory gems = new address[](1);
        uint256[] memory wads = new uint256[](1);
        gems[0] = gem;
        wads[0] = wad;
        vat.flash(gems, wads, address(this), data);
        approve_vat(gem, wad);
    }

    function multi_borrow(address gem1, uint256 bal1, address gem2, uint256 bal2) public {
        require(GemLike(gem1).balanceOf(address(this)) >= bal1, 'missing borrowed tokens 1');
        require(GemLike(gem2).balanceOf(address(this)) >= bal2, 'missing borrowed tokens 2');
        approve_vat(gem1, bal1);
        approve_vat(gem2, bal2);
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
