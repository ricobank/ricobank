import { expect as want } from 'chai'

import * as hh from 'hardhat'
// @ts-ignore
import { ethers } from 'hardhat'

import { rad, wad } from 'minihat'
const { hexZeroPad } = ethers.utils

import { getDiamondArtifact } from '../../task/helpers'

import { b32, revert_pop, revert_name, revert_clear, snapshot_name } from '../helpers'
const dpack = require('@etherpacks/dpack')

const bn2b32 = (bn) => hexZeroPad(bn.toHexString(), 32)
const BN = ethers.BigNumber.from
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

  it('set all lines but weth to zero and print data', async () => {
    const bank_artifact = getDiamondArtifact()
    const bank_type = ethers.ContractFactory.fromSolidity(bank_artifact, msig)
    bank = bank_type.attach(bank.address)

    const names = ["dai", "usdc", "usdc.e", "reth", "wbtc", "link", "wsteth", "arb", ":uninft"]

    for (let name of names) {
      let ilk = b32(name);
      let startLine = (await dapp.bank.ilks(ilk)).line;
      want(startLine).not.eql(BN(0))

      console.log(`setting line for ${name} to zero`)
      let data = bank.interface.encodeFunctionData('filk', [ilk, b32('line'), bn2b32(rad(0))])
      console.log(data, "\n")
      await msig.sendTransaction({to: bank.address, data})

      let finishLine = (await dapp.bank.ilks(ilk)).line;
      want(finishLine).eql(BN(0))
    }
  })

})
