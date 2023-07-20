/// SPDX-License-Identifier: AGPL-3.0

// Copyright (C) 2021-2023 halys

// The cannonball is the canonical deployment sequence
// implemented as one big contract. You can diff more
// efficient deployment sequences against the result of
// this one.

pragma solidity ^0.8.19;

import {Vat} from './vat.sol';
import {Vow} from './vow.sol';
import {Vox} from './vox.sol';
import {Feedbase} from "../lib/feedbase/src/Feedbase.sol";
import {Ploker} from "../lib/feedbase/src/Ploker.sol";
import {Gem} from "../lib/gemfab/src/gem.sol";
import {Ward} from "../lib/feedbase/src/mixin/ward.sol";
import {Divider} from "../lib/feedbase/src/combinators/Divider.sol";
import {UniswapV3Adapter, IUniWrapper} from "../lib/feedbase/src/adapters/UniswapV3Adapter.sol";
import {Medianizer} from "../lib/feedbase/src/Medianizer.sol";
import {ChainlinkAdapter} from "../lib/feedbase/src/adapters/ChainlinkAdapter.sol";
import {Math} from '../src/mixin/math.sol';
import {ERC20Hook} from './hook/ERC20hook.sol';
import {UniNFTHook} from './hook/nfpm/UniV3NFTHook.sol';
import {Bank} from './bank.sol';
import {File} from './file.sol';
import {Diamond, IDiamondCuttable} from '../lib/solidstate-solidity/contracts/proxy/diamond/Diamond.sol';

