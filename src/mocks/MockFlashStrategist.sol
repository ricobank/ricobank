/// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank

pragma solidity 0.8.15;

import { GemLike, VatLike, PlugLike, PortLike } from '../abi.sol';

contract MockFlashStrategist {
    PlugLike public plug;
    PortLike public port;
    VatLike public vat;
    GemLike public rico;
    bytes32 ilk0;

    constructor(address plug_, address port_, address vat_, address rico_, bytes32 ilk0_) {
        plug = PlugLike(plug_);
        port = PortLike(port_);
        vat = VatLike(vat_);
        rico = GemLike(rico_);
        ilk0 = ilk0_;
    }

    function nop() public {
    }

    function approve_all(address[] memory gems, uint256[] memory amts) public {
        for (uint256 i = 0; i < gems.length; i++) {
            GemLike(gems[i]).approve(address(plug), amts[i]);
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
        plug.flash(gems, amts, address(this), data);
        approve_all(gems, amts);
    }

    function port_lever(address gem, uint256 lock_amt, uint256 draw_amt) public {
        _buy_gem(gem, draw_amt);
        GemLike(gem).approve(address(plug), lock_amt);
        plug.join(address(vat), ilk0, address(this), lock_amt);
        vat.lock(ilk0, lock_amt);
        vat.draw(ilk0, draw_amt);
        vat.trust(address(port), true);
        port.exit(address(vat), address(rico), address(this), draw_amt);
    }

    function port_release(address gem, uint256 free_amt, uint256 wipe_amt) public {
        port.join(address(vat), address(rico), address(this), wipe_amt);
        vat.wipe(ilk0, wipe_amt);
        vat.free(ilk0, free_amt);
        plug.exit(address(vat), ilk0, address(this), free_amt);
        _sell_gem(gem, wipe_amt);
    }

    function plug_lever(address gem, uint256 lock_amt, uint256 draw_amt) public {
        GemLike(gem).approve(address(plug), lock_amt);
        plug.join(address(vat), ilk0, address(this), lock_amt);
        vat.lock(ilk0, lock_amt);
        vat.draw(ilk0, draw_amt);
        vat.trust(address(port), true);
        port.exit(address(vat), address(rico), address(this), draw_amt);
        _buy_gem(gem, draw_amt);
        GemLike(gem).approve(address(plug), lock_amt);
    }

    function plug_release(address gem, uint256 free_amt, uint256 wipe_amt) public {
        _sell_gem(gem, wipe_amt);
        port.join(address(vat), address(rico), address(this), wipe_amt);
        vat.wipe(ilk0, wipe_amt);
        vat.free(ilk0, free_amt);
        plug.exit(address(vat), ilk0, address(this), free_amt);
        GemLike(gem).approve(address(plug), wipe_amt);
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
