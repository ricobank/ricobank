const debug = require('debug')('rico:test')
import { expect as want } from 'chai'

import * as hh from 'hardhat'
// @ts-ignore
import { ethers } from 'hardhat'
import { constants } from 'ethers'

import { wad } from 'minihat'
const { hexZeroPad } = ethers.utils

import { getDiamondArtifact } from '../../task/helpers'

import { b32, revert_pop, revert_name, revert_clear, snapshot_name } from '../helpers'
const dpack = require('@etherpacks/dpack')

const bn2b32 = (bn) => hexZeroPad(bn.toHexString(), 32)
const BN = ethers.BigNumber.from
const PRE_CID = 'bafkreieglufuj5bnde3id5yizytsncsskfuyizmvf2bhf5fa6skt74rf6m'
const FCA = {ADD: 0, REPLACE: 1, REMOVE: 2};  // Facet Cut Actions

describe('Test diamond cut function to add wards to gems', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let bank
  let dapp
  let msig

  let newFile

  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)

    dapp = await dpack.load(PRE_CID, ethers, ali)

    const MSIG = '0x85808ff766a80aB61Aafe354e7edDacc94230046'
    await ali.sendTransaction({to: MSIG, value: wad(1)})
    await hh.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [MSIG],
    });

    msig = await ethers.getSigner(MSIG)

    bank = dapp.bank.connect(msig)

    debug('deploying new File')  // New File has not yet been deployed on arbitrum one
    const newFile_artifact = require('../../artifacts/src/file.sol/File.json')
    const newFile_type = ethers.ContractFactory.fromSolidity(newFile_artifact, ali)
    newFile = await newFile_type.deploy()

    await snapshot_name(hh);
  })

  afterEach(async () => revert_name(hh))
  after(async () => {
      revert_pop(hh)
      revert_clear(hh)
  })

  const getSel = x => ethers.utils.id(x).slice(0, 10)

  const cutFile = async () => {
    const enlistSel = getSel('enlist(address,address,bool)')

    const cuts = [[newFile.address, FCA.ADD, [enlistSel]]]
    const data = bank.interface.encodeFunctionData(
      'diamondCut', [cuts, constants.AddressZero, '0x']
    )

    await msig.sendTransaction({to: bank.address, data})
    console.log(data)

    const facet = await bank.facetAddress(enlistSel)
    want(facet).eql(newFile.address)
  }

  it('cut adding gem wards', async () => {

    console.log('cut file:')
    await cutFile()

    const bank_artifact = getDiamondArtifact()
    const bank_type = ethers.ContractFactory.fromSolidity(bank_artifact, msig)
    bank = bank_type.attach(bank.address)

    let data = bank.interface.encodeFunctionData('enlist', [dapp.risk.address, BOB, true])
    await msig.sendTransaction({to: bank.address, data})
    want(await dapp.risk.wards(BOB)).eql(true)

    // test bob can now mint
    const bobsRisk = dapp.risk.connect(bob);
    await bobsRisk.mint(BOB, 10)
    const bobRiskBal = await dapp.risk.balanceOf(BOB)
    want(bobRiskBal).eql(BN(10))

    // non owners should not be able to add wards
    data = bank.interface.encodeFunctionData('enlist', [dapp.risk.address, CAT, true])
    let txWorked = true
    try {
      await cat.sendTransaction({
        to: bank.address,
        data: data,
        gasLimit: 1_000_000,
      });
    } catch (error) {
      txWorked = false
    }
    want(txWorked).eql(false)
    want(await dapp.risk.wards(CAT)).eql(false)

    // can still use previous unchanged file
    const dam = BN('123')
    data = bank.interface.encodeFunctionData('file', [b32('dam'), bn2b32(dam)])
    await msig.sendTransaction({to: bank.address, gasLimit: 1_000_000, data})
    want(await bank.dam()).eql(dam)

    let rcspack = await dpack.getIpfsJson(PRE_CID)
    delete rcspack.types.BankDiamond
    delete rcspack.objects.bank
    let pb = new dpack.PackBuilder('arbitrum')
    pb = await pb.packObject({
        objectname: 'bank',
        address: bank.address,
        typename: 'BankDiamond',
        artifact: bank_artifact
    }, true)
    pb = await pb.merge(rcspack)

    const cid = await dpack.putIpfsJson(pb.build(), true)
    console.log(`pinned new rcs pack at ${cid}`)
  })

})
