/// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank

pragma solidity 0.8.19;
import 'forge-std/Test.sol';

import { Vat } from '../src/vat.sol';
import { Gem } from '../lib/gemfab/src/gem.sol';
import { ERC20Hook } from '../src/hook/ERC20hook.sol';

contract Flasher {
    Gem public rico;
    bytes32 ilk0;
    error ErrBroken();
    address payable bank;

    constructor(address payable _bank, address rico_, bytes32 ilk0_) {
        bank = _bank;
        rico = Gem(rico_);
        ilk0 = ilk0_;
    }

    function nop() public {
    }

    function approve_hook(address gem, uint256 wad) public {
        Gem(gem).approve(address(bank), wad);
    }

    function approve_sender(address gem, uint256 wad) public {
        Gem(gem).approve(msg.sender, wad);
    }

    function welch(address[] memory gems, uint256[] memory wads, uint256 welch_index) public {
        for (uint256 i = 0; i < gems.length; i++) {
            approve_hook(gems[i], wads[i]);
            if (i == welch_index) {
                Gem(gems[i]).transfer(address(0), 1);
            }
        }
    }

    function failure() public pure {
        revert ErrBroken();
    }

    function reenter(address gem, uint256 wad) public {
        bytes memory data = abi.encodeCall(this.approve_hook, (gem, wad));
        address[] memory gems = new address[](1);
        uint256[] memory wads = new uint256[](1);
        gems[0] = gem;
        wads[0] = wad;
        if (gem == address(rico)) Vat(bank).flash(address(this), data);
        else ERC20Hook(bank).erc20flash(gems, wads, address(this), data);
        approve_hook(gem, wad);
    }

    function borrow_gem_after_rico(address gem, uint256 wad) public {
        bytes memory data = abi.encodeCall(this.approve_hook, (gem, wad));
        require(rico.balanceOf(address(this)) >= Vat(bank).MINT(), "missing borrowed rico");
        address[] memory gems = new address[](1);
        uint256[] memory wads = new uint256[](1);
        gems[0] = gem;
        wads[0] = wad;
        ERC20Hook(bank).erc20flash(gems, wads, address(this), data);
    }
    function multi_borrow(address gem1, uint256 bal1, address gem2, uint256 bal2) public {
        require(Gem(gem1).balanceOf(address(this)) >= bal1, 'missing borrowed tokens 1');
        require(Gem(gem2).balanceOf(address(this)) >= bal2, 'missing borrowed tokens 2');
        approve_hook(gem1, bal1);
        approve_hook(gem2, bal2);
    }

    function rico_lever(address gem, uint256 lock_amt, uint256 draw_amt) public {
        _buy_gem(gem, draw_amt);
        approve_hook(gem, lock_amt);
        Vat(bank).frob(ilk0, address(this), abi.encodePacked(lock_amt), int(draw_amt));
    }

    function rico_release(address gem, uint256 free_amt, uint256 wipe_amt) public {
        Vat(bank).frob(ilk0, address(this), abi.encodePacked(-int(free_amt)), -int(wipe_amt));
        _sell_gem(gem, wipe_amt);
    }

    function gem_lever(address gem, uint256 lock_amt, uint256 draw_amt) public {
        approve_hook(gem, lock_amt);
        Vat(bank).frob(ilk0, address(this), abi.encodePacked(lock_amt), int(draw_amt));
        _buy_gem(gem, draw_amt);
        approve_hook(gem, lock_amt);
    }

    function gem_release(address gem, uint256 free_amt, uint256 wipe_amt) public {
        _sell_gem(gem, wipe_amt);
        Vat(bank).frob(ilk0, address(this), abi.encodePacked(-int(free_amt)), -int(wipe_amt));
        approve_hook(gem, wipe_amt);
    }

    function _buy_gem(address gem, uint256 amount) internal {
        rico.burn(address(this), amount);
        Gem(gem).mint(address(this), amount);
    }

    function _sell_gem(address gem, uint256 amount) internal {
        Gem(gem).burn(address(this), amount);
        rico.mint(address(this), amount);
    }
}
