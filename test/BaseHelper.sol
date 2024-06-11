// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.25;
import 'forge-std/Test.sol';

import '../src/mixin/math.sol';
import { Vat } from '../src/vat.sol';
import { Vow } from '../src/vow.sol';
import { Vox } from '../src/vox.sol';
import { File } from '../src/file.sol';
import { Bank } from '../src/bank.sol';
import { BankDiamond } from '../src/diamond.sol';
import { Diamond, IDiamondCuttable } from "../lib/solidstate-solidity/contracts/proxy/diamond/Diamond.sol";

abstract contract BaseHelper is Math, Test {
    address immutable public self = payable(address(this));

    bytes32[] public empty = new bytes32[](0);
    address payable public bank;

    receive () payable external {}

    function _ink(address usr) internal view returns (uint) {
        Vat.Urn memory urn = Vat(bank).urns(usr);
        return urn.ink;
    }

    function _art(address usr) internal view returns (uint) {
        Vat.Urn memory urn = Vat(bank).urns(usr);
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

    IDiamondCuttable.FacetCutAction internal constant REPLACE = IDiamondCuttable.FacetCutAction.REPLACE;

    function file_imm(bytes32 key, bytes32 val) internal {
        Bank.BankParams memory saved_bank = Bank.BankParams(
            address(File(bank).rico()),
            address(File(bank).risk())
        );
        Vow.VowParams memory saved_vow = Vow.VowParams(
            Vow(bank).wel(),
            Vow(bank).dam(),
            Vow(bank).pex(),
            Vow(bank).mop(),
            Vow(bank).lax()
        );
        Vox.VoxParams memory saved_vox = Vox.VoxParams(
            Vox(bank).how(),
            Vox(bank).cap()
        );

        // bank
             if (key == 'rico') { saved_bank.rico = address(bytes20(val)); }
        else if (key == 'risk') { saved_bank.risk = address(bytes20(val)); }
        // vat
        // vow
        else if (key == 'wel') { saved_vow.wel = uint(val); }
        else if (key == 'dam') { saved_vow.dam = uint(val); }
        else if (key == 'pex') { saved_vow.pex = uint(val); }
        else if (key == 'mop') { saved_vow.mop = uint(val); }
        else if (key == 'lax') { saved_vow.lax = uint(val); }
        // vox
        else if (key == 'how') { saved_vox.how = uint(val); }
        else if (key == 'cap') { saved_vox.cap = uint(val); }
        else { revert('file_imm: bad key'); }

        Vat vat = new Vat(saved_bank);
        Vow vow = new Vow(saved_bank, saved_vow);
        Vox vox = new Vox(saved_bank, saved_vox);

        bytes4[] memory vatsels = Diamond(bank).facetFunctionSelectors(
            Diamond(bank).facetAddress(Vat.frob.selector)
        );

        bytes4[] memory vowsels = Diamond(bank).facetFunctionSelectors(
            Diamond(bank).facetAddress(Vow.keep.selector)
        );

        bytes4[] memory voxsels = Diamond(bank).facetFunctionSelectors(
            Diamond(bank).facetAddress(Vox.poke.selector)
        );

        IDiamondCuttable.FacetCut[] memory facetCuts = new IDiamondCuttable.FacetCut[](3);
        facetCuts[0] = IDiamondCuttable.FacetCut(address(vat),  REPLACE, vatsels);
        facetCuts[1] = IDiamondCuttable.FacetCut(address(vow),  REPLACE, vowsels);
        facetCuts[2] = IDiamondCuttable.FacetCut(address(vox),  REPLACE, voxsels);

        Diamond(bank).diamondCut(facetCuts, address(0), bytes(""));
    }

    function file(bytes32 key, bytes32 val) public {
        if (
            // bank
            key == 'rico' || key == 'risk' ||
            // vow
            key == 'wel'  || key == 'dam'  || key == 'pex'  ||
            key == 'mop'  || key == 'lax'  ||
            // vox
            key == 'cap'  || key == 'how'  ||
            // vat
            key == 'ceil'
        ) {
            file_imm(key, val);
        } else {
            File(bank).file(key, val);
        }
    }

    function set_dxm(bytes32 key, uint price) public {
        file(key, bytes32(rdiv(price, Vow(bank).pex())));
        file('bel', bytes32(block.timestamp - 1));
    }

}
