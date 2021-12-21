import * as hh from 'hardhat'
import { ethers } from 'hardhat'
import { fail, rad, ray, revert, send, snapshot, U256_MAX, wad, want } from 'minihat'
import { b32 } from './helpers'

const debug = require('debug')('rico:test')

let i0 = Buffer.alloc(32, 1)  // ilk 0 id

describe('Plug', () => {
    let ali, bob, cat
    let ALI, BOB, CAT
    let vat, vat_type
    let join, join_type
    let plug, plug_type
    let RICO, gemA
    let gem_type
    before(async () => {
        [ali, bob, cat] = await ethers.getSigners();
        [ALI, BOB, CAT] = [ali, bob, cat].map(signer => signer.address)
        vat_type = await ethers.getContractFactory('Vat', ali)
        const gem_artifacts = require('../lib/gemfab/artifacts/sol/gem.sol/Gem.json')
        gem_type = ethers.ContractFactory.fromSolidity(gem_artifacts, ali)
        join_type = await ethers.getContractFactory('Join', ali)
        plug_type = await ethers.getContractFactory('Plug', ali)

        vat = await vat_type.deploy()
        RICO = await gem_type.deploy('Rico', 'RICO')
        gemA = await gem_type.deploy('gemA', 'GEMA')
        join = await join_type.deploy()
        plug = await plug_type.deploy()

        await send(vat.hope, plug.address)
        await send(RICO.ward, plug.address, true)
        await send(vat.rely, join.address)
        await send(gemA.approve, join.address, U256_MAX)
        await send(RICO.mint, ALI, wad(10))
        await send(gemA.mint, ALI, wad(1000))
        await send(vat.init, i0)
        await send(vat.file, b32("ceil"), rad(1000))
        await send(vat.filk, i0, b32("line"), rad(2000))
        await send(vat.plot, i0, ray(1).toString())
        await send(join.bind, vat.address, i0, gemA.address)
        await send(plug.bind, vat.address, RICO.address, true)
        await send(join.join, vat.address, i0, ALI, wad(1000))

        await snapshot(hh);
    })
    beforeEach(async () => {
        await revert(hh);
    })

    describe('join and exit', () => {
        it('joy', async () => {
            const ricoWad = wad(10)
            const initialRico = await RICO.balanceOf(ALI)

            await send(vat.lock, i0, wad(500))
            await send(vat.draw, i0, ricoWad)

            await fail('operation underflowed', plug.exit, vat.address, RICO.address, ALI, wad(11))
            await send(plug.exit, vat.address, RICO.address, ALI, ricoWad)
            await fail('operation underflowed', plug.exit, vat.address, RICO.address, ALI, wad(1))
            const postExitRico = await RICO.balanceOf(ALI)

            want(postExitRico.sub(initialRico).toString()).equals(ricoWad.toString())

            await fail('operation underflowed', plug.join, vat.address, RICO.address, ALI, wad(11))
            await send(plug.join, vat.address, RICO.address, ALI, ricoWad)
            await fail('operation underflowed', plug.join, vat.address, RICO.address, ALI, wad(1))
            const postJoinRico = await RICO.balanceOf(ALI)

            want(postJoinRico.toString()).equals(initialRico.toString())
        });
    })

    describe('rico flash loan', () => {
    })
})
