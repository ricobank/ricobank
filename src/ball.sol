/// SPDX-License-Identifier: AGPL-3.0

// Copyright (C) 2021-2024 halys

// The cannonball is the canonical deployment sequence
// implemented as one big contract. You can diff more
// efficient deployment sequences against the result of
// this one.

pragma solidity ^0.8.19;

import {Diamond, IDiamondCuttable} from "../lib/solidstate-solidity/contracts/proxy/diamond/Diamond.sol";
import {Block} from "../lib/feedbase/src/mixin/Read.sol";
import {ChainlinkAdapter} from "../lib/feedbase/src/adapters/ChainlinkAdapter.sol";
import {Divider} from "../lib/feedbase/src/combinators/Divider.sol";
import {Multiplier} from "../lib/feedbase/src/combinators/Multiplier.sol";
import {UniswapV3Adapter} from "../lib/feedbase/src/adapters/UniswapV3Adapter.sol";
import {Ward} from "../lib/feedbase/src/mixin/ward.sol";
import {Feedbase} from "../lib/feedbase/src/Feedbase.sol";

import {Gem} from "../lib/gemfab/src/gem.sol";

import {Vat} from "./vat.sol";
import {Vow} from "./vow.sol";
import {Vox} from "./vox.sol";
import {File} from "./file.sol";
import {Math} from "./mixin/math.sol";

