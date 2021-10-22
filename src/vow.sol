// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.9;

import 'hardhat/console.sol';

import './mixin/math.sol';
import './mixin/ward.sol';

import './flow.sol';

interface VatLike {
    function joy() external returns (uint);
    function vice() external returns (uint);
    function heal(uint amt) external;
    function drip(bytes32 ilk) external;
    function rake() external returns (uint);
    function safe(bytes32,address) external returns (bool);
    function urns(bytes32,address) external returns (uint,uint);
    function grab(bytes32,address,address,address,int,int) external returns (uint);
    function gem(bytes32,address) external returns (uint);
}

interface VaultLike {
    function gem_join(address,bytes32,address,uint) external returns (address);
    function gem_exit(address,bytes32,address,uint) external returns (address);
    function joy_exit(address vat, address joy, address usr, uint amt) external;
    function joy_join(address vat, address joy, address usr, uint amt) external;

}

interface GemLike {
    function mint(address usr, uint amt) external;
    function burn(address usr, uint amt) external;
    function approve(address usr, uint amt) external;
    function balanceOf(address usr) external returns (uint);
    function transfer(address usr, uint amt) external;
}

contract Vow is Math, Ward {
    VatLike public vat;
    VaultLike public vault;
    GemLike public RICO;
    GemLike public BANK;
    mapping(bytes32=>address) public flippers;

    address pool;

    Flopper flopper;
    uint256 flopping;

    Flapper flapper;
    uint256 flapping;

    function bail(bytes32 ilk, address urn) external {
        require( !vat.safe(ilk, urn), 'ERR_SAFE' );
        address flipper = flippers[ilk];
        (uint ink, uint art) = vat.urns(ilk, urn);
        uint chop = vat.grab(ilk, urn, address(this), address(this), -int(ink), -int(art));
        address gem = vault.gem_exit(address(vat), ilk, address(this), ink);
        GemLike(gem).transfer(flipper, ink);
        //Flipper(flipper).flip(ilk, urn, gem, ink, art, chop);
    }

    function reapprove() external {
        RICO.approve(address(vault), type(uint256).max);
        RICO.approve(address(pool), type(uint256).max);
        BANK.approve(address(pool), type(uint256).max);
    }

    function file_vat(address v) external {
        ward(); vat = VatLike(v);
    }
    function file_vault(address v) external {
        ward(); vault = VaultLike(v);
    }
    function file_flipper(bytes32 ilk, address f) external {
        ward(); flippers[ilk] = f;
    }

}



