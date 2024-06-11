// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2024 halys

pragma solidity ^0.8.25;
import { Gem }  from "../lib/gemfab/src/gem.sol";
import { Bank } from "./bank.sol";
import { Vat } from "./vat.sol";
import { Vox } from "./vox.sol";

contract File is Bank {
    constructor(BankParams memory bp) Bank(bp) {}

    function file(bytes32 key, bytes32 val) external payable onlyOwner _flog_ {
        VatStorage storage vatS = getVatStorage();
        VowStorage storage vowS = getVowStorage();
        VoxStorage storage voxS = getVoxStorage();
        uint _val = uint(val);

               if (key == "par")  { vatS.par = _val;
        } else if (key == "line") { vatS.line = _val;
        } else if (key == "dust") {
            must(_val, 0, RAY);
            vatS.dust = _val;
        } else if (key == "pep")  { vatS.plot.pep = _val;
        } else if (key == "pop")  { vatS.plot.pop = _val;
        } else if (key == "pup")  { vatS.plot.pup = int(_val);
        } else if (key == "liqr") {
            must(_val, RAY, type(uint).max);
            vatS.liqr = _val;
        } else if (key == "chop") {
            must(_val, RAY, 10 * RAY);
            vatS.chop = _val;
        } else if (key == "fee") {
            must(_val, RAY, Vat(address(this)).FEE_MAX());
            Vat(address(this)).drip();
            vatS.fee = _val;
        } else if (key == "rack") {
            must(_val, RAY, type(uint).max);
            vatS.rack = _val;
        } else if (key == "rho") {
            must(_val, 0, block.timestamp);
            vatS.rho = _val;
        } else if (key == "bel") {
            must(_val, 0, block.timestamp);
            vowS.bel = _val;
        } else if (key == "gif") { vowS.gif = _val;
        } else if (key == "phi") {
            must(_val, 0, block.timestamp);
            vowS.phi = _val;
        } else if (key == "wal") {
            must(_val, 0, RAD);
            vowS.wal = _val;
        } else if (key == "way") {
            uint cap = Vox(address(this)).cap();
            must(_val, rinv(cap), cap);
            voxS.way = _val;
        } else revert ErrWrongKey();

        emit NewPalm0(key, val);
    }

}
