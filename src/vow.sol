// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2023 halys

pragma solidity ^0.8.19;

import { Gem }  from '../lib/gemfab/src/gem.sol';
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

        Gem rico = bankS.rico;
        Gem risk = vowS.RISK;
        uint ricobal = rico.balanceOf(address(this));
        uint riskbal = risk.balanceOf(address(this));
        risk.burn(address(this), riskbal);

        // rico is a wad, sin is a rad
        uint sin = vatS.sin / RAY;
        if (ricobal > sin) {
            // pay down sin, then auction off surplus RICO for RISK
            if (sin > 1) Vat(address(this)).heal(sin - 1);

            // buy-and-burn risk with remaining (`over`) rico
            uint over = ricobal - sin;

            // rush increases as surplus increases, i.e. if there's a massive
            // surplus the system deduces that it's overpricing rico
            uint debt = vatS.debt;
            uint rush = (over * vowS.flappep + debt * vowS.flappop) / debt;

            // swap the surplus for RISK
            flow(vowS.flapsrc, vowS.flaptag, rico, over, risk, rush);
        } else if (sin > ricobal) {
            // pay down as much sin as possible
            if (ricobal > 1) Vat(address(this)).heal(ricobal - 1);

            // mint-and-sell risk to cover `under`
            uint under = sin - ricobal;

            // rush increases as system becomes undercollateralized
            // i.e. if it's very undercollateralized then bank deduces
            // that it's overpricing RISK
            uint debt  = vatS.debt;
            uint rush  = (under * vowS.floppep + debt * vowS.floppop) / debt;

            // rate-limit flop
            uint slope = min(vowS.ramp.vel, wmul(vowS.ramp.rel, risk.totalSupply()));
            uint flop  = slope * min(block.timestamp - vowS.ramp.bel, vowS.ramp.cel);
            if (0 == flop) revert ErrReflop();

            vowS.ramp.bel = block.timestamp;
            emit NewPalm0('bel', bytes32(vowS.ramp.bel));

            // swap RISK for rico to cover sin
            risk.mint(address(this), flop);
            flow(vowS.flopsrc, vowS.floptag, risk, flop, rico, rush);
        }
    }

    function flow(
        address src, bytes32 tag, Gem hag, uint ham, Gem wag, uint rush
    ) internal {
        // pull the feed to get the earn (in rico for flop, risk for flap)
        // if rush was 1.0
        (bytes32 val, uint ttl) = getBankStorage().fb.pull(src, tag);
        if (ttl < block.timestamp) revert ErrOutDated();
        uint cut = ham * uint(val);

        // cut is RAD, rush is RAY, so bank earns a WAD
        uint earn = cut / rush;
        if (!Gem(wag).transferFrom(msg.sender, address(this), earn)) revert ErrTransfer();
        if (!Gem(hag).transfer(msg.sender, ham)) revert ErrTransfer();
    }

}
