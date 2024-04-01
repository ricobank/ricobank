const debug = require('debug')('rico:test')
import { expect as want } from 'chai'

import * as hh from 'hardhat'
// @ts-ignore
import { ethers } from 'hardhat'
import { constants } from 'ethers'

import { wad, ray } from 'minihat'
const { hexZeroPad } = ethers.utils

import { getDiamondArtifact } from '../../task/helpers'

import { b32, revert_pop, revert_name, revert_clear, snapshot_name } from '../helpers'
const dpack = require('@etherpacks/dpack')

const bn2b32 = (bn) => hexZeroPad(bn.toHexString(), 32)
const BN = ethers.BigNumber.from

describe('Test diamond cut modifications', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let bank
  let dapp
  let msig

const FCA = {ADD: 0, REPLACE: 1, REMOVE: 2};

  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)

    const cid = 'bafkreibgmj3srxcccdbgvo3sdsfrcm36hv7pmw7nofcwfghjvqfe5zuffa'
    dapp = await dpack.load(cid, ethers, ali)

    const MSIG = '0x85808ff766a80aB61Aafe354e7edDacc94230046'
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

  const getSel = x => ethers.utils.id(x).slice(0, 10)

  // replace (rudd, plat, plot) with (dam, dom, pex)
  // same as cutStandard otherwise
  const cutVow = async () => {
    const rmsels = ['keep(bytes32[])', 'RISK()', 'ramp()', 'loot()', 'rudd()', 'plat()', 'plot()']
      .map(getSel)

    const addsels = ['keep(bytes32[])', 'RISK()', 'ramp()', 'loot()', 'dam()', 'dom()', 'pex()']
      .map(getSel)

    const VOW   = '0x254834c73e3070a674ea8059Be3c813694070f06'
    const AZERO = constants.AddressZero

    const cuts = [[constants.AddressZero, FCA.REMOVE, rmsels], [VOW, FCA.ADD, addsels]]

    const data = bank.interface.encodeFunctionData(
      'diamondCut', [cuts, constants.AddressZero, '0x']
    )

    await msig.sendTransaction({to: bank.address, data})
    console.log(data)

    const sels = [
      'keep(bytes32[])', 'RISK()', 'ramp()', 'loot()', 'rudd()', 'plat()',
      'plot()', 'dam()', 'dom()', 'pex()'
    ].map(getSel)
    let facets = []
    for (let sel of sels) {
      facets.push(await bank.facetAddress(sel))
    }

    want(facets).eql([VOW, VOW, VOW, VOW, AZERO, AZERO, AZERO, VOW, VOW, VOW])

  }

  // point all of prev's selectors to next
  const cutStandard = async (PREV, NEXT) => {
    const sels = await bank.facetFunctionSelectors(PREV)

    const cuts = [[NEXT, FCA.REPLACE, sels]]

    const data = bank.interface.encodeFunctionData(
      'diamondCut', [cuts, constants.AddressZero, '0x']
    )

    await msig.sendTransaction({to: bank.address, data})
    console.log(data)

    for (let sel of sels) {
      const facet = await bank.facetAddress(sel)
      want(facet).eql(NEXT)
    }

  }

  const cutVat = async () => {
    const VAT   = '0xc6D7b37FE18A3Dd007F9b1C3b339B8c6043b3ccf'
    const oldVAT = await bank.facetAddress(getSel('debt()'))
    await cutStandard(oldVAT, VAT)
  }

  const cutFile = async () => {
    const FILE = '0x8dFb233ef877dd5a260a52EcED01A0f7e160B7b2'
    const oldFILE = await bank.facetAddress(getSel('file(bytes32,bytes32)'))
    await cutStandard(oldFILE, FILE)
  }

  it('cut 0.1', async () => {

    console.log('cut vow:')
    await cutVow()
    console.log('cut vat:')
    await cutVat()
    console.log('cut file:')
    await cutFile()

    const bank_artifact = getDiamondArtifact()
    const bank_type = ethers.ContractFactory.fromSolidity(bank_artifact, msig)
    bank = bank_type.attach(bank.address)

    console.log('file dam:')
    const dam = BN('999760176148485019772757194')
    let data = bank.interface.encodeFunctionData('file', [b32('dam'), bn2b32(dam)])
    console.log(data)
    await msig.sendTransaction({to: bank.address, data})

    console.log('file dom:')
    const dom = dam
    data = bank.interface.encodeFunctionData('file', [b32('dom'), bn2b32(dom)])
    console.log(data)
    await msig.sendTransaction({to: bank.address, data})

    console.log('file cel:')
    const cel = BN(172800) // 2 days
    data = bank.interface.encodeFunctionData('file', [b32('cel'), bn2b32(cel)])
    console.log(data)
    await msig.sendTransaction({to: bank.address, data})

    want(await bank.dam()).eql(dam)
    want(await bank.dom()).eql(dom)
    want((await bank.ramp()).cel).eql(cel)
    want(await bank.pex()).eql(ray(1).mul(wad(1)))

    const rcscid = 'bafkreibgmj3srxcccdbgvo3sdsfrcm36hv7pmw7nofcwfghjvqfe5zuffa'
    let rcspack = await dpack.getIpfsJson(rcscid)
    delete rcspack.types.BankDiamond
    delete rcspack.objects.bank
    delete rcspack.objects.ricorisk
    const pb = new dpack.PackBuilder('arbitrum')
    await pb.packObject({
        objectname: 'bank',
        address: bank.address,
        typename: 'BankDiamond',
        artifact: bank_artifact
    }, true)
    rcspack = await pb.merge(rcspack)

    const cid = await dpack.putIpfsJson(pb.build(), true)
    console.log(`pinned new rcs pack at ${cid}`)
  })

})
