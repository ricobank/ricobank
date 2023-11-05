/// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 the bank

pragma solidity ^0.8.19;
import 'forge-std/Test.sol';

import { Vat, Math, Gem, ERC20Hook } from './RicoHelper.sol';

contract Flasher is Math {
    Gem     rico;
    bytes32 ilk0;
    error   ErrBroken();
    address payable bank;

    constructor(address payable _bank, address rico_, bytes32 ilk0_) {
        bank = _bank;
        rico = Gem(rico_);
        ilk0 = ilk0_;
    }

    function nop() public {}

    function approve_hook(address gem, uint256 wad) public {
        Gem(gem).approve(address(bank), wad);
    }

    function approve_sender(address gem, uint256 wad) public {
        Gem(gem).approve(msg.sender, wad);
    }

    // approve all gems to bank, but throw away a little bit of one
    function welch(address[] calldata gems, uint256[] calldata wads, uint256 welch_index) public {
        for (uint256 i = 0; i < gems.length; i++) {
            approve_hook(gems[i], wads[i]);
            if (i == welch_index) {
                Gem(gems[i]).transfer(address(1), 1);
            }
        }
    }

    function failure() public pure { revert ErrBroken(); }

    function reenter(address gem, uint256 wad) public {
        bytes memory data = abi.encodeCall(this.approve_hook, (gem, wad));
        address[] memory gems = new address[](1);
        uint256[] memory wads = new uint256[](1);
        gems[0] = gem;
        wads[0] = wad;
        Vat(bank).flash(address(this), data);
        approve_hook(gem, wad);
    }

    // trade some flashed rico for gem, then use gem as collateral to pay flash back
    function rico_lever(address gem, uint256 lock_amt, uint256 draw_amt) public {
        require(Vat(bank).ilks(ilk0).rack == RAY, 'rico_lever: rack must be 1');
        // use the flashed rico to buy some gem
        _buy_gem(gem, draw_amt);
        approve_hook(gem, lock_amt);

        // frob to compensate for what was lost
        Vat(bank).frob(ilk0, address(this), abi.encodePacked(lock_amt), int(draw_amt));
    }

    // use the flashed rico to pay down a loan, sell some collateral to pay flash back
    function rico_release(address gem, uint256 free_amt, uint256 wipe_amt) public {
        Vat(bank).frob(ilk0, address(this), abi.encodePacked(-int(free_amt)), -int(wipe_amt));
        _sell_gem(gem, wipe_amt);
    }

    function _buy_gem(address gem, uint256 amount) internal {
        rico.transfer(address(1), amount);
        Gem(gem).mint(address(this), amount);
    }

    function _sell_gem(address gem, uint256 amount) internal {
        Gem(gem).burn(address(this), amount);
        rico.mint(address(this), amount);
    }
}
