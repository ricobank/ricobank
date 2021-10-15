
pragma solidity 0.8.9;

import 'hardhat/console.sol';

import './mixin/math.sol';
import './mixin/ward.sol';

interface VatLike {
    function safe(bytes32,address) external returns (bool);
    function urns(bytes32,address) external returns (uint,uint);
    function grab(bytes32,address,address,address,int,int) external returns (uint);
    function gem(bytes32,address) external returns (uint);
}

interface VaultLike {
    function gem_join(address,bytes32,address,uint) external returns (address);
    function gem_exit(address,bytes32,address,uint) external returns (address);
}

interface Flipper {
    function flip(bytes32 ilk, address urn, address gem, uint ink, uint art, uint chop) external;
}

interface GemLike {
    function transfer(address,uint256) external;
}

contract Bat is Math, Ward {
    VatLike public vat;
    address public vow;
    VaultLike public vault;
    mapping(bytes32=>address) public flippers;

    function bite(bytes32 ilk, address urn) external returns (bytes32) {
        require( !vat.safe(ilk, urn), 'ERR_SAFE' );
        address flipper = flippers[ilk];
        (uint ink, uint art) = vat.urns(ilk, urn);
        uint chop = vat.grab(ilk, urn, address(this), vow, -int(ink), -int(art));
        uint cart = mul(chop, art);
        address gem = vault.gem_exit(address(vat), ilk, address(this), ink);
        console.log('gem');
        console.log(gem);
        console.log('ink');
        console.log(ink);
        GemLike(gem).transfer(flipper, ink);
        //Flipper(flipper).flip(address(this), gem, ink, cart);
    }

    function file_vat(address v) external {
        ward(); vat = VatLike(v);
    }
    function file_vow(address v) external {
        ward(); vow = v;
    }
    function file_vault(address v) external {
        ward(); vault = VaultLike(v);
    }
    function file_flipper(bytes32 ilk, address f) external {
        ward(); flippers[ilk] = f;
    }

}
