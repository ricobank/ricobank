/// SPDX-License-Identifier: AGPL-3.0

// Copyright (C) 2021-2024 halys

// The cannonball is the canonical deployment sequence
// implemented as one big contract. You can diff more
// efficient deployment sequences against the result of
// this one.

pragma solidity ^0.8.25;

import {Diamond, IDiamondCuttable} from "../lib/solidstate-solidity/contracts/proxy/diamond/Diamond.sol";
import {Ownable, OwnableStorage} from "../lib/solidstate-solidity/contracts/access/Ownable.sol";

import {Gem} from "../lib/gemfab/src/gem.sol";

import {Vat} from "./vat.sol";
import {Vow} from "./vow.sol";
import {Vox} from "./vox.sol";
import {Bank} from "./bank.sol";
import {File} from "./file.sol";
import {Math} from "./mixin/math.sol";

contract Ball is Math, Ownable {
    bytes32 internal constant HOW = bytes32(uint256(1000000000000003652500000000));
    bytes32 internal constant CAP = bytes32(uint256(1000000021970000000000000000));
    IDiamondCuttable.FacetCutAction internal constant ADD = IDiamondCuttable.FacetCutAction.ADD;
    using OwnableStorage for OwnableStorage.Layout;

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
        uint256 wel;
        uint256 dam;
        uint256 pex;
        uint256 gif;
        uint256 mop;
        uint256 lax;
        uint256 how;
        uint256 cap;
    }

    address public rico;
    address public risk;

    Vat public vat;
    Vow public vow;
    Vox public vox;

    address payable public bank;
    File public file;

    constructor(BallArgs memory args) {
        Bank.BankParams memory bp = Bank.BankParams(args.rico, args.risk);
        vat  = new Vat(bp);
        vow  = new Vow(bp, Vow.VowParams(
            args.wel, args.dam, args.pex, args.mop, args.lax
        ));
        vox  = new Vox(bp, Vox.VoxParams(args.how, args.cap));
        file = new File(bp);

        bank = args.bank;
        rico = args.rico;
        risk = args.risk;
        OwnableStorage.layout().setOwner(msg.sender);
    }

    function setup(BallArgs calldata args) external onlyOwner {
        IDiamondCuttable.FacetCut[] memory facetCuts = new IDiamondCuttable.FacetCut[](4);
        bytes4[] memory filesels = new bytes4[](3);
        bytes4[] memory vatsels  = new bytes4[](14);
        bytes4[] memory vowsels  = new bytes4[](12);
        bytes4[] memory voxsels  = new bytes4[](5);
        File fbank = File(bank);

        filesels[0] = File.file.selector;
        filesels[1] = bytes4(keccak256(abi.encodePacked('rico()')));
        filesels[2] = bytes4(keccak256(abi.encodePacked('risk()')));
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
        vatsels[10] = Vat.par.selector;
        vatsels[11] = Vat.drip.selector;
        vatsels[12] = bytes4(keccak256(abi.encodePacked('FEE_MAX()')));
        vatsels[13] = Vat.get.selector;
        vowsels[0]  = Vow.keep.selector;
        vowsels[1]  = bytes4(keccak256(abi.encodePacked('dam()')));
        vowsels[2]  = bytes4(keccak256(abi.encodePacked('pex()')));
        vowsels[3]  = Vow.bel.selector;
        vowsels[4]  = bytes4(keccak256(abi.encodePacked('wel()')));
        vowsels[5]  = Vow.mine.selector;
        vowsels[6]  = Vow.gif.selector;
        vowsels[7]  = bytes4(keccak256(abi.encodePacked('mop()')));
        vowsels[8]  = Vow.phi.selector;
        vowsels[9]  = bytes4(keccak256(abi.encodePacked('lax()')));
        vowsels[10] = bytes4(keccak256(abi.encodePacked('LAX_MAX()')));
        vowsels[11] = Vow.wal.selector;
        voxsels[0]  = Vox.poke.selector;
        voxsels[1]  = Vox.way.selector;
        voxsels[2]  = bytes4(keccak256(abi.encodePacked('how()')));
        voxsels[3]  = bytes4(keccak256(abi.encodePacked('cap()')));
        voxsels[4]  = bytes4(keccak256(abi.encodePacked('CAP_MAX()')));

        facetCuts[0] = IDiamondCuttable.FacetCut(address(file), ADD, filesels);
        facetCuts[1] = IDiamondCuttable.FacetCut(address(vat),  ADD, vatsels);
        facetCuts[2] = IDiamondCuttable.FacetCut(address(vow),  ADD, vowsels);
        facetCuts[3] = IDiamondCuttable.FacetCut(address(vox),  ADD, voxsels);
        Diamond(payable(address(fbank))).acceptOwnership();
        Diamond(payable(address(fbank))).diamondCut(facetCuts, address(0), bytes(""));

        fbank.file("par",  bytes32(args.par));
        fbank.file("bel", bytes32(block.timestamp));
        fbank.file("gif", bytes32(args.gif));
        fbank.file("phi", bytes32(block.timestamp));
        fbank.file("wal", bytes32(Gem(risk).totalSupply()));
        fbank.file("way", bytes32(RAY));
    }

    function makeilk(IlkParams calldata ilkparams) external onlyOwner {
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

    function approve(address usr) external onlyOwner {
        Diamond(bank).transferOwnership(usr);
    }

    function accept() external onlyOwner {
        Diamond(bank).acceptOwnership();
    }

}
