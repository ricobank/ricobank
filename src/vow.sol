// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2023 the bank
// Copyright (C) 2022 the bank

pragma solidity ^0.8.19;

import { Gem }  from '../lib/gemfab/src/gem.sol';
import { Ward } from '../lib/feedbase/src/mixin/ward.sol';
import { Flog } from './mixin/flog.sol';
import { Math } from './mixin/math.sol';
import { Vat }  from './vat.sol';
import { ERC20Hook } from '../src/hook/ERC20hook.sol';
import { Bank } from './bank.sol';

// accounting mechanism
// triggers collateral (flip), surplus (flap), and deficit (flop) auctions
contract Vow is Bank {
    function RISK() view external returns (Gem) {return getVowStorage().RISK;}
    function ramp() view external returns (Ramp memory) {
        return getVowStorage().ramp;
    }
    function flapfeed() view external returns (address, bytes32) {
        return (getVowStorage().flapsrc, getVowStorage().flaptag);
    }
    function flopfeed() view external returns (address, bytes32) {
        return (getVowStorage().flopsrc, getVowStorage().floptag);
    }
    function flapplot() view external returns (uint, uint) {
        return (getVowStorage().flappep, getVowStorage().flappop);
    }
    function flopplot() view external returns (uint, uint) {
        return (getVowStorage().floppep, getVowStorage().floppop);
    }

    error ErrReflop();
    error ErrOutDated();
    error ErrTransfer();

    function keep(bytes32[] calldata ilks) _flog_ external {
        VowStorage storage  vowS  = getVowStorage();
        VatStorage storage  vatS  = getVatStorage();
        BankStorage storage bankS = getBankStorage();
        for (uint256 i = 0; i < ilks.length; i++) {
            Vat(address(this)).drip(ilks[i]);
        }
        uint rico = bankS.rico.balanceOf(address(this));
        uint risk = vowS.RISK.balanceOf(address(this));
        vowS.RISK.burn(address(this), risk);

        // rico is a wad, sin is a rad
        uint sin = vatS.sin / RAY;
        if (rico > sin) {
            // pay down sin, then auction off surplus RICO for RISK
            if (sin > 1) Vat(address(this)).heal(sin - 1);
            // buy-and-burn risk with remaining rico
            uint flap = rico - sin;
            uint debt = vatS.debt;
            uint rush = (flap * vowS.flappep + debt * vowS.flappop) / debt;
            flow(vowS.flapsrc, vowS.flaptag, address(bankS.rico), flap, address(vowS.RISK), rush);
        } else if (sin > rico) {
            // pay down as much sin as possible
            if (rico > 1) Vat(address(this)).heal(rico - 1);
            uint debt = vatS.debt;
            uint rush = ((sin - rico) * vowS.floppep + debt * vowS.floppop) / debt;
            uint slope = min(vowS.ramp.vel, wmul(vowS.ramp.rel, vowS.RISK.totalSupply()));
            uint flop  = slope * min(block.timestamp - vowS.ramp.bel, vowS.ramp.cel);
            if (0 == flop) revert ErrReflop();
            vowS.ramp.bel = block.timestamp;
            // mint-and-sell risk to cover remaining sin
            vowS.RISK.mint(address(this), flop);
            flow(vowS.flopsrc, vowS.floptag, address(vowS.RISK), flop, address(bankS.rico), rush);
        }
    }

    function flow(
        address src, bytes32 tag, address hag, uint ham, address wag, uint rush
    ) internal {
        (bytes32 val, uint ttl) = getBankStorage().fb.pull(src, tag);
        if (ttl < block.timestamp) revert ErrOutDated();
        uint cut = ham * uint(val);

        // cut is RAD, rush is RAY, so vow earns a WAD
        uint earn = cut / rush;
        if (!Gem(wag).transferFrom(msg.sender, address(this), earn)) revert ErrTransfer();
        if (!Gem(hag).transfer(msg.sender, ham)) revert ErrTransfer();
    }

}
