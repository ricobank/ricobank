import { expect as want } from 'chai'

import { ethers, artifacts, network } from 'hardhat'

import { wad, ray, send } from './helpers'
const debug = require('debug')('rico:test')

const ZERO = Buffer.alloc(32)
const ADDRZERO = '0x' + '00'.repeat(20)
const i0 = ZERO // ilk 0 id

const TAG = Buffer.from('feed'.repeat(16), 'hex')

describe('plot vat ilk mark via plotter', () => {
  let ali, bob, cat
  let ALI, BOB, CAT
  let vat; let vat_type
  let plotter; let plotter_type
  let fb_deployer; let fb
  before(async () => {
    [ali, bob, cat] = await ethers.getSigners();
    [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)
    vat_type = await ethers.getContractFactory('./src/vat.sol:Vat', ali)
    plotter_type = await ethers.getContractFactory('./src/plot.sol:Plotter', ali)
    const fb_artifacts = require('../lib/feedbase/artifacts/contracts/Feedbase.sol/Feedbase.json')
    fb_deployer = ethers.ContractFactory.fromSolidity(fb_artifacts, ali)
  })
  beforeEach(async () => {
    vat = await vat_type.deploy()
    plotter = await plotter_type.deploy()
    fb = await fb_deployer.deploy()
    // fb = await fbpack.dapp.types.Feedbase.deploy();

    await send(vat.rely, plotter.address)

    await send(plotter.file_fb, fb.address)
    await send(plotter.file_vat, vat.address)

    await send(plotter.wire, i0, ALI, TAG)
  })

  it('plot mark', async () => {
    const p = Buffer.from(wad(1200).toHexString().slice(2).padStart(64, '0'), 'hex')
    await send(fb.push, TAG, p, 10 ** 10, ADDRZERO)
    await send(plotter.poke, i0)

    const [,,mark0] = await vat.ilks(i0)
    want(mark0.eq(ray(1200))).true // upcast to ray by plotter
  })
})
