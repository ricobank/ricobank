/// SPDX-License-Identifier: AGPL-3.0

// Copyright (C) 2021-2024 halys

// The cannonball is the canonical deployment sequence
// implemented as one big contract. You can diff more
// efficient deployment sequences against the result of
// this one.

pragma solidity ^0.8.25;

import {Diamond, IDiamondCuttable} from "../lib/solidstate-solidity/contracts/proxy/diamond/Diamond.sol";

import {Gem} from "../lib/gemfab/src/gem.sol";

import {Vat} from "./vat.sol";
import {Vow} from "./vow.sol";
import {Vox} from "./vox.sol";
import {File} from "./file.sol";
import {Math} from "./mixin/math.sol";

contract Ball is Math {
    bytes32 internal constant HOW = bytes32(uint256(1000000000000003652500000000));
    bytes32 internal constant CAP = bytes32(uint256(1000000021970000000000000000));
    bytes32[] internal empty = new bytes32[](0);
    IDiamondCuttable.FacetCutAction internal constant ADD = IDiamondCuttable.FacetCutAction.ADD;

    struct IlkParams {
        bytes32 ilk;
        uint256 chop;
        uint256 dust;
        uint256 fee;
        uint256 line;
        uint256 liqr;
    }

    struct BallArgs {
        address payable bank; // diamond
        address rico;
        address risk;
        uint256 par;
        uint256 ceil;
        Vow.Ramp ramp;
    }

    address public rico;
    address public risk;

    Vat public vat;
    Vow public vow;
    Vox public vox;

    address payable public bank;
    File public file;

    constructor(BallArgs memory args) {
        vat  = new Vat();
        vow  = new Vow();
        vox  = new Vox();
        file = new File();

        bank = args.bank;
        rico = args.rico;
        risk = args.risk;
    }

    bool done;
    function setup(BallArgs calldata args) external {
        if (done) revert('done');
        IDiamondCuttable.FacetCut[] memory facetCuts = new IDiamondCuttable.FacetCut[](4);
        bytes4[] memory filesels = new bytes4[](4);
        bytes4[] memory vatsels  = new bytes4[](16);
        bytes4[] memory vowsels  = new bytes4[](5);
        bytes4[] memory voxsels  = new bytes4[](4);
        File fbank = File(bank);

        filesels[0] = File.file.selector;
        filesels[1] = File.rico.selector;
        filesels[2] = File.CAP_MAX.selector;
        filesels[3] = File.REL_MAX.selector;
        vatsels[0]  = Vat.filk.selector;
        vatsels[1]  = Vat.init.selector;
        vatsels[2]  = Vat.frob.selector;
        vatsels[3]  = Vat.bail.selector;
        vatsels[4]  = Vat.safe.selector;
        vatsels[5]  = Vat.joy.selector;
        vatsels[6] = Vat.sin.selector;
        vatsels[7] = Vat.ilks.selector;
        vatsels[8] = Vat.urns.selector;
        vatsels[9] = Vat.rest.selector;
        vatsels[10] = Vat.debt.selector;
        vatsels[11] = Vat.ceil.selector;
        vatsels[12] = Vat.par.selector;
        vatsels[13] = Vat.drip.selector;
        vatsels[14] = Vat.FEE_MAX.selector;
        vatsels[15] = Vat.get.selector;
        vowsels[0]  = Vow.keep.selector;
        vowsels[1]  = Vow.RISK.selector;
        vowsels[2]  = Vow.dam.selector;
        vowsels[3]  = Vow.pex.selector;
        vowsels[4]  = Vow.ramp.selector;
        voxsels[0]  = Vox.poke.selector;
        voxsels[1]  = Vox.way.selector;
        voxsels[2]  = Vox.how.selector;
        voxsels[3]  = Vox.cap.selector;

        facetCuts[0] = IDiamondCuttable.FacetCut(address(file), ADD, filesels);
        facetCuts[1] = IDiamondCuttable.FacetCut(address(vat),  ADD, vatsels);
        facetCuts[2] = IDiamondCuttable.FacetCut(address(vow),  ADD, vowsels);
        facetCuts[3] = IDiamondCuttable.FacetCut(address(vox),  ADD, voxsels);
        Diamond(payable(address(fbank))).acceptOwnership();
        Diamond(payable(address(fbank))).diamondCut(facetCuts, address(0), bytes(""));

        fbank.file("rico", bytes32(bytes20(rico)));
        fbank.file("risk", bytes32(bytes20(risk)));

        fbank.file("par",  bytes32(args.par));
        fbank.file("ceil", bytes32(args.ceil));

        fbank.file("dam", bytes32(RAY));

        fbank.file("bel", bytes32(block.timestamp));
        fbank.file("wel", bytes32(args.ramp.wel));

        fbank.file("how", HOW);
        fbank.file("cap", CAP);
        fbank.file("way", bytes32(RAY));

    }

    function makeilk(IlkParams calldata ilkparams) external {
        if (done) revert('done');
        bytes32 ilk = ilkparams.ilk;
        Vat(bank).init(ilk);
        Vat(bank).filk(ilk, "chop", bytes32(ilkparams.chop));
        Vat(bank).filk(ilk, "dust", bytes32(ilkparams.dust));
        Vat(bank).filk(ilk, "fee",  bytes32(ilkparams.fee));
        Vat(bank).filk(ilk, "line", bytes32(ilkparams.line));
        Vat(bank).filk(ilk, "liqr", bytes32(ilkparams.liqr));
        Vat(bank).filk(ilk, "pep",  bytes32(uint(2)));
        Vat(bank).filk(ilk, "pop",  bytes32(RAY));
    }

    function approve(address usr) external {
        if (done) revert('done');
        Diamond(bank).transferOwnership(usr);
        done = true;
    }

}
