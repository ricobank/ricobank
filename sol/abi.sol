
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
}

interface VatLike {
    // from Plug/Port
    function slip(bytes32,address,int) external;
    function move(address,address,uint) external;

    // from Plot
    function plot(bytes32 ilk, uint256 ray) external;

    // from Vow
    function joy(address) external returns (uint);
    function sin(address) external returns (uint);
    function heal(uint amt) external;
    function drip(bytes32 ilk) external;
    function trust(address, bool) external;
    function rake() external returns (uint);
    function safe(bytes32,address) external returns (bool);
    function urns(bytes32,address) external returns (uint,uint);
    function grab(bytes32,address,address,address,int,int) external returns (uint);

    // from Vox
    function par() external returns (uint256);
    function way() external returns (uint256);
    function prod() external returns (uint256);
    function sway(uint256 r) external;

    // from User
    function lock(bytes32 i, uint amt) external;
    function free(bytes32 i, uint amt) external;
    function draw(bytes32 i, uint amt) external;
    function wipe(bytes32 i, uint amt) external;    
}

interface PlugLike {
    function join(address,bytes32,address,uint) external returns (address);
    function exit(address,bytes32,address,uint) external returns (address);
    function bind(address vat, bytes32 ilk, address gem) external;
    function flash(
        address[] calldata gems_,
        uint[] calldata amts,
        address code,
        bytes calldata data
        ) external returns (bytes memory);
}

interface PortLike {
    function join(address vat, address joy, address usr, uint amt) external;
    function exit(address vat, address joy, address usr, uint amt) external;
    function bind(address vat, address joy, bool bound) external;
    function flash(address joy, address code, bytes calldata data)
      external returns (bytes memory);
}

interface FeedbaseLike {
    function read(address src, bytes32 tag) external returns (bytes32 val, uint ttl);
}


// Abstract liquidations
interface Flipper {
    function flip(bytes32 ilk, address urn, address gem, uint ink, uint bill) external;
}

interface Flapper {
    function flap(uint surplus) external;
}

interface Flopper {
    function flop(uint debt) external;
}

interface Plopper {
    function plop(bytes32 ilk, address urn, uint amt) external;
}

interface Yanker {
    function yank() external returns (uint256);
}
