
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
    // from Join/Plug
    function slip(bytes32,address,int) external;
    function move(address,address,uint) external;

    // from Plot
    function plot(bytes32 ilk, uint256 ray) external;

    // from Vow
    function joy(address) external returns (uint);
    function sin(address) external returns (uint);
    function heal(uint amt) external;
    function drip(bytes32 ilk) external;
    function hope(address) external;
    function rake() external returns (uint);
    function safe(bytes32,address) external returns (bool);
    function urns(bytes32,address) external returns (uint,uint);
    function grab(bytes32,address,address,address,int,int) external returns (uint);

    // from Vox
    function par() external returns (uint256);
    function way() external returns (uint256);
    function prod() external;
    function sway(uint256 r) external;
}

interface JoinLike {
    function join(address,bytes32,address,uint) external returns (address);
    function exit(address,bytes32,address,uint) external returns (address);
}

interface PlugLike {
    function join(address vat, address joy, address usr, uint amt) external;
    function exit(address vat, address joy, address usr, uint amt) external;
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


/**
 * @dev Interface of the ERC3156 FlashBorrower, as defined in
 * https://eips.ethereum.org/EIPS/eip-3156[ERC-3156].
 */
interface IERC3156FlashBorrower {
    /**
     * @dev Receive a flash loan.
     * @param initiator The initiator of the loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param fee The additional amount of tokens to repay.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     * @return The keccak256 hash of "ERC3156FlashBorrower.onFlashLoan"
     */
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32);
}


interface IERC3156FlashLender {
    /**
     * @dev The amount of currency available to be lended.
     * @param token The loan currency.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token) external view returns (uint256);

    /**
     * @dev The fee to be charged for a given loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address token, uint256 amount) external view returns (uint256);

    /**
     * @dev Initiate a flash loan.
     * @param receiver The receiver of the tokens in the loan, and the receiver of the callback.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     */
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);
}
