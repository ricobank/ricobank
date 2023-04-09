/// SPDX-License-Identifier: AGPL-3.0

// The cannonball is the canonical deployment sequence
// implemented as one big contract. You can diff more
// efficient deployment sequences against the result of
// this one.

pragma solidity 0.8.19;

import {Vat} from './vat.sol';
import {Vow} from './vow.sol';
import {Vox} from './vox.sol';
import {DutchFlower} from './flow.sol';
import {Feedbase} from "../lib/feedbase/src/Feedbase.sol";
import {Divider} from "../lib/feedbase/src/combinators/Divider.sol";
import {UniswapV3Adapter} from "../lib/feedbase/src/adapters/UniswapV3Adapter.sol";
import {Medianizer} from "../lib/feedbase/src/Medianizer.sol";
import {TWAP} from "../lib/feedbase/src/combinators/TWAP.sol";
import {ChainlinkAdapter} from "../lib/feedbase/src/adapters/ChainlinkAdapter.sol";
import {Math} from '../src/mixin/math.sol';
import {ERC20Hook} from './hook/ERC20hook.sol';

contract Ball is Math {
    bytes32 internal constant RICO_DAI_TAG = "ricodai";
    bytes32 internal constant DAI_RICO_TAG = "dairico";
    bytes32 internal constant XAU_USD_TAG = "xauusd";
    bytes32 internal constant DAI_USD_TAG = "daiusd";
    bytes32 internal constant RICO_XAU_TAG = "ricoxau";
    bytes32 internal constant RICO_REF_TAG = "ricoref";
    bytes32 internal constant RICO_RISK_TAG  = "ricorisk";
    bytes32 internal constant RISK_RICO_TAG  = "riskrico";

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    DutchFlower public flow;
    Vat public vat;
    Vow public vow;
    Vox public vox;
    ERC20Hook public hook;

    Medianizer public mdn;
    UniswapV3Adapter public adapt;
    Divider public divider;
    ChainlinkAdapter public cladapt;
    TWAP public twap;
   
    address constant DAI_USD_AGG = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address constant XAU_USD_AGG = 0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6;
    struct IlkParams {
        bytes32 ilk;
        address gem;
        address pool;
        uint    chop;
        uint    dust;
        uint    fee;
        uint    line;
        uint    liqr;
        DutchFlower.Ramp ramp;
        uint    ttl;
        uint    range;
    }

    struct BallArgs {
        address feedbase;
        address rico;
        address risk;
        address ricodai;
        address ricorisk;
        address router;
        address roll;
        uint    par;
        uint    ceil;
        uint    adaptrange;
        uint    adaptttl;
        uint    daiusdttl;
        uint    xauusdttl;
        uint    twaprange;
        uint    twapttl;
        DutchFlower.Ramp ricoramp;
        DutchFlower.Ramp riskramp;
        Vow.Ramp         mintramp;
    }

    constructor(
        BallArgs    memory args,
        IlkParams[] memory ilks
    ) payable {
        address rico = args.rico;
        address risk = args.risk;

        flow = new DutchFlower();
        vat  = new Vat();
        vow  = new Vow();
        hook = new ERC20Hook(args.feedbase, address(vat), address(flow), rico);

        vat.prod(args.par);

        vow.link('flow', address(flow));
        vow.link('vat',  address(vat));
        vow.link('RICO', rico);
        vow.link('RISK', risk);

        vat.file('ceil',  args.ceil);
        vat.link('rico',  rico);
        vow.ward(address(flow), true);
        vat.ward(address(vow), true);
        hook.ward(address(flow), true); // flowback
        hook.ward(address(vat), true);  // grabhook, frobhook

        mdn = new Medianizer(args.feedbase);
        adapt = new UniswapV3Adapter(Feedbase(args.feedbase));
        divider = new Divider(args.feedbase, RAY);
        twap = new TWAP(args.feedbase);
        Medianizer.Source[] memory mdn_sources = new Medianizer.Source[](1);
        mdn_sources[0].src = address(divider);
        for (uint i = 0; i < ilks.length; i++) {
            IlkParams memory ilkparams = ilks[i];
            bytes32 ilk = ilkparams.ilk;
            address gem = ilkparams.gem;
            address pool = ilkparams.pool;
            vat.init(ilk, address(hook));
            mdn_sources[0].tag = concat(ilk, 'rico');
            mdn.setSources(concat(ilk, 'rico'), mdn_sources);
            hook.wire(ilk, gem, address(mdn), concat(ilk, 'rico'));
            hook.grant(gem);
            vat.filk(ilk, 'chop', ilkparams.chop);
            vat.filk(ilk, 'dust', ilkparams.dust);
            vat.filk(ilk, 'fee',  ilkparams.fee);  // 5%
            vat.filk(ilk, 'line', ilkparams.line);
            vat.filk(ilk, 'liqr', ilkparams.liqr);
            hook.list(gem, true);

            if (gem != DAI) {
                bytes32 tag = concat(ilk, 'dai');
                adapt.setConfig(
                    tag,
                    UniswapV3Adapter.Config(pool, ilkparams.ttl, ilkparams.range, gem > DAI)
                );

                // TODO: Check what to use for range, ttl
                twap.setConfig(tag, TWAP.Config(address(adapt), tag, args.twaprange, args.twapttl));
                address[] memory ss = new address[](2);
                bytes32[] memory ts = new bytes32[](2);
                ss[0] = address(twap); ts[0] = tag;
                ss[1] = address(adapt); ts[1] = RICO_DAI_TAG;
                divider.setConfig(concat(ilk, 'rico'), Divider.Config(ss, ts));
            }

            hook.pair(gem, "fel", ilkparams.ramp.fel);
            hook.pair(gem, "del", ilkparams.ramp.del);
            hook.pair(gem, "gel", ilkparams.ramp.gel);
            hook.pair(gem, "feed", uint(uint160(ilkparams.ramp.feed)));
            hook.pair(gem, "fsrc", uint(uint160(address(mdn))));
            hook.pair(gem, "ftag", uint(ilkparams.ramp.ftag));
        }

        // todo ramp config
        vow.pair(risk, "fel", args.riskramp.fel);
        vow.pair(risk, "del", args.riskramp.del);
        vow.pair(risk, "gel", args.riskramp.gel);
        vow.pair(risk, "feed", uint(uint160(args.feedbase)));
        vow.pair(risk, "fsrc", uint(uint160(bytes20(address(mdn)))));
        vow.pair(risk, "ftag", uint(RISK_RICO_TAG));
        vow.file("vel", args.mintramp.vel);
        vow.file("rel", args.mintramp.vel);
        vow.file("bel", args.mintramp.bel);
        vow.file("cel", args.mintramp.cel);

        vow.pair(rico, "fel", args.ricoramp.fel);
        vow.pair(rico, "del", args.ricoramp.del);
        vow.pair(rico, "gel", args.ricoramp.gel);
        vow.pair(rico, "feed", uint(uint160(args.feedbase)));
        vow.pair(rico, "fsrc", uint(uint160(address(mdn))));
        vow.pair(rico, "ftag", uint(RICO_RISK_TAG));

        vow.grant(rico);
        vow.grant(risk);

        address roll = args.roll;
        vow.give(roll);
        hook.give(roll);
        // |------------------------->divider--------->twap------>| (usd/rico)
        // |                              |                       |
        // |                             inv                      |
        // |                              |                       |
        // |                         rico/dai                     |
        // |   Rico/Dai AMM ------------->|                       |
        // --- DAI/USD CL -- divider---->divider------>twap---->prog-->inv-->RICO/REF
        //     XAU/USD CL ----|                   ^
        //                                  (xau/rico)
        adapt.setConfig(
            RICO_DAI_TAG,
            UniswapV3Adapter.Config(args.ricodai, args.adaptrange, args.adaptttl, DAI < rico)
        );

        // dai/rico = 1 / (rico/dai)
        {
            address[] memory sources = new address[](2);
            bytes32[] memory tags    = new bytes32[](2);
            Feedbase(args.feedbase).push(bytes32("ONE"), bytes32(RAY), type(uint).max);
            sources[0] = address(this); tags[0] = bytes32("ONE");
            sources[1] = address(adapt); tags[1] = RICO_DAI_TAG;
            divider.setConfig(DAI_RICO_TAG, Divider.Config(sources, tags));
        }

        cladapt = new ChainlinkAdapter(args.feedbase);
        cladapt.setConfig(XAU_USD_TAG, ChainlinkAdapter.Config(XAU_USD_AGG, args.xauusdttl, RAY));
        cladapt.setConfig(DAI_USD_TAG, ChainlinkAdapter.Config(DAI_USD_AGG, args.daiusdttl, RAY));
        {
            address[] memory src3 = new address[](3);
            bytes32[] memory tag3 = new bytes32[](3);
            src3[0] = address(cladapt); tag3[0] = DAI_USD_TAG;
            src3[1] = address(divider); tag3[1] = DAI_RICO_TAG;
            src3[2] = address(cladapt); tag3[2] = XAU_USD_TAG;
            divider.setConfig(RICO_XAU_TAG, Divider.Config(src3, tag3));
        }
        twap.setConfig(RICO_XAU_TAG, TWAP.Config(address(divider), RICO_XAU_TAG, args.twaprange, args.twapttl));
        mdn_sources[0] = Medianizer.Source(address(twap), RICO_XAU_TAG);
        mdn.setSources(RICO_REF_TAG, mdn_sources);

        adapt.setConfig(
            RICO_RISK_TAG,
            UniswapV3Adapter.Config(args.ricorisk, args.adaptrange, args.adaptttl, rico < risk)
        );
        twap.setConfig(RICO_RISK_TAG, TWAP.Config(address(adapt), RICO_RISK_TAG, args.twaprange, args.twapttl));
        {
            address[] memory src2 = new address[](2);
            bytes32[] memory tag2 = new bytes32[](2);
            src2[0] = address(this); tag2[0] = bytes32("ONE");
            src2[1] = address(adapt); tag2[1] = RICO_RISK_TAG;
            divider.setConfig(RISK_RICO_TAG, Divider.Config(src2, tag2));
        }
        mdn_sources[0] = Medianizer.Source(address(twap), RICO_RISK_TAG);
        mdn.setSources(RICO_RISK_TAG, mdn_sources);
        mdn_sources[0] = Medianizer.Source(address(divider), RISK_RICO_TAG);
        mdn.setSources(RISK_RICO_TAG, mdn_sources);
        mdn.give(roll);
        divider.give(roll);
        adapt.give(roll);
        twap.give(roll);

        cladapt.look(XAU_USD_TAG);
        (bytes32 ref,) = Feedbase(args.feedbase).pull(address(cladapt), XAU_USD_TAG);
        vox = new Vox(uint256(ref));
        vox.link('fb',  args.feedbase);
        vox.link('tip', args.roll);
        vox.link('vat', address(vat));
        vox.link('tip', address(mdn));
        vox.file('tag', RICO_REF_TAG);
        vat.ward(address(vox), true);
        vat.give(roll);
        vox.give(roll);
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
