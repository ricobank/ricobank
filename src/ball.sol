/// SPDX-License-Identifier: AGPL-3.0

// Copyright (C) 2021-2023 halys

// The cannonball is the canonical deployment sequence
// implemented as one big contract. You can diff more
// efficient deployment sequences against the result of
// this one.

pragma solidity ^0.8.19;

import {Diamond, IDiamondCuttable} from '../lib/solidstate-solidity/contracts/proxy/diamond/Diamond.sol';
import {Block} from "../lib/feedbase/src/mixin/Block.sol";
import {ChainlinkAdapter} from "../lib/feedbase/src/adapters/ChainlinkAdapter.sol";
import {Divider} from "../lib/feedbase/src/combinators/Divider.sol";
import {Feedbase} from "../lib/feedbase/src/Feedbase.sol";
import {Medianizer} from "../lib/feedbase/src/Medianizer.sol";
import {Multiplier} from "../lib/feedbase/src/combinators/Multiplier.sol";
import {Ploker} from "../lib/feedbase/src/Ploker.sol";
import {UniswapV3Adapter, IUniWrapper} from "../lib/feedbase/src/adapters/UniswapV3Adapter.sol";
import {Ward} from "../lib/feedbase/src/mixin/ward.sol";
import {Gem} from "../lib/gemfab/src/gem.sol";

import {Vat} from './vat.sol';
import {Vow} from './vow.sol';
import {Vox} from './vox.sol';
import {Bank} from './bank.sol';
import {File} from './file.sol';
import {Math} from './mixin/math.sol';
import {ERC20Hook} from './hook/ERC20hook.sol';
import {UniNFTHook} from './hook/nfpm/UniV3NFTHook.sol';

