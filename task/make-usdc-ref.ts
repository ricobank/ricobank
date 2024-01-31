import { task } from 'hardhat/config'

const debug = require('debug')('ricobank:task')
const dpack = require('@etherpacks/dpack')
import { b32, ray, rad, send, wad, BANKYEAR } from 'minihat'
import { createAndInitializePoolIfNecessary } from './createAndInitializePoolIfNecessary'



task('make-usdc-ref', '')
  .addParam('rbpackcid', 'ricobank pack ipfs cid')
  .addParam('aggpackcid', 'chainlink aggregator pack ipfs cid')
  .addParam('unipackcid', 'uniswapv3 pack ipfs cid')
  .addOptionalParam('rmdai', 'remove dai and rico:dai pool')
  .addOptionalParam('writepack', 'write pack to pack dir')
  .addOptionalParam('gasLimit', 'per-tx gas limit')
  .addOptionalParam('ipfs', 'add packs to ipfs')
  .setAction(async (args, hre) => {
    debug('network name in task:', hre.network.name)
    const ethers    = hre.ethers
    const BN        = ethers.BigNumber
    const constants = ethers.constants

    const [ali]  = await ethers.getSigners()
    const bn2b32 = (bn) => ethers.utils.hexZeroPad(bn.toHexString(), 32)


    const rbpack = await dpack.getIpfsJson(args.rbpackcid)
    const dapp = await dpack.load(rbpack, ethers, ali)

    const aggdapp = await dpack.load(args.aggpackcid, ethers, ali)

    if (!dapp.usdc) {
      throw new Error('no usdc found in ricobank pack')
    }

    debug('pack rico:usdc pool')
    const rico = dapp.rico
    const usdc = dapp.usdc
    const pooladdr = await createAndInitializePoolIfNecessary(
      { ali, ethers, gasLimit: args.gasLimit, unipackcid: args.unipackcid },
      dapp.uniswapV3Factory, rico.address, usdc.address,
      500, '0x2AA64CF000000000000000000000000'
    )

    if (pooladdr === constants.AddressZero) {
      throw new Error('no rico:usdc pool found')
    }

    const ricousdc = dapp._types.UniswapV3Pool.attach(pooladdr)
    const pb = new dpack.PackBuilder(hre.network.name)
    await pb.packObject({
      objectname: 'ricousdc',
      address: ricousdc.address,
      typename: 'UniswapV3Pool',
      artifact: await dpack.getIpfsJson(rbpack.types.UniswapV3Pool.artifact['/'])
    }, false)

    debug('set uni adapter config')
    const uniadapt = dapp.uniswapv3adapter
    let config = await uniadapt.getConfig(b32('rico:dai'))
    await send(
      uniadapt.setConfig,
      b32('rico:usdc'),
      [pooladdr, usdc.address < rico.address, config.range, config.ttl]
    )

    debug('set chainlink adapter config')
    const cladapt = dapp.chainlinkadapter
    config = await cladapt.getConfig(b32('dai:usd'))
    await send(
      cladapt.setConfig,
      b32('usdc:usd'),
      [aggdapp.agg_usdc_usd.address, config.ttl]
    )

    debug('set multiplier config')
    const multiplier = dapp.multiplier
    await send(
      multiplier.setConfig,
      b32('rico:usd'),
      [[cladapt.address, uniadapt.address],
      [b32('usdc:usd'), b32('rico:usdc')]]
    )

    debug('set divider config')
    const divider = dapp.divider
    await send(
      divider.setConfig,
      b32('rico:ref'),
      [[multiplier.address, cladapt.address, dapp.ball.address],
      [b32('rico:usd'), b32('xau:usd'), bn2b32(BN.from(10).pow(27 + 12))]]
    )

    if (args.rmdai) {
      delete rbpack.objects.dai
      delete rbpack.objects.ricodai
    }

    await pb.merge(rbpack)

    if (args.ipfs) {
      const cid = await dpack.putIpfsJson(await pb.build(), true)
      console.log("swapped in usdc ref, pack CID:", cid)
    }

    return pb.build()
  })
