import { expect as want } from 'chai'

import * as hh from 'hardhat'
// @ts-ignore
import { ethers } from 'hardhat'

import { send, rad, wad } from 'minihat'
const { hexZeroPad } = ethers.utils

import { b32, revert_pop, revert_name, revert_clear, snapshot_name, join_pool } from '../helpers'
const dpack = require('@etherpacks/dpack')

const bn2b32 = (bn) => hexZeroPad(bn.toHexString(), 32)
const rpaddr = (a) => a + '00'.repeat(12)
const PRE_CID = 'bafkreieglufuj5bnde3id5yizytsncsskfuyizmvf2bhf5fa6skt74rf6m'

describe('set all lines but weth to zero and print data', () => {
  const MSIG = '0x85808ff766a80aB61Aafe354e7edDacc94230046'

  let ali, bob, cat
  let ALI, BOB, CAT
  let bank
  let dapp
  let msig

  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)

    dapp = await dpack.load(PRE_CID, ethers, ali)

    await ali.sendTransaction({to: MSIG, value: wad(1)})
    await hh.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [MSIG],
    });

    msig = await ethers.getSigner(MSIG)

    bank = dapp.bank.connect(msig)

    await snapshot_name(hh);
  })

  afterEach(async () => revert_name(hh))
  after(async () => {
      revert_pop(hh)
      revert_clear(hh)
  })

  it('create a new uni ilk with rico and weth', async () => {
    const prevIlk  = b32(':uninft')
    const newIlk   = b32(':uninft-rico-weth')
    const prevHook = (await dapp.bank.ilks(prevIlk)).hook;
    const prevFee  = (await dapp.bank.ilks(prevIlk)).fee;
    const prevChop = (await dapp.bank.ilks(prevIlk)).chop;
    const prevDust = (await dapp.bank.ilks(prevIlk)).dust;

    const prevRoom = (await dapp.bank.geth(prevIlk, b32('room'), []));
    const prevPep  = (await dapp.bank.geth(prevIlk, b32('pep'), []));
    const prevPop  = (await dapp.bank.geth(prevIlk, b32('pop'), []));

    const prevWethSrc  = (await dapp.bank.geth(prevIlk, b32('src'),  [rpaddr(dapp.weth.address)]));
    const prevRicoSrc  = (await dapp.bank.geth(prevIlk, b32('src'),  [rpaddr(dapp.rico.address)]));
    const prevWethTag  = (await dapp.bank.geth(prevIlk, b32('tag'),  [rpaddr(dapp.weth.address)]));
    const prevRicoTag  = (await dapp.bank.geth(prevIlk, b32('tag'),  [rpaddr(dapp.rico.address)]));
    const prevWethLiqr = (await dapp.bank.geth(prevIlk, b32('liqr'), [rpaddr(dapp.weth.address)]));
    const prevRicoLiqr = (await dapp.bank.geth(prevIlk, b32('liqr'), [rpaddr(dapp.rico.address)]));

    const prevLine = rad(1000)

    async function msigAction(description, functionName, args) {
        console.log(description);
        let data = bank.interface.encodeFunctionData(functionName, args);
        console.log(data, "\n");
        await msig.sendTransaction({to: bank.address, data});
    }

    /* Initialize the new ilk using the same uni hook contract */
    await msigAction(`Initializing new uni ilk ${newIlk}`, 'init', [newIlk, prevHook]);

    /* file ilk parameters */
    await msigAction(`Setting fee  to ${prevFee}`,  'filk', [newIlk, b32('fee'),  bn2b32(prevFee)]);
    await msigAction(`Setting chop to ${prevChop}`, 'filk', [newIlk, b32('chop'), bn2b32(prevChop)]);
    await msigAction(`Setting dust to ${prevDust}`, 'filk', [newIlk, b32('dust'), bn2b32(prevDust)]);
    await msigAction(`Setting line to ${prevLine}`, 'filk', [newIlk, b32('line'), bn2b32(prevLine)]);

    /* file hook parameters */
    await msigAction(`Setting wrap to ${dapp.uniwrapper.address}`, 'filh', [newIlk, b32('wrap'), [], rpaddr(dapp.uniwrapper.address)]);
    await msigAction(`Setting room to ${prevRoom}`, 'filh', [newIlk, b32('room'), [], prevRoom]);
    await msigAction(`Setting pep  to ${prevPep}`,  'filh', [newIlk, b32('pep'),  [], prevPep]);
    await msigAction(`Setting pop  to ${prevPop}`,  'filh', [newIlk, b32('pop'),  [], prevPop]);

    /* set the per gem hook parameters to match original uni hook values for weth and rico,
    *  may want to update fork block in hardhat config for modifications to paired gem (weth) */
    await msigAction(`Setting rico src  to ${prevRicoSrc}`,  'filh', [newIlk, b32('src'),  [rpaddr(dapp.rico.address)], prevRicoSrc]);
    await msigAction(`Setting rico tag  to ${prevRicoTag}`,  'filh', [newIlk, b32('tag'),  [rpaddr(dapp.rico.address)], prevRicoTag]);
    await msigAction(`Setting rico liqr to ${prevRicoLiqr}`, 'filh', [newIlk, b32('liqr'), [rpaddr(dapp.rico.address)], prevRicoLiqr]);

    await msigAction(`Setting weth src to  ${prevWethSrc}`,  'filh', [newIlk, b32('src'),  [rpaddr(dapp.weth.address)], prevWethSrc]);
    await msigAction(`Setting weth tag to  ${prevWethTag}`,  'filh', [newIlk, b32('tag'),  [rpaddr(dapp.weth.address)], prevWethTag]);
    await msigAction(`Setting weth liqr to ${prevWethLiqr}`, 'filh', [newIlk, b32('liqr'), [rpaddr(dapp.weth.address)], prevWethLiqr]);

    /* ensure values now match */
    const newHook     = (await dapp.bank.ilks(newIlk)).hook;
    const newFee      = (await dapp.bank.ilks(newIlk)).fee;
    const newChop     = (await dapp.bank.ilks(newIlk)).chop;
    const newDust     = (await dapp.bank.ilks(newIlk)).dust;
    const newRoom     = (await dapp.bank.geth(newIlk, b32('room'), []));
    const newPep      = (await dapp.bank.geth(newIlk, b32('pep'),  []));
    const newPop      = (await dapp.bank.geth(newIlk, b32('pop'),  []));
    const newWethSrc  = (await dapp.bank.geth(newIlk, b32('src'),  [rpaddr(dapp.weth.address)]));
    const newRicoSrc  = (await dapp.bank.geth(newIlk, b32('src'),  [rpaddr(dapp.rico.address)]));
    const newWethTag  = (await dapp.bank.geth(newIlk, b32('tag'),  [rpaddr(dapp.weth.address)]));
    const newRicoTag  = (await dapp.bank.geth(newIlk, b32('tag'),  [rpaddr(dapp.rico.address)]));
    const newWethLiqr = (await dapp.bank.geth(newIlk, b32('liqr'), [rpaddr(dapp.weth.address)]));
    const newRicoLiqr = (await dapp.bank.geth(newIlk, b32('liqr'), [rpaddr(dapp.rico.address)]));

    want(newHook).eql(prevHook)
    want(newFee).eql(prevFee)
    want(newChop).eql(prevChop)
    want(newDust).eql(prevDust)
    want(newRoom).eql(prevRoom)
    want(newPep).eql(prevPep)
    want(newPop).eql(prevPop)
    want(newWethSrc).eql(prevWethSrc)
    want(newRicoSrc).eql(prevRicoSrc)
    want(newWethTag).eql(prevWethTag)
    want(newRicoTag).eql(prevRicoTag)
    want(newWethLiqr).eql(prevWethLiqr)
    want(newRicoLiqr).eql(prevRicoLiqr)

    // use new uni ilk for basic frob
    // get ali some rico and weth
    await ali.sendTransaction({to: dapp.weth.address, value: wad(1000)});
    await dapp.weth.approve(dapp.bank.address, wad(100_000))
    await dapp.weth.approve(dapp.nonfungiblePositionManager.address, wad(100_000))
    await dapp.rico.approve(dapp.nonfungiblePositionManager.address, wad(100_000))
    const wethDink = ethers.utils.solidityPack(['int'], [wad(100)])
    await send(dapp.bank.frob, b32('weth'), ALI, wethDink, wad(10))

    // get ali a rico/weth LP position
    const joinres = await join_pool({
      nfpm: dapp.nonfungiblePositionManager, ethers, ali,
      a1: { token: dapp.weth.address, amountIn: wad(10) },
      a2: { token: dapp.rico.address, amountIn: wad(10) },
      fee: 500,
      tickSpacing: 10
    })

    await dapp.nonfungiblePositionManager.approve(bank.address, joinres.tokenId)
    let dink = ethers.utils.defaultAbiCoder.encode(['uint[]'], [[1, joinres.tokenId]])
    await dapp.bank.frob(newIlk, ALI, dink, wad(10))
  })

})
