// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2023 halys

pragma solidity ^0.8.19;

import { Vat }  from './vat.sol';
import { Bank, Gem, OwnableStorage } from './bank.sol';

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
        uint joy = vatS.joy;

        // use equal scales for sin and joy
        uint sin = vatS.sin / RAY;
        if (joy > sin) {

            // pay down sin, then auction off surplus RICO for RISK
            uint flap = joy - sin;
            if (sin > 1) {
                // gas - don't zero sin
                Vat(address(this)).heal(sin - 1);
                joy -= sin - 1;
            } else {
                // gas - don't zero joy
                flap -= 1;
            }

            // rush increases as surplus increases, i.e. if there's a massive
            // surplus the system deduces that it's overpricing rico
            uint debt = vatS.debt;
            uint rush = (flap * vowS.flappep + debt * vowS.flappop) / debt;

            // buy-and-burn risk with remaining (`flap`) rico
            joy     -= flap;
            vatS.joy = joy;
            emit NewPalm0('joy', bytes32(joy));

            uint price = rdiv(_price(vowS.flapsrc, vowS.flaptag), rush) + 1;
            uint sell  = rmul(flap, RAY - vowS.toll);
            uint earn  = rmul(sell, price) + 1;

            // swap rico for RISK, pay protocol fee
            Gem(risk).burn(msg.sender, earn);
            Gem(rico).mint(msg.sender, sell);
            if (sell < flap) Gem(rico).mint(owner(), flap - sell);

        } else if (sin > joy) {

            // pay down as much sin as possible
            if (joy > 1) {
                // gas - don't zero joy
                Vat(address(this)).heal(joy - 1);
                joy = 1;
            }

            // mint-and-sell risk to cover `under`
            uint under = sin - joy;

            // rush increases as system becomes undercollateralized
            // i.e. if it's very undercollateralized then bank deduces
            // that it's overpricing RISK
            uint debt  = vatS.debt;
            uint rush  = (under * vowS.floppep + debt * vowS.floppop) / debt;

            // rate-limit flop
            uint slope = min(vowS.ramp.vel, wmul(vowS.ramp.rel, risk.totalSupply()));
            uint flop  = slope * min(block.timestamp - vowS.ramp.bel, vowS.ramp.cel);
            if (0 == flop) revert ErrReflop();

            // update last flop stamp
            vowS.ramp.bel = block.timestamp;
            emit NewPalm0('bel', bytes32(vowS.ramp.bel));

            // swap RISK for rico to cover sin
            uint earn = flop * _price(vowS.flopsrc, vowS.floptag) / rush;
            Gem(rico).burn(msg.sender, earn);
            Gem(risk).mint(msg.sender, flop);

            // new joy will heal some sin in next flop
            joy     += earn;
            vatS.joy = joy;
            emit NewPalm0('joy', bytes32(joy));

        }
    }

    function _price(address src, bytes32 tag) internal view returns (uint) {
        (bytes32 _val, uint ttl) = getBankStorage().fb.pull(src, tag);
        if (ttl < block.timestamp) revert ErrOutDated();
        return uint(_val);
    }

}
