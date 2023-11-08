// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2023 halys

pragma solidity ^0.8.19;
import { Gem }  from "../lib/gemfab/src/gem.sol";
import { Feedbase } from "../lib/feedbase/src/Feedbase.sol";
import { Bank } from "./bank.sol";

contract File is Bank {
    uint constant _CAP_MAX = 1000000072964521287979890107; // ~10x/yr
    uint constant _REL_MAX = 10 * WAD / BANKYEAR; // ~10x/yr
    function CAP_MAX() external pure returns (uint) {return _CAP_MAX;}
    function REL_MAX() external pure returns (uint) {return _REL_MAX;}

    function file(bytes32 key, bytes32 val) external payable onlyOwner _flog_ {
        VatStorage storage vatS = getVatStorage();
        VowStorage storage vowS = getVowStorage();
        VoxStorage storage voxS = getVoxStorage();
        BankStorage storage bankS = getBankStorage();
        uint _val = uint(val);
        // bank
        if (key == "rico") { bankS.rico = Gem(address(bytes20(val))); }
        else if (key == "fb") { bankS.fb = Feedbase(address(bytes20(val))); }
        // vat
        else if (key == "ceil") { vatS.ceil = _val; }
        else if (key == "par") { vatS.par = _val; }
        // vow
        else if (key == "rel") {
            shld(_val, 0, _REL_MAX);
            vowS.ramp.rel = _val;
        }
        else if (key == "bel") {
            shld(_val, 0, block.timestamp);
            vowS.ramp.bel = _val;
        }
        else if (key == "cel") { vowS.ramp.cel = _val; }
        else if (key == "wel") {
            must(_val, 0, WAD);
            vowS.ramp.wel = _val;
        }
        else if (key == "toll") {
            must(_val, 0, RAY);
            vowS.toll = _val;
        }
        else if (key == "plot.pep") { vowS.plot.pep = _val; }
        else if (key == "plat.pep") { vowS.plat.pep = _val; }
        else if (key == "plot.pop") {
            shld(_val, RAY / 10, 10 * RAY);
            vowS.plot.pop = _val;
        }
        else if (key == "plat.pop") {
            shld(_val, RAY / 10, 10 * RAY);
            vowS.plat.pop = _val;
        }
        else if (key == "rudd.src") { vowS.rudd.src = address(bytes20(bytes32(val))); }
        else if (key == "rudd.tag") { vowS.rudd.tag = val; }
        else if (key == "risk") { vowS.risk = Gem(address(bytes20(val))); }
        // vox
        else if (key == "tip.src") { voxS.tip.src = address(bytes20(val)); }
        else if (key == "tip.tag") { voxS.tip.tag = val; }
        else if (key == "how") {
            must(_val, RAY, type(uint).max);
            voxS.how = _val; }
        else if (key == "cap") {
            must(_val, RAY, type(uint).max);
            shld(_val, RAY, _CAP_MAX);
            voxS.cap = _val;
        }
        else if (key == "tau") {
            must(_val, block.timestamp, type(uint).max);
            voxS.tau = _val;
        }
        else if (key == "way") {
            must(_val, rinv(voxS.cap), voxS.cap);
            voxS.way = _val;
        }
        else if (key == "care") { bankS.care = bytes32(0) == val ? false : true; }
        else revert ErrWrongKey();
        emit NewPalm0(key, val);
    }

    function rico() external view returns (Gem) {return getBankStorage().rico;}
    function fb() external view returns (Feedbase) {return getBankStorage().fb;}
    function care() external view returns (bool) {return getBankStorage().care;}
}
