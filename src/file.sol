// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2023 halys

pragma solidity ^0.8.19;
import { Math } from './mixin/math.sol';
import { Flog } from './mixin/flog.sol';
import { Gem }  from '../lib/gemfab/src/gem.sol';
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { Bank } from './bank.sol';

contract File is Bank {
    error ErrHighToll();

    function file(bytes32 key, bytes32 val) onlyOwner _flog_ external {
        VatStorage storage vatS = getVatStorage();
        VowStorage storage vowS = getVowStorage();
        VoxStorage storage voxS = getVoxStorage();
        BankStorage storage bankS = getBankStorage();
        // bank
        if (key == "rico") { bankS.rico = Gem(address(bytes20(val))); }
        else if (key == 'fb') { bankS.fb = Feedbase(address(bytes20(val))); }
        // vat
        else if (key == "ceil") { vatS.ceil = uint(val); }
        else if (key == "par") { vatS.par = uint(val); }
        // vow
        else if (key == "vel") { vowS.ramp.vel = uint(val); }
        else if (key == "rel") { vowS.ramp.rel = uint(val); }
        else if (key == "bel") { vowS.ramp.bel = uint(val); }
        else if (key == "cel") { vowS.ramp.cel = uint(val); }
        else if (key == "toll") { 
            if (uint(val) > RAY) revert ErrHighToll();
            vowS.toll = uint(val);
        }
        else if (key == 'risk') { vowS.RISK = Gem(address(bytes20(val))); }
        else if (key == "floppep") { vowS.floppep = uint(val); }
        else if (key == "flappep") { vowS.flappep = uint(val); }
        else if (key == "floppop") { vowS.floppop = uint(val); }
        else if (key == "flappop") { vowS.flappop = uint(val); }
        else if (key == "flopsrc") { vowS.flopsrc = address(bytes20(val)); }
        else if (key == "flapsrc") { vowS.flapsrc = address(bytes20(val)); }
        else if (key == "floptag") { vowS.floptag = val; }
        else if (key == "flaptag") { vowS.flaptag = val; }
        // vox
        else if (key == "tip") { voxS.tip = address(bytes20(val)); }
        else if (key == "tag") { voxS.tag = val; }
        else if (key == "how") { voxS.how = uint256(val); }
        else if (key == "cap") { voxS.cap = uint256(val); }
        else if (key == "tau") { voxS.tau = uint256(val); }
        else if (key == "way") { voxS.way = uint256(val); }
        else revert ErrWrongKey();
        emit NewPalm0(key, val);
    }

    function rico() external view returns (Gem) {return getBankStorage().rico;}
    function fb() external view returns (Feedbase) {return getBankStorage().fb;}
}
