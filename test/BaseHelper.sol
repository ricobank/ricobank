// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.25;
import 'forge-std/Test.sol';

import '../src/mixin/math.sol';
import { Vat } from '../src/vat.sol';
import { Vow } from '../src/vow.sol';
import { File } from '../src/file.sol';
import { BankDiamond } from '../src/diamond.sol';

abstract contract BaseHelper is Math, Test {
    address immutable public self = payable(address(this));

    bytes32[] public empty = new bytes32[](0);
    address payable public bank;

    receive () payable external {}

    function _ink(bytes32 ilk, address usr) internal view returns (uint) {
        Vat.Urn memory urn = Vat(bank).urns(ilk, usr);
        return urn.ink;
    }

    function _art(bytes32 ilk, address usr) internal view returns (uint) {
        Vat.Urn memory urn = Vat(bank).urns(ilk, usr);
        return urn.art;
    }

    function make_diamond() internal returns (address payable deployed) {
        return payable(address(new BankDiamond()));
    }

    function assertClose(uint v1, uint v2, uint rel) internal pure {
        uint abs = v1 / rel;
        assertGt(v1 + abs, v2);
        assertLt(v1 - abs, v2);
    }

    // useful for clarity wrt which ilks keep drips
    function single(bytes32 x) internal pure returns (bytes32[] memory res) {
        res = new bytes32[](1);
        res[0] = x;
    }

    function set_dxm(bytes32 key, uint price) public {
        File(bank).file(key, bytes32(rdiv(price, Vow(bank).pex())));
        File(bank).file('bel', bytes32(block.timestamp - 1));
    }

}
