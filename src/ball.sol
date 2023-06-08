/// SPDX-License-Identifier: AGPL-3.0

// The cannonball is the canonical deployment sequence
// implemented as one big contract. You can diff more
// efficient deployment sequences against the result of
// this one.

pragma solidity 0.8.20;

import {Vat} from './vat.sol';
import {Vow} from './vow.sol';
import {Vox} from './vox.sol';
import {Feedbase} from "../lib/feedbase/src/Feedbase.sol";
import {Gem} from "../lib/gemfab/src/gem.sol";
import {Ward} from "../lib/feedbase/src/mixin/ward.sol";
import {Divider} from "../lib/feedbase/src/combinators/Divider.sol";
import {UniswapV3Adapter, IUniWrapper} from "../lib/feedbase/src/adapters/UniswapV3Adapter.sol";
import {Medianizer} from "../lib/feedbase/src/Medianizer.sol";
import {ChainlinkAdapter} from "../lib/feedbase/src/adapters/ChainlinkAdapter.sol";
import {Math} from '../src/mixin/math.sol';
import {ERC20Hook} from './hook/ERC20hook.sol';
import {UniNFTHook} from './hook/nfpm/UniV3NFTHook.sol';
import {Ploker} from './test/Ploker.sol';
import {Bank} from './bank.sol';
import {File} from './file.sol';
import {Diamond, IDiamondCuttable} from '../lib/solidstate-solidity/contracts/proxy/diamond/Diamond.sol';