contract Ball is Math, Ward {
    bytes32 internal constant RICO_DAI_TAG  = "rico:dai";
    bytes32 internal constant DAI_RICO_TAG  = "dai:rico";
    bytes32 internal constant RICO_USD_TAG  = "rico:usd";
    bytes32 internal constant XAU_USD_TAG   = "xau:usd";
    bytes32 internal constant DAI_USD_TAG   = "dai:usd";
    bytes32 internal constant RICO_XAU_TAG  = "rico:xau";
    bytes32 internal constant RICO_REF_TAG  = "rico:ref";
    bytes32 internal constant RICO_RISK_TAG = "rico:risk";
    bytes32 internal constant RISK_RICO_TAG = "risk:rico";
    bytes32 internal constant UNI_NFT_ILK   = ":uninft";
    bytes32 internal constant HOW = bytes32(uint(1000000000000003652500000000));
    bytes32 internal constant CAP = bytes32(uint(1000000021970000000000000000));
    IDiamondCuttable.FacetCutAction internal constant ADD = IDiamondCuttable.FacetCutAction.ADD;

    Vat public vat;
    Vow public vow;
    Vox public vox;
    ERC20Hook public hook;
    UniNFTHook public nfthook;
    address public feedbase;

    Medianizer public mdn;
    UniswapV3Adapter public uniadapt;
    Divider public divider;
    ChainlinkAdapter public cladapt;
    address payable public bank;
    File public file;

    struct IlkParams {
        bytes32 ilk;
        address gem;
        address gemusdagg;
        uint256 chop;
        uint256 dust;
        uint256 fee;
        uint256 line;
        uint256 liqr;
        uint256 ttl;
        uint256 range;
    }

    struct UniParams {
        address nfpm;
        bytes32 ilk;
        uint256 fee;
        uint256 chop;
        uint256 room;
        address uniwrapper;
    }

    struct BallArgs {
        address payable bank; // diamond
        address feedbase;
        address rico;
        address risk;
        address ricodai;
        address ricorisk;
        address router;
        address uniwrapper;
        uint256 par;
        uint256 ceil;
        uint256 adaptrange;
        uint256 adaptttl;
        uint256 daiusdttl;
        uint256 xauusdttl;
        uint256 flappep;
        uint256 flappop;
        uint256 floppep;
        uint256 floppop;
        Vow.Ramp mintramp;
        address DAI;
        address DAI_USD_AGG;
        address XAU_USD_AGG;
    }

    address public rico;
    address public risk;
    address public dai;
    address public daiusdagg;

    Ploker public ploker;

    constructor(BallArgs memory args) {
        file = new File();
        vat  = new Vat();
        vow  = new Vow();
        hook = new ERC20Hook();
        ploker = new Ploker();

        mdn = new Medianizer(args.feedbase);
        uniadapt = new UniswapV3Adapter(Feedbase(args.feedbase), IUniWrapper(args.uniwrapper));
        cladapt = new ChainlinkAdapter(args.feedbase);
        divider = new Divider(args.feedbase);
        nfthook = new UniNFTHook();

        bank = args.bank;
        rico = args.rico;
        risk = args.risk;
        dai  = args.DAI;
        feedbase  = args.feedbase;
        daiusdagg = args.DAI_USD_AGG;

        // rico/usd, rico/ref
        cladapt.setConfig(
            XAU_USD_TAG, ChainlinkAdapter.Config(args.XAU_USD_AGG, args.xauusdttl, RAY)
        );
        cladapt.setConfig(
            DAI_USD_TAG, ChainlinkAdapter.Config(args.DAI_USD_AGG, args.daiusdttl, RAY)
        );
        cladapt.look(XAU_USD_TAG);
        (bytes32 ref,) = Feedbase(feedbase).pull(address(cladapt), XAU_USD_TAG);
        vox = new Vox(uint256(ref));

        // rico/dai, dai/rico (== 1 / (rico/dai))
        uniadapt.setConfig(
            RICO_DAI_TAG,
            UniswapV3Adapter.Config(args.ricodai, args.adaptrange, args.adaptttl, args.DAI < rico)
        );
        address[] memory sources = new address[](2);
        bytes32[] memory tags    = new bytes32[](2);
        Feedbase(feedbase).push(bytes32("ONE"), bytes32(RAY), type(uint).max);
        sources[0] = address(this);     tags[0] = bytes32("ONE");
        sources[1] = address(uniadapt); tags[1] = RICO_DAI_TAG;
        divider.setConfig(DAI_RICO_TAG, Divider.Config(sources, tags));

        sources[0] = address(cladapt); tags[0] = DAI_USD_TAG;
        sources[1] = address(divider); tags[1] = DAI_RICO_TAG;
        divider.setConfig(RICO_USD_TAG, Divider.Config(sources, tags));

        sources[0] = address(divider); tags[0] = RICO_USD_TAG;
        sources[1] = address(cladapt); tags[1] = XAU_USD_TAG;
        divider.setConfig(RICO_XAU_TAG, Divider.Config(sources, tags));

        Medianizer.Config memory mdnconf = Medianizer.Config(new address[](1), new bytes32[](1), 1);
        mdnconf.srcs[0] = address(divider); mdnconf.tags[0] = RICO_XAU_TAG;
        mdn.setConfig(RICO_REF_TAG, mdnconf);

        // need four plokers: rico/ref, rico/risk, risk/rico, collateral/rico
        Ploker.Config memory plokerconf = Ploker.Config(
            new address[](3), new bytes32[](3), new address[](1), new bytes32[](1)
        );
        plokerconf.adapters[0] = address(cladapt); plokerconf.adaptertags[0] = XAU_USD_TAG;
        plokerconf.adapters[1] = address(cladapt); plokerconf.adaptertags[1] = DAI_USD_TAG;
        plokerconf.adapters[2] = address(uniadapt); plokerconf.adaptertags[2] = RICO_DAI_TAG;
        plokerconf.combinators[0] = address(mdn); plokerconf.combinatortags[0] = RICO_REF_TAG;
        ploker.setConfig(RICO_REF_TAG, plokerconf);
        ploker.setConfig(RICO_XAU_TAG, plokerconf);

        //
        // rico/risk, risk/rico
        //
        uniadapt.setConfig(
            RICO_RISK_TAG,
            UniswapV3Adapter.Config(args.ricorisk, args.adaptrange, args.adaptttl, rico < risk)
        );
        sources[0] = address(this);     tags[0] = bytes32("ONE");
        sources[1] = address(uniadapt); tags[1] = RICO_RISK_TAG;
        divider.setConfig(RISK_RICO_TAG, Divider.Config(sources, tags));
        mdnconf.srcs[0] = address(divider); mdnconf.tags[0] = RISK_RICO_TAG;
        mdn.setConfig(RISK_RICO_TAG, mdnconf);
        mdnconf.srcs[0] = address(uniadapt); mdnconf.tags[0] = RICO_RISK_TAG;
        mdn.setConfig(RICO_RISK_TAG, mdnconf);

        plokerconf = Ploker.Config(
            new address[](1), new bytes32[](1), new address[](1), new bytes32[](1)
        );
        plokerconf.adapters[0] = address(uniadapt); plokerconf.adaptertags[0] = RICO_RISK_TAG;
        plokerconf.combinators[0] = address(mdn); plokerconf.combinatortags[0] = RISK_RICO_TAG;
        ploker.setConfig(RISK_RICO_TAG, plokerconf);
        plokerconf.combinators[0] = address(mdn); plokerconf.combinatortags[0] = RICO_RISK_TAG;
        ploker.setConfig(RICO_RISK_TAG, plokerconf);
    }

    function setup(BallArgs calldata args) _ward_ external payable {
        {
            IDiamondCuttable.FacetCut[] memory facetCuts = new IDiamondCuttable.FacetCut[](4);
            bytes4[] memory filesels = new bytes4[](6);
            bytes4[] memory vatsels  = new bytes4[](24);
            bytes4[] memory vowsels  = new bytes4[](7);
            bytes4[] memory voxsels  = new bytes4[](8);

            filesels[0] = File.file.selector;
            filesels[1] = File.link.selector;
            filesels[2] = File.fb.selector;
            filesels[3] = File.rico.selector;
            filesels[4] = File.ward.selector;
            filesels[5] = File.wards.selector;
            vatsels[0]  = Vat.filk.selector;
            vatsels[1]  = Vat.filh.selector;
            vatsels[2]  = Vat.filhi.selector;
            vatsels[3]  = Vat.filhi2.selector;
            vatsels[4]  = Vat.init.selector;
            vatsels[5]  = Vat.frob.selector;
            vatsels[6]  = Vat.bail.selector;
            vatsels[7]  = Vat.safe.selector;
            vatsels[8]  = Vat.heal.selector;
            vatsels[9]  = Vat.sin.selector;
            vatsels[10] = Vat.ilks.selector;
            vatsels[11] = Vat.urns.selector;
            vatsels[12] = Vat.rest.selector;
            vatsels[13] = Vat.debt.selector;
            vatsels[14] = Vat.ceil.selector;
            vatsels[15] = Vat.par.selector;
            vatsels[16] = Vat.drip.selector;
            vatsels[17] = Vat.MINT.selector;
            vatsels[18] = Vat.ink.selector;
            vatsels[19] = Vat.flash.selector;
            vatsels[20] = Vat.geth.selector;
            vatsels[21] = Vat.gethi.selector;
            vatsels[22] = Vat.gethi2.selector;
            vatsels[23] = Vat.hookcallext.selector;
            vowsels[0]  = Vow.keep.selector;
            vowsels[1]  = Vow.RISK.selector;
            vowsels[2]  = Vow.ramp.selector;
            vowsels[3]  = Vow.flapfeed.selector;
            vowsels[4]  = Vow.flopfeed.selector;
            vowsels[5]  = Vow.flapplot.selector;
            vowsels[6]  = Vow.flopplot.selector;
            voxsels[0]  = Vox.poke.selector;
            voxsels[1]  = Vox.way.selector;
            voxsels[2]  = Vox.how.selector;
            voxsels[3]  = Vox.cap.selector;
            voxsels[4]  = Vox.tip.selector;
            voxsels[5]  = Vox.tag.selector;
            voxsels[6]  = Vox.amp.selector;
            voxsels[7]  = Vox.tau.selector;

            facetCuts[0] = IDiamondCuttable.FacetCut(address(file), ADD, filesels);
            facetCuts[1] = IDiamondCuttable.FacetCut(address(vat),  ADD, vatsels);
            facetCuts[2] = IDiamondCuttable.FacetCut(address(vow),  ADD, vowsels);
            facetCuts[3] = IDiamondCuttable.FacetCut(address(vox),  ADD, voxsels);
            Diamond(bank).acceptOwnership();
            Diamond(bank).diamondCut(facetCuts, address(0), bytes(''));
        }
        File(bank).file('par', bytes32(args.par));

        File(bank).link('rico', rico);
        File(bank).link('risk', risk);

        File(bank).file('ceil', bytes32(args.ceil));

        File(bank).file('flappep', bytes32(args.flappep));
        File(bank).file('flappop', bytes32(args.flappop));
        File(bank).file('flaptag', RICO_RISK_TAG);
        File(bank).file('flapsrc', bytes32(bytes20(address(mdn))));
        File(bank).file('floppep', bytes32(args.floppep));
        File(bank).file('floppop', bytes32(args.floppop));
        File(bank).file('floptag', RISK_RICO_TAG);
        File(bank).file('flopsrc', bytes32(bytes20(address(mdn))));

        File(bank).file("vel", bytes32(args.mintramp.vel));
        File(bank).file("rel", bytes32(args.mintramp.vel));
        File(bank).file("bel", bytes32(args.mintramp.bel));
        File(bank).file("cel", bytes32(args.mintramp.cel));

        File(bank).link('fb',  feedbase);
        File(bank).link('tip', address(mdn));
        File(bank).file('tag', RICO_REF_TAG);
        File(bank).file('how', HOW);
        File(bank).file('cap', CAP);
        File(bank).file('tau', bytes32(block.timestamp));
        File(bank).file('way', bytes32(RAY));
    }

    function makeilk(IlkParams calldata ilkparams) _ward_ external {
        bytes32 ilk = ilkparams.ilk;
        bytes32 gemricotag = concat(ilk, ':rico');
        Vat(bank).init(ilk, address(hook));
        Vat(bank).filhi(ilk, 'gem', ilk, bytes32(bytes20(ilkparams.gem)));
        Vat(bank).filhi(ilk, 'fsrc', ilk, bytes32(bytes20(address(mdn))));
        Vat(bank).filhi(ilk, 'ftag', ilk, gemricotag);
        Vat(bank).filk(ilk, 'chop', bytes32(ilkparams.chop));
        Vat(bank).filk(ilk, 'dust', bytes32(ilkparams.dust));
        Vat(bank).filk(ilk, 'fee', bytes32( ilkparams.fee));  // 5%
        Vat(bank).filk(ilk, 'line', bytes32(ilkparams.line));
        Vat(bank).filk(ilk, 'liqr', bytes32(ilkparams.liqr));

        address[] memory sources = new address[](2);
        bytes32[] memory tags    = new bytes32[](2);
        // uni adapter returns a ray, and both ink and sqrtPriceX96 ignore decimals, so scale always a RAY
        bytes32 gemusdtag = concat(ilk, ':usd');

        Medianizer.Config memory mdnconf = Medianizer.Config(new address[](1), new bytes32[](1), 1);
        mdnconf.srcs[0] = address(divider); mdnconf.tags[0] = gemricotag;
        mdn.setConfig(gemricotag, mdnconf);

        if (ilkparams.gem == dai) {
            Ploker.Config memory plokerconf = Ploker.Config(
                new address[](1), new bytes32[](1), new address[](1), new bytes32[](1)
            );
            plokerconf.adapters[0] = address(uniadapt); plokerconf.adaptertags[0] = RICO_DAI_TAG;
            plokerconf.combinators[0] = address(mdn); plokerconf.combinatortags[0] = gemricotag;
            ploker.setConfig(gemricotag, plokerconf);
        } else {
            cladapt.setConfig(gemusdtag, ChainlinkAdapter.Config(ilkparams.gemusdagg, ilkparams.ttl, RAY));
            sources[0] = address(cladapt); tags[0] = gemusdtag;
            sources[1] = address(divider); tags[1] = RICO_USD_TAG;
            divider.setConfig(gemricotag, Divider.Config(sources, tags));

            Ploker.Config memory plokerconf = Ploker.Config(
                new address[](3), new bytes32[](3), new address[](1), new bytes32[](1)
            );
            plokerconf.adapters[0] = address(uniadapt); plokerconf.adaptertags[0] = RICO_DAI_TAG;
            plokerconf.adapters[1] = address(cladapt); plokerconf.adaptertags[1] = gemusdtag;
            plokerconf.adapters[2] = address(cladapt); plokerconf.adaptertags[2] = DAI_USD_TAG;
            plokerconf.combinators[0] = address(mdn); plokerconf.combinatortags[0] = gemricotag;
            ploker.setConfig(gemricotag, plokerconf);
        }
    }

    function makeuni(UniParams calldata ups) _ward_ external {
        if (Vat(bank).ilks(UNI_NFT_ILK).rack != 0) return;
        // initialize uni ilk
        Vat(bank).init(ups.ilk, address(nfthook));
        Vat(bank).filh(UNI_NFT_ILK, 'nfpm', bytes32(bytes20(address(ups.nfpm))));
        Vat(bank).filh(UNI_NFT_ILK, 'ROOM', bytes32(ups.room));
        Vat(bank).filh(UNI_NFT_ILK, 'wrap', bytes32(bytes20(address(ups.uniwrapper))));

        Vat(bank).filk(ups.ilk, 'fee', bytes32(ups.fee));
        Vat(bank).filk(ups.ilk, 'chop', bytes32(ups.chop));
    }

    function approve(address usr) _ward_ external {
        mdn.give(usr);
        divider.give(usr);
        uniadapt.give(usr);
        cladapt.give(usr);
        ploker.give(usr);

        Diamond(bank).transferOwnership(usr);
    }

}