contract Ball is Math, Ward {
    bytes32 internal constant RICO_DAI_TAG  = "rico:dai";
    bytes32 internal constant RICO_USD_TAG  = "rico:usd";
    bytes32 internal constant XAU_USD_TAG   = "xau:usd";
    bytes32 internal constant DAI_USD_TAG   = "dai:usd";
    bytes32 internal constant RICO_REF_TAG  = "rico:ref";
    bytes32 internal constant RISK_RICO_TAG = "risk:rico";
    bytes32 internal constant WETH_USD_TAG  = "weth:usd";
    bytes32 internal constant HOW = bytes32(uint256(1000000000000003652500000000));
    bytes32 internal constant CAP = bytes32(uint256(1000000021970000000000000000));
    bytes32[] internal empty = new bytes32[](0);
    IDiamondCuttable.FacetCutAction internal constant ADD = IDiamondCuttable.FacetCutAction.ADD;

    struct IlkParams {
        bytes32 ilk;
        address gem;
        address gemethagg;
        address gemusdagg;
        uint256 chop;
        uint256 dust;
        uint256 fee;
        uint256 line;
        uint256 liqr;
        uint256 ttl;
    }

    struct UniParams {
        bytes32 ilk;
        uint256 fee;
        uint256 chop;
        uint256 dust;
        uint256 line;
        uint256 room;
        address uniwrapper;
        address[] gems;
        address[] srcs;
        bytes32[] tags;
        uint256[] liqrs;
    }

    struct BallArgs {
        address payable bank; // diamond
        address feedbase;
        address uniadapt;
        address divider;
        address multiplier;
        address cladapt;
        address tokhook;
        address unihook;
        address rico;
        address risk;
        address ricodai;
        address ricorisk;
        address dai;
        address dai_usd_agg;
        address xau_usd_agg;
        uint256 par;
        uint256 ceil;
        uint256 uniadaptrange;
        uint256 uniadaptttl;
        uint256 daiusdttl;
        uint256 xauusdttl;
        Vow.Ramp mintramp;
    }

    address public rico;
    address public risk;

    Vat public vat;
    Vow public vow;
    Vox public vox;

    address public tokhook;
    address public unihook;

    address public feedbase;
    Divider public divider;
    Multiplier public multiplier;
    UniswapV3Adapter public uniadapt;
    ChainlinkAdapter public cladapt;

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
        feedbase   = args.feedbase;
        uniadapt   = UniswapV3Adapter(args.uniadapt);
        divider    = Divider(args.divider);
        multiplier = Multiplier(args.multiplier);
        cladapt    = ChainlinkAdapter(args.cladapt);
        tokhook = args.tokhook;
        unihook = args.unihook;
    }

    function setup(BallArgs calldata args) external _ward_ {
        IDiamondCuttable.FacetCut[] memory facetCuts = new IDiamondCuttable.FacetCut[](4);
        bytes4[] memory filesels = new bytes4[](5);
        bytes4[] memory vatsels  = new bytes4[](21);
        bytes4[] memory vowsels  = new bytes4[](5);
        bytes4[] memory voxsels  = new bytes4[](6);
        File fbank = File(bank);

        filesels[0] = File.file.selector;
        filesels[1] = File.fb.selector;
        filesels[2] = File.rico.selector;
        filesels[3] = File.CAP_MAX.selector;
        filesels[4] = File.REL_MAX.selector;
        vatsels[0]  = Vat.filk.selector;
        vatsels[1]  = Vat.filh.selector;
        vatsels[2]  = Vat.init.selector;
        vatsels[3]  = Vat.frob.selector;
        vatsels[4]  = Vat.bail.selector;
        vatsels[5]  = Vat.safe.selector;
        vatsels[6]  = Vat.joy.selector;
        vatsels[7] = Vat.sin.selector;
        vatsels[8] = Vat.ilks.selector;
        vatsels[9] = Vat.urns.selector;
        vatsels[10] = Vat.rest.selector;
        vatsels[11] = Vat.debt.selector;
        vatsels[12] = Vat.ceil.selector;
        vatsels[13] = Vat.par.selector;
        vatsels[14] = Vat.drip.selector;
        vatsels[15] = Vat.MINT.selector;
        vatsels[16] = Vat.FEE_MAX.selector;
        vatsels[17] = Vat.ink.selector;
        vatsels[18] = Vat.flash.selector;
        vatsels[19] = Vat.geth.selector;
        vatsels[20] = Vat.hookcallext.selector;
        vowsels[0]  = Vow.keep.selector;
        vowsels[1]  = Vow.RISK.selector;
        vowsels[2]  = Vow.ramp.selector;
        vowsels[3]  = Vow.loot.selector;
        vowsels[4]  = Vow.dam.selector;
        voxsels[0]  = Vox.poke.selector;
        voxsels[1]  = Vox.way.selector;
        voxsels[2]  = Vox.how.selector;
        voxsels[3]  = Vox.cap.selector;
        voxsels[4]  = Vox.tip.selector;
        voxsels[5]  = Vox.tau.selector;

        facetCuts[0] = IDiamondCuttable.FacetCut(address(file), ADD, filesels);
        facetCuts[1] = IDiamondCuttable.FacetCut(address(vat),  ADD, vatsels);
        facetCuts[2] = IDiamondCuttable.FacetCut(address(vow),  ADD, vowsels);
        facetCuts[3] = IDiamondCuttable.FacetCut(address(vox),  ADD, voxsels);
        Diamond(payable(address(fbank))).acceptOwnership();
        Diamond(payable(address(fbank))).diamondCut(facetCuts, address(0), bytes(""));

        fbank.file("rico", bytes32(bytes20(rico)));
        fbank.file("risk", bytes32(bytes20(risk)));
        fbank.file("fb",   bytes32(bytes20(feedbase)));

        fbank.file("par",  bytes32(args.par));
        fbank.file("ceil", bytes32(args.ceil));

        fbank.file("dam", bytes32(RAY));

        fbank.file("bel", bytes32(args.mintramp.bel));
        fbank.file("cel", bytes32(args.mintramp.cel));
        fbank.file("rel", bytes32(args.mintramp.rel));
        fbank.file("wel", bytes32(args.mintramp.wel));

        fbank.file("loot", bytes32(RAY));

        fbank.file("tip.src", bytes32(bytes20(address(divider))));
        fbank.file("tip.tag", RICO_REF_TAG);
        fbank.file("how", HOW);
        fbank.file("cap", CAP);
        fbank.file("tau", bytes32(block.timestamp));
        fbank.file("way", bytes32(RAY));

        // set feedbase component configs
        // rico/usd, rico/ref
        cladapt.setConfig(XAU_USD_TAG, ChainlinkAdapter.Config(args.xau_usd_agg, args.xauusdttl));
        cladapt.setConfig(DAI_USD_TAG, ChainlinkAdapter.Config(args.dai_usd_agg, args.daiusdttl));
        // rico/dai, dai/rico (== 1 / (rico/dai))
        uniadapt.setConfig(
            RICO_DAI_TAG,
            UniswapV3Adapter.Config(args.ricodai, args.dai < args.rico, args.uniadaptrange, args.uniadaptttl)
        );

        _configureBlock(multiplier, RICO_USD_TAG,
                       address(cladapt),  DAI_USD_TAG,
                       address(uniadapt), RICO_DAI_TAG, RAY);
        _configureBlock(divider, RICO_REF_TAG,
                       address(multiplier), RICO_USD_TAG,
                       address(cladapt),    XAU_USD_TAG, RAY);

        // risk:rico
        uniadapt.setConfig(
            RISK_RICO_TAG,
            UniswapV3Adapter.Config(args.ricorisk, args.risk < args.rico, args.uniadaptrange, args.uniadaptttl)
        );
    }

    function makeilk(IlkParams calldata ilkparams) external _ward_ {
        bytes32 ilk = ilkparams.ilk;
        bytes32 gemreftag = concat(ilk, ":ref");
        Vat(bank).init(ilk, tokhook);
        Vat(bank).filk(ilk, "chop", bytes32(ilkparams.chop));
        Vat(bank).filk(ilk, "dust", bytes32(ilkparams.dust));
        Vat(bank).filk(ilk, "fee",  bytes32(ilkparams.fee));
        Vat(bank).filk(ilk, "line", bytes32(ilkparams.line));
        Vat(bank).filh(ilk, "liqr", empty, bytes32(ilkparams.liqr));
        Vat(bank).filh(ilk, "gem", empty, bytes32(bytes20(ilkparams.gem)));
        Vat(bank).filh(ilk, "src", empty, bytes32(bytes20(address(divider))));
        Vat(bank).filh(ilk, "tag", empty, gemreftag);
        Vat(bank).filh(ilk, "pep", empty, bytes32(uint(2)));
        Vat(bank).filh(ilk, "pop", empty, bytes32(RAY));
        bytes32 gemusdtag = concat(ilk, ":usd");
        bytes32 gemclatag;
        address gemusdsrc;
        if (ilkparams.gemethagg == address(0)) {
            // ilk has feed sequence of gem/usd / rico/usd
            cladapt.setConfig(gemusdtag, ChainlinkAdapter.Config(ilkparams.gemusdagg, ilkparams.ttl));
            gemusdsrc = address(cladapt);
            gemclatag = gemusdtag;
        } else {
            // ilk has feed sequence of gem/eth * eth/usd / rico/usd
            bytes32 gemethtag = concat(ilk, ":eth");
            cladapt.setConfig(gemethtag, ChainlinkAdapter.Config(ilkparams.gemethagg, ilkparams.ttl));
            // add a multiplier config which reads gem/usd. Relies on weth ilk existing for weth:usd cladapter
            _configureBlock(multiplier, gemusdtag,
                            address(cladapt), gemethtag,
                            address(cladapt), WETH_USD_TAG, RAY);
            gemusdsrc = address(multiplier);
            gemclatag = gemethtag;
        }
        _configureBlock(divider, gemreftag,
                        address(gemusdsrc), gemusdtag,
                        address(cladapt),   XAU_USD_TAG,
                        10 ** (27 - (18 - Gem(ilkparams.gem).decimals())));
    }

    function makeuni(UniParams calldata ups) external _ward_ {
        Vat(bank).init(ups.ilk, unihook);
        Vat(bank).filh(ups.ilk, "room", empty, bytes32(ups.room));
        Vat(bank).filh(ups.ilk, "wrap", empty, bytes32(bytes20(address(ups.uniwrapper))));

        Vat(bank).filk(ups.ilk, "fee",  bytes32(ups.fee));
        Vat(bank).filk(ups.ilk, "chop", bytes32(ups.chop));
        Vat(bank).filk(ups.ilk, "dust", bytes32(ups.dust));
        Vat(bank).filk(ups.ilk, "line", bytes32(ups.line));

        Vat(bank).filh(ups.ilk, "pep",  empty, bytes32(uint(2)));
        Vat(bank).filh(ups.ilk, "pop",  empty, bytes32(RAY));

        for (uint i = 0; i < ups.gems.length; i++) {
            address gem = ups.gems[i];
            bytes32[] memory idxs = new bytes32[](1);
            idxs[0] = bytes32(bytes20(gem));
            Vat(bank).filh(ups.ilk, 'src', idxs, bytes32(bytes20(ups.srcs[i])));
            Vat(bank).filh(ups.ilk, 'tag', idxs, ups.tags[i]);
            Vat(bank).filh(ups.ilk, 'liqr', idxs, bytes32(ups.liqrs[i]));
        }
    }

    function approve(address usr) external _ward_ {
        divider.give(usr);
        multiplier.give(usr);
        uniadapt.give(usr);
        cladapt.give(usr);

        Diamond(bank).transferOwnership(usr);
    }

    function _configureBlock(Block b, bytes32 tag, address s1, bytes32 t1, address s2, bytes32 t2, uint C) internal {
        address[] memory sources;
        bytes32[] memory tags;

        if (C == RAY) {
            sources = new address[](2);
            tags    = new bytes32[](2);
        } else {
            sources = new address[](3);
            tags    = new bytes32[](3);
            sources[2] = address(this); tags[2] = bytes32(C);
            Feedbase(feedbase).push(bytes32(C), bytes32(C), type(uint).max);
        }

        sources[0] = s1; tags[0] = t1;
        sources[1] = s2; tags[1] = t2;

        b.setConfig(tag, Block.Config(sources, tags));
    }

    function read(bytes32 tag) external pure returns (bytes32, uint) {
        return (tag, type(uint).max);
    }
}
