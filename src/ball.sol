/// SPDX-License-Identifier: AGPL-3.0

// The cannonball is the canonical deployment sequence
// implemented as one big contract. You can diff more
// efficient deployment sequences against the result of
// this one.

pragma solidity 0.8.19;

import {Vat} from './vat.sol';
import {Vow} from './vow.sol';
import {Vox} from './vox.sol';
import {Feedbase} from "../lib/feedbase/src/Feedbase.sol";
import {Ward} from "../lib/feedbase/src/mixin/ward.sol";
import {Divider} from "../lib/feedbase/src/combinators/Divider.sol";
import {UniswapV3Adapter, IUniWrapper} from "../lib/feedbase/src/adapters/UniswapV3Adapter.sol";
import {Medianizer} from "../lib/feedbase/src/Medianizer.sol";
import {ChainlinkAdapter} from "../lib/feedbase/src/adapters/ChainlinkAdapter.sol";
import {Math} from '../src/mixin/math.sol';
import {ERC20Hook} from './hook/ERC20hook.sol';
import {UniNFTHook} from './hook/nfpm/UniV3NFTHook.sol';
import {Ploker} from './test/Ploker.sol';

contract Ball is Math, Ward {
    bytes32 internal constant RICO_DAI_TAG = "rico:dai";
    bytes32 internal constant DAI_RICO_TAG = "dai:rico";
    bytes32 internal constant XAU_USD_TAG = "xau:usd";
    bytes32 internal constant DAI_USD_TAG = "dai:usd";
    bytes32 internal constant RICO_XAU_TAG = "rico:xau";
    bytes32 internal constant RICO_REF_TAG = "rico:ref";
    bytes32 internal constant RICO_RISK_TAG  = "rico:risk";
    bytes32 internal constant RISK_RICO_TAG  = "risk:rico";

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

    constructor(
        BallArgs memory args
    ) payable {
        rico = args.rico;
        risk = args.risk;
        dai = args.DAI;
        feedbase = args.feedbase;

        vat  = new Vat();
        vow  = new Vow();
        hook = new ERC20Hook(feedbase, address(vat), rico);
        mdn = new Medianizer(feedbase);
        uniadapt = new UniswapV3Adapter(Feedbase(feedbase), IUniWrapper(args.uniwrapper));
        cladapt = new ChainlinkAdapter(feedbase);
        divider = new Divider(feedbase, RAY);
        ploker = new Ploker();
        vat.prod(args.par);

        vow.link('flow', address(hook));
        vow.link('vat',  address(vat));
        vow.link('RICO', rico);
        vow.link('RISK', risk);

        vat.file('ceil',  args.ceil);
        vat.link('rico',  rico);
        vat.ward(address(vow), true);

        hook.ward(address(vat), true);  // grabhook, frobhook
        hook.ward(address(vow), true);  // flow
        hook.wire("flap", rico, address(mdn), RICO_RISK_TAG);
        hook.wire("flop", risk, address(mdn), RISK_RICO_TAG);

        vow.file("vel", args.mintramp.vel);
        vow.file("rel", args.mintramp.vel);
        vow.file("bel", args.mintramp.bel);
        vow.file("cel", args.mintramp.cel);
        vow.grant(rico);
        vow.grant(risk);

        // rico/dai, dai/rico (== 1 / (rico/dai))
        uniadapt.setConfig(
            RICO_DAI_TAG,
            UniswapV3Adapter.Config(args.ricodai, args.adaptrange, args.adaptttl, args.DAI < rico)
        );
        {
            address[] memory sources = new address[](2);
            bytes32[] memory tags    = new bytes32[](2);
            Feedbase(feedbase).push(bytes32("ONE"), bytes32(RAY), type(uint).max);
            sources[0] = address(this); tags[0] = bytes32("ONE");
            sources[1] = address(uniadapt); tags[1] = RICO_DAI_TAG;
            divider.setConfig(DAI_RICO_TAG, Divider.Config(sources, tags));
        }

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
            src3[0] = address(cladapt); tag3[0] = DAI_USD_TAG;
            src3[1] = address(divider); tag3[1] = DAI_RICO_TAG;
            src3[2] = address(cladapt); tag3[2] = XAU_USD_TAG;
            divider.setConfig(RICO_XAU_TAG, Divider.Config(src3, tag3));
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
        {
            address[] memory src2 = new address[](2);
            bytes32[] memory tag2 = new bytes32[](2);
            src2[0] = address(this); tag2[0] = bytes32("ONE");
            src2[1] = address(uniadapt); tag2[1] = RICO_RISK_TAG;
            divider.setConfig(RISK_RICO_TAG, Divider.Config(src2, tag2));
        }
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
        vox.link('fb',  feedbase);
        vox.link('vat', address(vat));
        vox.link('tip', address(mdn));
        vox.file('tag', RICO_REF_TAG);
        vat.ward(address(vox), true);
    }

    function makeilk(IlkParams calldata ilkparams) _ward_ public {
        bytes32 ilk = ilkparams.ilk;
        bytes32 ilkrico = concat(ilk, ':rico');
        vat.init(ilk, address(hook));
        Medianizer.Config memory mdnconf =
            Medianizer.Config(new address[](1), new bytes32[](1), 0);
        mdnconf.srcs[0] = address(divider);
        mdnconf.tags[0] = ilkrico;
        mdn.setConfig(ilkrico, mdnconf);
        hook.wire(ilk, ilkparams.gem, address(mdn), ilkrico);
        vat.filk(ilk, 'chop', ilkparams.chop);
        vat.filk(ilk, 'dust', ilkparams.dust);
        vat.filk(ilk, 'fee',  ilkparams.fee);  // 5%
        vat.filk(ilk, 'line', ilkparams.line);
        vat.filk(ilk, 'liqr', ilkparams.liqr);
        hook.list(ilkparams.gem, true);

        address[] memory ss = new address[](2);
        bytes32[] memory ts = new bytes32[](2);
        if (ilkparams.gem == dai) {
            ss[0] = address(this); ts[0] = bytes32("ONE");

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
            ss[0] = address(uniadapt); ts[0] = tag;

            Ploker.Config memory plokerconf = Ploker.Config(
                new address[](2), new bytes32[](2), new address[](1), new bytes32[](1)
            );
            plokerconf.adapters[0] = address(uniadapt); plokerconf.adaptertags[0] = tag;
            plokerconf.adapters[1] = address(uniadapt); plokerconf.adaptertags[1] = RICO_DAI_TAG;
            plokerconf.combinators[0] = address(mdn); plokerconf.combinatortags[0] = ilkrico;
            ploker.setConfig(ilkrico, plokerconf);
        }

        ss[1] = address(uniadapt); ts[1] = RICO_DAI_TAG;
        divider.setConfig(ilkrico, Divider.Config(ss, ts));
    }

    function makeuni(UniParams calldata ups) _ward_ public {
        if (address(nfthook) != address(0)) return;
        // initialize uni ilk
        nfthook = new UniNFTHook(feedbase, rico, ups.nfpm, ups.room, ups.uniwrapper);
        vat.init(ups.ilk, address(nfthook));
        vat.filk(ups.ilk, 'fee', ups.fee);
        vat.filk(ups.ilk, 'chop', ups.chop);

        nfthook.ward(address(vat), true);
    }

    function approve(address usr) _ward_ public {
        mdn.give(usr);
        divider.give(usr);
        uniadapt.give(usr);
        cladapt.give(usr);
        ploker.give(usr);

        hook.give(usr);
        nfthook.give(usr);

        vow.give(usr);
        vat.give(usr);
        vox.give(usr);
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
