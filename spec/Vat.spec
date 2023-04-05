// vat spec

using Gem as rico
using BlankHook as blankhook
methods {
    hookie(bytes32) returns (address) envfree
    frob(bytes32,address,int,int)
    grab(bytes32,address,int,address)
    heal(uint)
    drip(bytes32)
    urns(bytes32, address) returns (uint, uint) envfree
    ilks(bytes32) returns (uint,uint,address,bytes32,uint,uint,uint,uint,uint,uint,address)
    rack(bytes32) returns (uint) envfree
    ink(bytes32, address) returns (uint) envfree
    art(bytes32, address) returns (uint) envfree
    tart(bytes32) returns (uint) envfree
    rico() returns (address) envfree
    debt() returns (uint) envfree
    rest() returns (uint) envfree
    init(bytes32, address, address, bytes32)
    sin(address) returns (uint) envfree

    rico.totalSupply() returns (uint) envfree
    rico.balanceOf(address) returns (uint) envfree
    rico.wards(address) returns (bool) envfree

    wards(address) returns (bool) envfree
    self() returns (address) envfree

    frobhook(address,bytes32,address,int,int) => DISPATCHER(true)
    grabhook(address,bytes32,address,int,int,uint) returns (uint) => DISPATCHER(true)
}

// frob increases debt and art by dart * rack
// frob increases ink by dink
ghost mapping(bytes32=>mathint) sum_of_arts {
    init_state axiom (forall bytes32 i . sum_of_arts[i] == 0);
}
hook Sstore urns[KEY bytes32 i][KEY address u].art uint newval (uint oldval) STORAGE {
    sum_of_arts[i] = sum_of_arts[i] + (to_mathint(newval) - to_mathint(oldval));
}

invariant ilkUninitializedIfRackIs(bytes32 i)
    rack(i) != 0 || tart(i) == 0

// ilks[i].tart == sum_u(urns[i][u].art)
invariant tartIsSumOfArts(bytes32 i)
    to_mathint(tart(i)) == sum_of_arts[i]
    { preserved { requireInvariant ilkUninitializedIfRackIs(i); } }

ghost mapping (bytes32=>bool) ilk_initialized {
    init_state axiom (forall bytes32 i . ilk_initialized[i] == false);
}

hook Sstore ilks[KEY bytes32 i].rack uint newval (uint oldval) STORAGE {
    ilk_initialized[i] = true;
}

// only one vat => rico.totalSupply() == debt()
rule debtEqualsSupply {
    env e; method f; calldataarg args;

    require rico.totalSupply() == debt();
    require rico.balanceOf(e.msg.sender) <= rico.totalSupply();
    require forall bytes32 i . hookie(i) == blankhook;

    f(e, args);

    assert to_mathint(rico.totalSupply()) == debt(),
        "fundie";
}