contract Ball is Math, Ward {
    bytes32 internal constant RICO_DAI_TAG = "rico:dai";
    bytes32 internal constant DAI_RICO_TAG = "dai:rico";
    bytes32 internal constant XAU_USD_TAG = "xau:usd";
    bytes32 internal constant DAI_USD_TAG = "dai:usd";
    bytes32 internal constant RICO_XAU_TAG = "rico:xau";
    bytes32 internal constant RICO_REF_TAG = "rico:ref";
    bytes32 internal constant RICO_RISK_TAG  = "rico:risk";
    bytes32 internal constant RISK_RICO_TAG  = "risk:rico";
    bytes32 internal constant UNI_NFT_ILK = ":uninft";

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
        address pool;
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
        Vow.Ramp mintramp;
        address DAI;
        address DAI_USD_AGG;
        address XAU_USD_AGG;
    }

    address public rico;
    address public risk;
    address public dai;

    Ploker public ploker;

    function singleCut(address facet, bytes4 sel) internal {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = sel;
        IDiamondCuttable.FacetCut[] memory cuts = new IDiamondCuttable.FacetCut[](1);
        cuts[0] = IDiamondCuttable.FacetCut(
            facet, IDiamondCuttable.FacetCutAction.ADD, sels
        );

        Diamond(bank).diamondCut(cuts, address(0), bytes(''));
    }

    constructor(BallArgs memory args) {
        file = new File();
        vat  = new Vat();
        vow  = new Vow();
        hook = new ERC20Hook();
        ploker = new Ploker();

        mdn = new Medianizer(args.feedbase);
        uniadapt = new UniswapV3Adapter(Feedbase(args.feedbase), IUniWrapper(args.uniwrapper));
        cladapt = new ChainlinkAdapter(args.feedbase);
        divider = new Divider(args.feedbase, RAY);
    }

    function setup(BallArgs memory args) _ward_ public payable {
        bank = args.bank;
        rico = args.rico;
        risk = args.risk;
        dai = args.DAI;
        feedbase = args.feedbase;

        Diamond(bank).acceptOwnership();
        singleCut(address(file), File.file.selector);
        singleCut(address(file), File.link.selector);
        singleCut(address(file), File.fb.selector);
        singleCut(address(file), File.rico.selector);
        singleCut(address(vat), Vat.filk.selector);
        singleCut(address(vat), Vat.filh.selector);
        singleCut(address(vat), Vat.filhi.selector);
        singleCut(address(vat), Vat.filhi2.selector);
        singleCut(address(vat), Vat.init.selector);
        singleCut(address(vat), Vat.frob.selector);
        singleCut(address(vat), Vat.grab.selector);
        singleCut(address(vat), Vat.safe.selector);
        singleCut(address(vat), Vat.heal.selector);
        singleCut(address(vat), Vat.sin.selector);
        singleCut(address(vat), Vat.ilks.selector);
        singleCut(address(vat), Vat.urns.selector);
        singleCut(address(vat), Vat.rest.selector);
        singleCut(address(vat), Vat.debt.selector);
        singleCut(address(vat), Vat.ceil.selector);
        singleCut(address(vat), Vat.par.selector);
        singleCut(address(vat), Vat.drip.selector);
        singleCut(address(vat), Vat.DASH.selector);
        singleCut(address(vat), Vat.MINT.selector);
        singleCut(address(vat), Vat.ink.selector);
        singleCut(address(vat), Vat.flash.selector);

        singleCut(address(vow), Vow.keep.selector);
        singleCut(address(vow), Vow.bail.selector);
        singleCut(address(vow), Vow.RISK.selector);
        singleCut(address(vow), Vow.ramp.selector);
        singleCut(address(vow), Vow.flapfeed.selector);
        singleCut(address(vow), Vow.flopfeed.selector);

        singleCut(address(hook), ERC20Hook.erc20flash.selector);
        File(bank).file('par', bytes32(args.par));

        File(bank).link('rico', rico);
        File(bank).link('risk', risk);

        File(bank).file('ceil', bytes32(args.ceil));

        File(bank).file('flaptag', RICO_RISK_TAG);
        File(bank).file('flapsrc', bytes32(bytes20(address(mdn))));
        File(bank).file('floptag', RISK_RICO_TAG);
        File(bank).file('flopsrc', bytes32(bytes20(address(mdn))));

        File(bank).file("vel", bytes32(args.mintramp.vel));
        File(bank).file("rel", bytes32(args.mintramp.vel));
        File(bank).file("bel", bytes32(args.mintramp.bel));
        File(bank).file("cel", bytes32(args.mintramp.cel));

        // rico/dai, dai/rico (== 1 / (rico/dai))
        uniadapt.setConfig(
            RICO_DAI_TAG,
            UniswapV3Adapter.Config(args.ricodai, args.adaptrange, args.adaptttl, args.DAI < rico)
        );
        address[] memory sources = new address[](2);
        bytes32[] memory tags    = new bytes32[](2);
        uint256[] memory scales  = new uint256[](2);
        scales[0] = scales[1] = RAY;
        Feedbase(feedbase).push(bytes32("ONE"), bytes32(RAY), type(uint).max);
        sources[0] = address(this);     tags[0] = bytes32("ONE");
        sources[1] = address(uniadapt); tags[1] = RICO_DAI_TAG;
        divider.setConfig(DAI_RICO_TAG, Divider.Config(sources, tags, scales));

        //
        // rico/ref
        //
        cladapt.setConfig(
            XAU_USD_TAG, ChainlinkAdapter.Config(args.XAU_USD_AGG, args.xauusdttl, RAY)
        );
        cladapt.setConfig(
            DAI_USD_TAG, ChainlinkAdapter.Config(args.DAI_USD_AGG, args.daiusdttl, RAY)
        );
        {
            address[] memory src3 = new address[](3);
            bytes32[] memory tag3 = new bytes32[](3);
            uint256[] memory scl3 = new uint256[](3);
            src3[0] = address(cladapt); tag3[0] = DAI_USD_TAG;  scl3[0] = RAY;
            src3[1] = address(divider); tag3[1] = DAI_RICO_TAG; scl3[1] = RAY;
            src3[2] = address(cladapt); tag3[2] = XAU_USD_TAG;  scl3[2] = RAY;
            divider.setConfig(RICO_XAU_TAG, Divider.Config(src3, tag3, scl3));
        }
        Medianizer.Config memory mdnconf =
            Medianizer.Config(new address[](1), new bytes32[](1), 0);
        mdnconf.srcs[0] = address(divider);
        mdnconf.tags[0] = RICO_XAU_TAG;
        mdnconf.quorum  = 1;
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
        divider.setConfig(RISK_RICO_TAG, Divider.Config(sources, tags, scales));
        mdnconf.srcs[0] = address(uniadapt);
        mdnconf.tags[0] = RICO_RISK_TAG;
        mdn.setConfig(RICO_RISK_TAG, mdnconf);
        mdnconf.srcs[0] = address(divider);
        mdnconf.tags[0] = RISK_RICO_TAG;
        mdn.setConfig(RISK_RICO_TAG, mdnconf);
        plokerconf = Ploker.Config(
            new address[](1), new bytes32[](1), new address[](0), new bytes32[](0)
        );
        plokerconf.adapters[0] = address(uniadapt); plokerconf.adaptertags[0] = RICO_RISK_TAG;
        ploker.setConfig(RICO_RISK_TAG, plokerconf);
        ploker.setConfig(RISK_RICO_TAG, plokerconf);


        cladapt.look(XAU_USD_TAG);
        (bytes32 ref,) = Feedbase(feedbase).pull(address(cladapt), XAU_USD_TAG);
        vox = new Vox(uint256(ref));
        singleCut(address(vox), Vox.poke.selector);
        singleCut(address(vox), Vox.way.selector);
        singleCut(address(vox), Vox.how.selector);
        singleCut(address(vox), Vox.cap.selector);
        singleCut(address(vox), Vox.tip.selector);
        singleCut(address(vox), Vox.tag.selector);
        singleCut(address(vox), Vox.amp.selector);
        File(bank).link('fb',  feedbase);
        File(bank).link('tip', address(mdn));
        File(bank).file('tag', RICO_REF_TAG);
        File(bank).file('how', bytes32(uint(1000000115170000000000000000)));
        File(bank).file('cap', bytes32(uint(1000000022000000000000000000)));
        File(bank).file('tau', bytes32(block.timestamp));
        File(bank).file('way', bytes32(RAY));
    }

    function makeilk(IlkParams calldata ilkparams) _ward_ public {
        bytes32 ilk = ilkparams.ilk;
        bytes32 ilkrico = concat(ilk, ':rico');
        Vat(bank).init(ilk, address(hook));
        Medianizer.Config memory mdnconf =
            Medianizer.Config(new address[](1), new bytes32[](1), 0);
        mdnconf.srcs[0] = address(divider);
        mdnconf.tags[0] = ilkrico;
        mdn.setConfig(ilkrico, mdnconf);
        Vat(bank).filhi(ilk, 'gem', ilk, bytes32(bytes20(ilkparams.gem)));
        Vat(bank).filhi(ilk, 'fsrc', ilk, bytes32(bytes20(address(mdn))));
        Vat(bank).filhi(ilk, 'ftag', ilk, ilkrico);
        Vat(bank).filhi(ilk, 'pass', ilk, bytes32(uint(1)));
        Vat(bank).filk(ilk, 'chop', ilkparams.chop);
        Vat(bank).filk(ilk, 'dust', ilkparams.dust);
        Vat(bank).filk(ilk, 'fee',  ilkparams.fee);  // 5%
        Vat(bank).filk(ilk, 'line', ilkparams.line);
        Vat(bank).filk(ilk, 'liqr', ilkparams.liqr);

        address[] memory sources = new address[](2);
        bytes32[] memory tags    = new bytes32[](2);
        uint256[] memory scales  = new uint256[](2);
        // uni adapter returns a ray, and both ink and sqrtPriceX96 ignore decimals, so scale always a RAY
        scales[0] = scales[1] = RAY;
        if (ilkparams.gem == dai) {
            sources[0] = address(this); tags[0] = bytes32("ONE");

            // not using second uni adapter here, it's just dai/dai
            Ploker.Config memory plokerconf = Ploker.Config(
                new address[](1), new bytes32[](1), new address[](1), new bytes32[](1)
            );
            plokerconf.adapters[0] = address(uniadapt); plokerconf.adaptertags[0] = RICO_DAI_TAG;
            plokerconf.combinators[0] = address(mdn); plokerconf.combinatortags[0] = ilkrico;
            ploker.setConfig(ilkrico, plokerconf);
        } else {
            bytes32 tag = concat(ilk, ':dai');
            uniadapt.setConfig(
                tag,
                UniswapV3Adapter.Config(
                    ilkparams.pool, ilkparams.range, ilkparams.ttl, ilkparams.gem > dai
                )
            );
            sources[0] = address(uniadapt); tags[0] = tag;

            Ploker.Config memory plokerconf = Ploker.Config(
                new address[](2), new bytes32[](2), new address[](1), new bytes32[](1)
            );
            plokerconf.adapters[0] = address(uniadapt); plokerconf.adaptertags[0] = tag;
            plokerconf.adapters[1] = address(uniadapt); plokerconf.adaptertags[1] = RICO_DAI_TAG;
            plokerconf.combinators[0] = address(mdn); plokerconf.combinatortags[0] = ilkrico;
            ploker.setConfig(ilkrico, plokerconf);
        }

        sources[1] = address(uniadapt); tags[1] = RICO_DAI_TAG;
        divider.setConfig(ilkrico, Divider.Config(sources, tags, scales));
    }

    function makeuni(UniParams calldata ups) _ward_ public {
        if (address(nfthook) != address(0)) return;
        nfthook = new UniNFTHook();
        // initialize uni ilk
        Vat(bank).init(ups.ilk, address(nfthook));
        Vat(bank).filh(UNI_NFT_ILK, 'nfpm', bytes32(bytes20(address(ups.nfpm))));
        Vat(bank).filh(UNI_NFT_ILK, 'ROOM', bytes32(ups.room));
        Vat(bank).filh(UNI_NFT_ILK, 'wrap', bytes32(bytes20(address(ups.uniwrapper))));

        Vat(bank).filk(ups.ilk, 'fee', ups.fee);
        Vat(bank).filk(ups.ilk, 'chop', ups.chop);
    }

    function approve(address usr) _ward_ public {
        mdn.give(usr);
        divider.give(usr);
        uniadapt.give(usr);
        cladapt.give(usr);
        ploker.give(usr);

        Diamond(bank).transferOwnership(usr);
    }

    function concat(bytes32 a, bytes32 b) internal pure returns (bytes32 res) {
        uint i;
        while (true) {
            if (a[i] == 0) break;
            unchecked{ i++; }
        }
        res = a | (b >> (i << 3));
    }
}
