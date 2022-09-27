// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.15;

import '../vat.sol';
import '../vow.sol';

// Setting duty requires a drip in same block, hh tests use auto mine
contract DutySetter {
    function set_duty(Vat vat, Vow vow, bytes32 ilk, bytes32 key, uint val) external {
        vat.drip(ilk);
        vat.filk(ilk, key, val);
    }
}
