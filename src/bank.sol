// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2024 halys

pragma solidity ^0.8.25;

import { OwnableInternal } from "../lib/solidstate-solidity/contracts/access/OwnableInternal.sol";
import { Math } from "./mixin/math.sol";
import { Flog } from "./mixin/flog.sol";
import { Palm } from "./mixin/palm.sol";
import { Gem }  from "../lib/gemfab/src/gem.sol";

abstract contract Bank is Math, Flog, Palm, OwnableInternal {

    // per-collateral type accounting
    struct Ilk {
        uint256 tart;  // [wad] Total Normalised Debt
        uint256 rack;  // [ray] Accumulated Rate

        uint256 line;  // [rad] Debt Ceiling
        uint256 dust;  // [rad] Urn Debt Floor

        uint256  fee;  // [ray] Collateral-specific, per-second compounding rate
        uint256  rho;  // [sec] Time of last drip

        uint256 chop;  // [ray] Liquidation Penalty
        uint256 liqr;  // [ray] Liquidation Ratio

        Plx     plot;  // [obj] discount exponent and offset
    }

    struct BankStorage {
        Gem      rico;
    }

    struct Urn {
        uint256 ink;   // [wad] Locked Collateral
        uint256 art;   // [wad] Normalised Debt
    }

    struct VatStorage {
        mapping (bytes32 => Ilk) ilks; // collaterals
        mapping (bytes32 => mapping (address => Urn )) urns; // CDPs
        uint256 joy;   // [wad]
        uint256 sin;   // [rad]
        uint256 rest;  // [rad] Debt remainder
        uint256 debt;  // [wad] Total Rico Issued
        uint256 ceil;  // [wad] Total Debt Ceiling
        uint256 par;   // [ray] System Price (rico/ref)
    }

    // flap config
    struct Ramp {
        uint256 bel; // [sec] last flap and poke timestamp
        uint256 wel; // [ray] fraction of joy/flap
    }

    struct Plx {
        uint256 pep; // [int] discount growth exponent
        uint256 pop; // [ray] relative discount factor
        int256  pup; // [ray] relative discount y-axis shift
    }

    struct VowStorage {
        Ramp    ramp;
        Gem     risk;
        uint256 dam;  // [ray] per-second flap discount
    }

    struct VoxStorage {
        uint256 way; // [ray] System Rate (SP growth rate)
        uint256 how; // [ray] sensitivity paramater
        uint256 cap; // [ray] `way` bound
    }

    bytes32 internal constant VAT_INFO = "vat.0";
    bytes32 internal constant VAT_POS  = keccak256(abi.encodePacked(VAT_INFO));
    bytes32 internal constant VOW_INFO = "vow.0";
    bytes32 internal constant VOW_POS  = keccak256(abi.encodePacked(VOW_INFO));
    bytes32 internal constant VOX_INFO = "vox.0";
    bytes32 internal constant VOX_POS  = keccak256(abi.encodePacked(VOX_INFO));
    bytes32 internal constant BANK_INFO = "ricobank.0";
    bytes32 internal constant BANK_POS  = keccak256(abi.encodePacked(BANK_INFO));
    function getVowStorage() internal pure returns (VowStorage storage vs) {
        bytes32 pos = VOW_POS;  assembly { vs.slot := pos }
    }
    function getVoxStorage() internal pure returns (VoxStorage storage vs) {
        bytes32 pos = VOX_POS;  assembly { vs.slot := pos }
    }
    function getVatStorage() internal pure returns (VatStorage storage vs) {
        bytes32 pos = VAT_POS;  assembly { vs.slot := pos }
    }
    function getBankStorage() internal pure returns (BankStorage storage bs) {
        bytes32 pos = BANK_POS; assembly { bs.slot := pos }
    }

    error ErrWrongKey();
    error ErrBound();

    function must(uint actual, uint lo, uint hi) internal pure {
        if (actual < lo || actual > hi) revert ErrBound();
    }

}
