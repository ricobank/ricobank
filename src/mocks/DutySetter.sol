// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.15;

import '../vat.sol';

// Setting fee requires a drip in same block, hh tests use auto mine
contract FeeSetter {
    function set_fee(Vat vat, bytes32 ilk, uint val) external {
        vat.drip(ilk);
        vat.filk(ilk, "fee", val);
    }
}
