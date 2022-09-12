pragma solidity 0.8.15;

interface ERC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address usr) external view returns (uint);
    function approve(address usr, uint amt) external;
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
}

interface GemLike is ERC20 {
    function mint(address usr, uint amt) external;
    function burn(address usr, uint amt) external;
    function ward(address usr, bool authed) external;
    function ErrOverflow()external;
    function ErrUnderflow()external;
    function ErrWard()external;
}

interface WardLike {
    function ward(address, bool) external;
}

interface VatLike is WardLike {
    // from Dock
    function lob(address src, address dst, uint amt) external;
    function move(address,uint) external;
    function slip(bytes32,address,int) external;

    // from Plot
    function plot(bytes32 ilk, uint256 ray) external;

    // from Vow
    function joy(address) external returns (uint);
    function sin(address) external returns (uint);
    function heal(uint amt) external;
    function drip(bytes32 ilk) external;
    function rake() external returns (uint);
    function safe(bytes32,address) external returns (bool);
    function urns(bytes32,address) external returns (uint,uint);
    function grab(bytes32,address,int,int) external returns (uint);

    // from Vox
    function prod(uint256 par) external;

    // from User
    function filk(bytes32 ilk, bytes32 key, uint val) external;
    function frob(bytes32 i, address u, int dink, int dart) external;
    function init(bytes32 ilk, address gem) external;
    function gem(bytes32 ilk, address usr) external returns (uint);
    function par() external returns (uint);
}

interface DockLike {
    function join_gem(address vat, bytes32 ilk, address usr, uint wad) external returns (address);
    function exit_gem(address vat, bytes32 ilk, address usr, uint wad) external returns (address);
    function join_rico(address vat, address joy, address usr, uint wad) external;
    function exit_rico(address vat, address joy, address usr, uint wad) external;
    function flash(address gem, uint wad, address code, bytes calldata data) external;
    function bind_joy(address vat, address joy, bool bound) external;
    function bind_gem(address vat, bytes32 ilk, address gem) external;
    function list(address gem, bool bit) external;
    function ErrOverflow() external;
    function ErrNotBound() external;
    function ErrTransfer() external;
    function ErrNoIlkGem() external;
    function ErrMintCeil() external;
    function ErrLock() external;
}

interface FeedbaseLike {
    function pull(address src, bytes32 tag) external returns (bytes32 val, uint ttl);
}


// Abstract liquidations
interface Flow {
    function flow(address hag, uint ham, address wag, uint wam) external returns (bytes32);
    function glug(bytes32 aid) external;
    function clip(address gem, uint max) external returns (uint, uint);
    function curb(address gem, bytes32 key, uint val) external;
}

interface Flowback {
    function flowback(bytes32 aid, address gem, uint refund) external;
}
