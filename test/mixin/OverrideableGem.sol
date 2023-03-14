// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

contract OverrideableGem {
    bytes32 public name;
    bytes32 public symbol;
    uint256 public totalSupply;
    uint8   public constant decimals = 18;

    mapping (address => uint)                      public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;
    mapping (address => uint)                      public nonces;
    mapping (address => bool)                      public wards;

    bytes32 immutable DOMAIN_SUBHASH = keccak256(
        'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
    );
    bytes32 immutable PERMIT_TYPEHASH = keccak256(
        'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
    );

    event Approval(address indexed src, address indexed usr, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Mint(address indexed caller, address indexed user, uint256 wad);
    event Burn(address indexed caller, address indexed user, uint256 wad);
    event Ward(address indexed setter, address indexed user, bool authed);

    error ErrPermitDeadline();
    error ErrPermitSignature();
    error ErrOverflow();
    error ErrUnderflow();
    error ErrWard();

    constructor(bytes32 name_, bytes32 symbol_)
      payable
    {
        name = name_;
        symbol = symbol_;

        wards[msg.sender] = true;
        emit Ward(msg.sender, msg.sender, true);
    }

    function ward(address usr, bool authed)
      payable external virtual {
        if (!wards[msg.sender]) revert ErrWard();
        wards[usr] = authed;
        emit Ward(msg.sender, usr, authed);
    }

    function mint(address usr, uint wad)
      payable external virtual {
        if (!wards[msg.sender]) revert ErrWard();
        // only need to check totalSupply for overflow
        unchecked {
            uint256 prev = totalSupply;
            if (prev + wad < prev) {
                revert ErrOverflow();
            }
            balanceOf[usr] += wad;
            totalSupply     = prev + wad;
            emit Mint(msg.sender, usr, wad);
        }
    }

    function burn(address usr, uint wad)
      payable external virtual {
        if (!wards[msg.sender]) revert ErrWard();
        // only need to check balanceOf[usr] for underflow
        unchecked {
            uint256 prev = balanceOf[usr];
            balanceOf[usr] = prev - wad;
            totalSupply    -= wad;
            emit Burn(msg.sender, usr, wad);
            if (prev < wad) {
                revert ErrUnderflow();
            }
        }
    }

    function transfer(address dst, uint wad)
      payable external virtual returns (bool ok)
    {
        unchecked {
            ok = true;
            uint256 prev = balanceOf[msg.sender];
            balanceOf[msg.sender] = prev - wad;
            balanceOf[dst]       += wad;
            emit Transfer(msg.sender, dst, wad);
            if( prev < wad ) {
                revert ErrUnderflow();
            }
        }
    }

    function transferFrom(address src, address dst, uint wad)
      payable external virtual returns (bool ok)
    {
        unchecked {
            ok              = true;
            balanceOf[dst] += wad;
            uint256 prevB   = balanceOf[src];
            balanceOf[src]  = prevB - wad;
            uint256 prevA   = allowance[src][msg.sender];

            emit Transfer(src, dst, wad);

            if ( prevA != type(uint256).max ) {
                allowance[src][msg.sender] = prevA - wad;
                if( prevA < wad ) {
                    revert ErrUnderflow();
                }
            }

            if( prevB < wad ) {
                revert ErrUnderflow();
            }
        }
    }

    function approve(address usr, uint wad)
      payable external virtual returns (bool ok)
    {
        ok = true;
        allowance[msg.sender][usr] = wad;
        emit Approval(msg.sender, usr, wad);
    }

    // EIP-2612
    function permit(address owner, address spender, uint256 value, uint256 deadline,
                    uint8 v, bytes32 r, bytes32 s)
      payable external virtual {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
        address signer;
        unchecked {
            signer = ecrecover(
                keccak256(abi.encodePacked( "\x19\x01",
                    keccak256(abi.encode( DOMAIN_SUBHASH,
                        keccak256("GemPermit"), keccak256("0"),
                        block.chainid, address(this))),
                    keccak256(abi.encode( PERMIT_TYPEHASH, owner, spender,
                        value, nonces[owner]++, deadline )))),
                v, r, s
            );
        }
        if (signer == address(0)) { revert ErrPermitSignature(); }
        if (owner != signer) { revert ErrPermitSignature(); }
        if (block.timestamp > deadline) { revert ErrPermitDeadline(); }
    }
}
