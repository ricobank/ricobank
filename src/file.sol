// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2024 halys

pragma solidity ^0.8.25;
import { Gem }  from "../lib/gemfab/src/gem.sol";
import { Bank } from "./bank.sol";
import { Diamond } from "./diamond.sol";
import { Vox } from "./vox.sol";

contract File is Bank {
    constructor(BankParams memory bp) Bank(bp) {}

    function file(bytes32 key, bytes32 val) external payable onlyOwner _flog_ {
        VatStorage storage vatS = getVatStorage();
        VowStorage storage vowS = getVowStorage();
        VoxStorage storage voxS = getVoxStorage();
        uint _val = uint(val);

               if (key == "par") { vatS.par = _val;
        } else if (key == "bel") {
            must(_val, 0, block.timestamp);
            vowS.bel = _val;
        } else if (key == "gif") { vowS.gif = _val;
        } else if (key == "phi") {
            must(_val, 0, block.timestamp);
            vowS.phi = _val;
        } else if (key == "way") {
            uint cap = Vox(address(this)).cap();
            must(_val, rinv(cap), cap);
            voxS.way = _val;
        } else revert ErrWrongKey();

        emit NewPalm0(key, val);
    }

    function close() external onlyOwner {
        Diamond(payable(address(this))).acceptOwnership();
    }

}