contract Ball is Math, Ward {
    bytes32 internal constant RICO_DAI_TAG  = "rico:dai";
    bytes32 internal constant RICO_USD_TAG  = "rico:usd";
    bytes32 internal constant XAU_USD_TAG   = "xau:usd";
    bytes32 internal constant DAI_USD_TAG   = "dai:usd";
    bytes32 internal constant RICO_REF_TAG  = "rico:ref";
    bytes32 internal constant RICO_RISK_TAG = "rico:risk";
    bytes32 internal constant RISK_RICO_TAG = "risk:rico";
    bytes32 internal constant WETH_USD_TAG  = "weth:usd";
    bytes32 internal constant UNI_NFT_ILK   = ":uninft";
    bytes32 internal constant HOW = bytes32(uint(1000000000000003652500000000));
    bytes32 internal constant CAP = bytes32(uint(1000000021970000000000000000));
    uint256 internal constant MIN_P_SIZE    = 2;
    uint256 internal constant MAX_P_SIZE    = 3;
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
    Multiplier public multiplier;
    ChainlinkAdapter public cladapt;
    address payable public bank;
    File public file;

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
    Ploker  public ploker;

    constructor(BallArgs memory args) {
        vat  = new Vat();
        vow  = new Vow();
        vox  = new Vox();
        file = new File();
        hook = new ERC20Hook();
        nfthook = new UniNFTHook();
        ploker = new Ploker();

        mdn = new Medianizer(args.feedbase);
        uniadapt = new UniswapV3Adapter(Feedbase(args.feedbase), IUniWrapper(args.uniwrapper));
        cladapt = new ChainlinkAdapter(args.feedbase);
        divider = new Divider(args.feedbase);
        multiplier = new Multiplier(args.feedbase);

        bank = args.bank;
        rico = args.rico;
        risk = args.risk;
        feedbase = args.feedbase;

        // rico/usd, rico/ref
        cladapt.setConfig(XAU_USD_TAG, ChainlinkAdapter.Config(args.XAU_USD_AGG, args.xauusdttl, RAY));
        cladapt.setConfig(DAI_USD_TAG, ChainlinkAdapter.Config(args.DAI_USD_AGG, args.daiusdttl, RAY));
        // rico/dai, dai/rico (== 1 / (rico/dai))
        uniadapt.setConfig(
            RICO_DAI_TAG,
            UniswapV3Adapter.Config(args.ricodai, args.adaptrange, args.adaptttl, args.DAI < args.rico)
        );
        Feedbase(feedbase).push(bytes32("ONE"), bytes32(RAY), type(uint).max);

        _configureBlock(multiplier, RICO_USD_TAG,
                       address(cladapt),  DAI_USD_TAG,
                       address(uniadapt), RICO_DAI_TAG);
        _configureBlock(divider, RICO_REF_TAG,
                       address(multiplier), RICO_USD_TAG,
                       address(cladapt),    XAU_USD_TAG);

        Medianizer.Config memory mdnconf = Medianizer.Config(new address[](1), new bytes32[](1), 1);
        mdnconf.srcs[0] = address(divider); mdnconf.tags[0] = RICO_REF_TAG;
        mdn.setConfig(RICO_REF_TAG, mdnconf);

        // need four plokers: rico/ref, rico/risk, risk/rico, collateral/ref
        Ploker.Config memory plokerconf = Ploker.Config(
            new address[](3), new bytes32[](3), new address[](1), new bytes32[](1)
        );
        plokerconf.adapters[0] = address(cladapt); plokerconf.adaptertags[0] = XAU_USD_TAG;
        plokerconf.adapters[1] = address(cladapt); plokerconf.adaptertags[1] = DAI_USD_TAG;
        plokerconf.adapters[2] = address(uniadapt); plokerconf.adaptertags[2] = RICO_DAI_TAG;
        plokerconf.combinators[0] = address(mdn); plokerconf.combinatortags[0] = RICO_REF_TAG;
        ploker.setConfig(RICO_REF_TAG, plokerconf);

        //
        // rico/risk, risk/rico
        //
        uniadapt.setConfig(
            RICO_RISK_TAG,
            UniswapV3Adapter.Config(args.ricorisk, args.adaptrange, args.adaptttl, args.rico < args.risk)
        );
        _configureBlock(divider, RISK_RICO_TAG,
                       address(this),     bytes32("ONE"),
                       address(uniadapt), RICO_RISK_TAG);
        mdnconf.srcs[0] = address(divider); mdnconf.tags[0] = RISK_RICO_TAG;
        mdn.setConfig(RISK_RICO_TAG, mdnconf);
        mdnconf.srcs[0] = address(uniadapt); mdnconf.tags[0] = RICO_RISK_TAG;
        mdn.setConfig(RICO_RISK_TAG, mdnconf);

        plokerconf = Ploker.Config(new address[](1), new bytes32[](1), new address[](1), new bytes32[](1));
        plokerconf.adapters[0] = address(uniadapt); plokerconf.adaptertags[0] = RICO_RISK_TAG;
        plokerconf.combinators[0] = address(mdn); plokerconf.combinatortags[0] = RISK_RICO_TAG;
        ploker.setConfig(RISK_RICO_TAG, plokerconf);
        plokerconf.combinators[0] = address(mdn); plokerconf.combinatortags[0] = RICO_RISK_TAG;
        ploker.setConfig(RICO_RISK_TAG, plokerconf);
    }

    function setup(BallArgs calldata args) _ward_ external payable {
        IDiamondCuttable.FacetCut[] memory facetCuts = new IDiamondCuttable.FacetCut[](4);
        bytes4[] memory filesels = new bytes4[](4);
        bytes4[] memory vatsels  = new bytes4[](25);
        bytes4[] memory vowsels  = new bytes4[](7);
        bytes4[] memory voxsels  = new bytes4[](7);
        File fbank = File(bank);

        filesels[0] = File.file.selector;
        filesels[1] = File.link.selector;
        filesels[2] = File.fb.selector;
        filesels[3] = File.rico.selector;
        vatsels[0]  = Vat.filk.selector;
        vatsels[1]  = Vat.filh.selector;
        vatsels[2]  = Vat.filhi.selector;
        vatsels[3]  = Vat.filhi2.selector;
        vatsels[4]  = Vat.init.selector;
        vatsels[5]  = Vat.frob.selector;
        vatsels[6]  = Vat.bail.selector;
        vatsels[7]  = Vat.safe.selector;
        vatsels[8]  = Vat.heal.selector;
        vatsels[9]  = Vat.joy.selector;
        vatsels[10] = Vat.sin.selector;
        vatsels[11] = Vat.ilks.selector;
        vatsels[12] = Vat.urns.selector;
        vatsels[13] = Vat.rest.selector;
        vatsels[14] = Vat.debt.selector;
        vatsels[15] = Vat.ceil.selector;
        vatsels[16] = Vat.par.selector;
        vatsels[17] = Vat.drip.selector;
        vatsels[18] = Vat.MINT.selector;
        vatsels[19] = Vat.ink.selector;
        vatsels[20] = Vat.flash.selector;
        vatsels[21] = Vat.geth.selector;
        vatsels[22] = Vat.gethi.selector;
        vatsels[23] = Vat.gethi2.selector;
        vatsels[24] = Vat.hookcallext.selector;
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
        voxsels[6]  = Vox.tau.selector;

        facetCuts[0] = IDiamondCuttable.FacetCut(address(file), ADD, filesels);
        facetCuts[1] = IDiamondCuttable.FacetCut(address(vat),  ADD, vatsels);
        facetCuts[2] = IDiamondCuttable.FacetCut(address(vow),  ADD, vowsels);
        facetCuts[3] = IDiamondCuttable.FacetCut(address(vox),  ADD, voxsels);
        Diamond(payable(address(fbank))).acceptOwnership();
        Diamond(payable(address(fbank))).diamondCut(facetCuts, address(0), bytes(''));

        fbank.link('rico', rico);
        fbank.link('risk', risk);
        fbank.link('fb',  feedbase);
        fbank.link('tip', address(mdn));

        fbank.file('par',  bytes32(args.par));
        fbank.file('ceil', bytes32(args.ceil));

        fbank.file('flappep', bytes32(args.flappep));
        fbank.file('flappop', bytes32(args.flappop));
        fbank.file('flaptag', RICO_RISK_TAG);
        fbank.file('flapsrc', bytes32(bytes20(address(mdn))));
        fbank.file('floppep', bytes32(args.floppep));
        fbank.file('floppop', bytes32(args.floppop));
        fbank.file('floptag', RISK_RICO_TAG);
        fbank.file('flopsrc', bytes32(bytes20(address(mdn))));
        fbank.file("vel", bytes32(args.mintramp.vel));
        fbank.file("rel", bytes32(args.mintramp.vel));
        fbank.file("bel", bytes32(args.mintramp.bel));
        fbank.file("cel", bytes32(args.mintramp.cel));

        fbank.file('tag', RICO_REF_TAG);
        fbank.file('how', HOW);
        fbank.file('cap', CAP);
        fbank.file('tau', bytes32(block.timestamp));
        fbank.file('way', bytes32(RAY));
    }

    function makeilk(IlkParams calldata ilkparams) _ward_ external {
        bytes32 ilk = ilkparams.ilk;
        bytes32 gemreftag = concat(ilk, ':ref');
        Vat(bank).init(ilk, address(hook));
        Vat(bank).filk(ilk, 'chop', bytes32(ilkparams.chop));
        Vat(bank).filk(ilk, 'dust', bytes32(ilkparams.dust));
        Vat(bank).filk(ilk, 'fee',  bytes32(ilkparams.fee));
        Vat(bank).filk(ilk, 'line', bytes32(ilkparams.line));
        Vat(bank).filk(ilk, 'liqr', bytes32(ilkparams.liqr));
        Vat(bank).filhi(ilk, 'gem',  ilk, bytes32(bytes20(ilkparams.gem)));
        Vat(bank).filhi(ilk, 'fsrc', ilk, bytes32(bytes20(address(mdn))));
        Vat(bank).filhi(ilk, 'ftag', ilk, gemreftag);
        {
            Medianizer.Config memory mdnconf = Medianizer.Config(new address[](1), new bytes32[](1), 1);
            mdnconf.srcs[0] = address(divider); mdnconf.tags[0] = gemreftag;
            mdn.setConfig(gemreftag, mdnconf);
        }
        Ploker.Config memory pconf;
        bytes32 gemusdtag = concat(ilk, ':usd');
        bytes32 gemclatag;
        address gemusdsrc;
        uint256 plokesize = (ilkparams.gemethagg == address(0)) ? MIN_P_SIZE : MAX_P_SIZE;
        pconf = Ploker.Config(new address[](plokesize), new bytes32[](plokesize), new address[](1), new bytes32[](1));
        if (ilkparams.gemethagg == address(0)) {
            // ilk has feed sequence of gem/usd / rico/usd
            cladapt.setConfig(gemusdtag, ChainlinkAdapter.Config(ilkparams.gemusdagg, ilkparams.ttl, RAY));
            gemusdsrc = address(cladapt);
            gemclatag = gemusdtag;
        } else {
            // ilk has feed sequence of gem/eth * eth/usd / rico/usd
            bytes32 gemethtag = concat(ilk, ':eth');
            cladapt.setConfig(gemethtag, ChainlinkAdapter.Config(ilkparams.gemethagg, ilkparams.ttl, RAY));
            // add a multiplier config which reads gem/usd. Relies on weth ilk existing for weth:usd cladapter
            _configureBlock(multiplier, gemusdtag,
                            address(cladapt), gemethtag,
                            address(cladapt), WETH_USD_TAG);
            gemusdsrc = address(multiplier);
            gemclatag = gemethtag;
            pconf.adapters[MIN_P_SIZE] = address(cladapt); pconf.adaptertags[MIN_P_SIZE] = WETH_USD_TAG;
        }
        _configureBlock(divider, gemreftag,
                        address(gemusdsrc), gemusdtag,
                        address(cladapt),   XAU_USD_TAG);
        pconf.adapters[0] = address(cladapt);  pconf.adaptertags[0] = XAU_USD_TAG;
        pconf.adapters[1] = address(cladapt);  pconf.adaptertags[1] = gemclatag;
        pconf.combinators[0] = address(mdn); pconf.combinatortags[0] = gemreftag;
        ploker.setConfig(gemreftag, pconf);
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
        multiplier.give(usr);
        uniadapt.give(usr);
        cladapt.give(usr);
        ploker.give(usr);

        Diamond(bank).transferOwnership(usr);
    }

    function _configureBlock(Block b, bytes32 tag, address s1, bytes32 t1, address s2, bytes32 t2) internal {
        address[] memory sources = new address[](2);
        bytes32[] memory tags    = new bytes32[](2);
        sources[0] = s1; tags[0] = t1;
        sources[1] = s2; tags[1] = t2;
        b.setConfig(tag, Block.Config(sources, tags));
    }
}
