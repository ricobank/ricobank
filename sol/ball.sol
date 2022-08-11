/// SPDX-License-Identifier: AGPL-3.0

// The cannonball is the canonical deployment sequence
// implemented as one big contract. You can diff more
// efficient deployment sequences against the result of
// this one.

pragma solidity 0.8.15;

import {Plot} from './plot.sol';
import {Plug} from './plug.sol';
import {Port} from './port.sol';
import {Vat} from './vat.sol';
import {Vow} from './vow.sol';
import {Vox} from './vox.sol';

import {RicoFlowerV1} from './flow.sol';

interface GemFabLike {
    function build(
        bytes32 name,
        bytes32 symbol
    ) payable external returns (GemLike);
}

interface GemLike {
    function ward(address usr,
        bool authed
    ) payable external;
}

contract Ball {
    GemLike public rico;
    GemLike public risk;
    RicoFlowerV1 public flow;
    Plot public plot;
    Plug public plug;
    Port public port;
    Vat public vat;
    Vow public vow;
    Vox public vox;

    bytes32 public immutable gemFabHash = 0xc50480af81695123b87d00570a1f7efdef3241d74158683aa66fa13775b0fd61;
    bytes32 public immutable feedbaseHash = 0x7f077f77897df3acace06b253d14a11f9503318a47f731929c4972fabea5213c;

    constructor(GemFabLike gemfab, address feedbase) {
        bytes32 codeHash;
        assembly { codeHash := extcodehash(gemfab) }
        require(gemFabHash == codeHash, "Ball/gemfab codehash");
        assembly { codeHash := extcodehash(feedbase) }
        require(feedbaseHash == codeHash, "Ball/feedbase codehash");

        address roll = msg.sender;

        flow = new RicoFlowerV1();

        rico = gemfab.build(bytes32("Rico"), bytes32("RICO"));
        risk = gemfab.build(bytes32("Rico Riskshare"), bytes32("RISK"));

        plot = new Plot();
        plug = new Plug();
        port = new Port();
        vow = new Vow();
        vox = new Vox();
        vat = new Vat();

        flow.link('rico', address(rico));
        flow.link('risk', address(risk));
        flow.link('vow', address(vow));

        plot.link('fb', feedbase);
        plot.link('tip', roll);
        plot.link('vat', address(vat));

        vow.link('flapper', address(flow));
        vow.link('flopper', address(flow));
        vow.link('plug', address(plug));
        vow.link('port', address(port));
        vow.link('rico', address(rico));
        vow.link('risk', address(risk));
        vow.link('vat', address(vat));

        vox.link('fb', feedbase);
        vox.link('tip', roll);
        vox.link('vat', address(vat));

        vat.file('ceil', 1000e45);

        vow.file('bar', 100_000e45);
        vow.file('vel', 1e18);
        vow.file('rel', 1e12);
        vow.file('cel', 600);

        vat.ward(address(plot), true);
        vat.ward(address(plug), true);
        vat.ward(address(port), true);
        vat.ward(address(vow), true);
        vat.ward(address(vox), true);

        rico.ward(address(port), true);
        risk.ward(address(vow), true);

        // gem doesn't have give right now
        rico.ward(roll, true);
        rico.ward(address(this), false);
        risk.ward(roll, true);
        risk.ward(address(this), false);

        flow.give(roll);
        plot.give(roll);
        plug.give(roll);
        port.give(roll);
        vow.give(roll);
        vox.give(roll);
        vat.give(roll);

    }
}
