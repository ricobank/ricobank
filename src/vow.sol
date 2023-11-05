// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2023 halys

pragma solidity ^0.8.19;

import { Vat }  from "./vat.sol";
import { Bank, Gem } from "./bank.sol";

// accounting mechanism
// triggers collateral (flip), surplus (flap), and deficit (flop) auctions
contract Vow is Bank {
    function RISK() external view returns (Gem) {return getVowStorage().risk;}
    function ramp() external view returns (Ramp memory) {
        return getVowStorage().ramp;
    }
    function toll() external view returns (uint) { return getVowStorage().toll; }
    function rudd() external view returns (Rudd memory) { return getVowStorage().rudd; }
    function plat() external view returns (Plx memory) { return getVowStorage().plat; }
    function plot() external view returns (Plx memory) { return getVowStorage().plot; }

    error ErrReflop();
    error ErrOutDated();

    function keep(bytes32[] calldata ilks) external payable _flog_ {
        VowStorage storage  vowS  = getVowStorage();
        VatStorage storage  vatS  = getVatStorage();
        BankStorage storage bankS = getBankStorage();

        for (uint256 i = 0; i < ilks.length;) {
            Vat(address(this)).drip(ilks[i]);
            unchecked {++i;}
        }

        Gem rico = bankS.rico;
        Gem risk = vowS.risk;
        uint joy = vatS.joy;

        // use equal scales for sin and joy
        uint sin = vatS.sin / RAY;
        if (joy > sin) {

            // pay down sin, then auction off surplus RICO for RISK
            if (sin > 1) {
                // gas - don't zero sin
                joy = _heal(sin - 1);
            }

            // mash decreases as surplus increases, i.e. if there's a massive
            // surplus the system deduces that it's overpricing rico
            uint price = _price();
            uint mcap  = rmul(price, risk.totalSupply());
            uint mash  = rpow(rdiv(mcap, mcap + joy), vowS.plat.pep);
            mash       = rmul(vowS.plat.pop, mash);

            // buy-and-burn risk with remaining (`flap`) rico
            uint flap  = wmul(joy - 1, vowS.ramp.wel);
            joy       -= flap;
            vatS.joy   = joy;
            emit NewPalm0("joy", bytes32(joy));

            uint sell  = rmul(flap, RAY - vowS.toll);
            uint earn  = rmul(sell, rdiv(mash, price) + 1) + 1;

            // swap rico for RISK, pay protocol fee
            Gem(risk).burn(msg.sender, earn);
            Gem(rico).mint(msg.sender, sell);
            if (sell < flap) Gem(rico).mint(owner(), flap - sell);

        } else if (sin > joy) {

            // mint-and-sell risk to cover `under`
            uint under = sin - joy;

            // pay down as much sin as possible
            if (joy > 1) {
                // gas - don't zero joy
                joy = _heal(joy - 1);
            }

            // mash decreases as system becomes undercollateralized
            // i.e. if it's very undercollateralized then bank deduces
            // that it's overpricing RISK
            uint price = _price();
            uint mcap  = rmul(price, risk.totalSupply());
            uint mash  = rpow(rdiv(mcap, mcap + under), vowS.plot.pep);
            mash       = rmul(vowS.plot.pop, mash);

            // rate-limit flop
            uint elapsed = min(block.timestamp - vowS.ramp.bel, vowS.ramp.cel);
            uint flop    = elapsed * wmul(vowS.ramp.rel, risk.totalSupply());
            if (0 == flop) revert ErrReflop();

            // swap RISK for rico to cover sin
            uint earn = rmul(flop, rmul(price, mash));
            uint bel  = block.timestamp;
            if (earn > under) {
                // always advances >= 1s from max(vowS.bel, timestamp - cel)
                bel  -= wmul(elapsed, WAD - wdiv(under, earn));
                flop  = flop * under / earn;
                earn  = under;
            }

            // update last flop stamp
            vowS.ramp.bel = bel;
            emit NewPalm0("bel", bytes32(bel));

            Gem(rico).burn(msg.sender, earn);
            Gem(risk).mint(msg.sender, flop);

            // new joy will heal some sin in next flop
            joy     += earn;
            vatS.joy = joy;
            emit NewPalm0("joy", bytes32(joy));

        }
    }

    function _heal(uint wad) internal returns (uint joy) {
        VatStorage storage vs = getVatStorage();

        vs.sin  = vs.sin  - (wad * RAY);
        emit NewPalm0("sin", bytes32(vs.sin));

        vs.joy  = (joy = vs.joy - wad);
        emit NewPalm0("joy", bytes32(joy));

        vs.debt = vs.debt - wad;
        emit NewPalm0("debt", bytes32(vs.debt));
    }

    function _price() internal view returns (uint) {
        BankStorage storage bankS = getBankStorage();
        VowStorage  storage vowS  = getVowStorage();
        (bytes32 _val, uint ttl)  = bankS.fb.pull(vowS.rudd.src, vowS.rudd.tag);
        if (ttl < block.timestamp) revert ErrOutDated();
        return uint(_val);
    }

}
