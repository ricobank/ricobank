const debug = require('debug')('ricobank:task')

import { task } from 'hardhat/config'
const dpack = require('@etherpacks/dpack')

task('deploy-dependencies', '')
.addOptionalParam('gasLimit', 'per-tx gas limit')
.addOptionalParam('ipfs', 'add packs to ipfs')
.addOptionalParam('mock', 'mock mode')
.setAction(async (args, hre) => {
  debug('deploying dependencies...')

  let uni_pack
  if (args.unipackcid) {
    uni_pack = await dpack.getIpfsJson(args.unipackcid)
  } else {
    uni_pack = require(`../lib/uniswapv3/pack/uniswapv3_${args.netname}.dpack.json`)
  }
  uni_pack.network = hre.network.name
  debug('found uni pack')

  const fb_pack = await hre.run('deploy-feedbase', {netname: args.netname})
  debug('deployed fb')

  let gf_pack
  if (args.gfpackcid) {
    gf_pack = await dpack.getIpfsJson(args.gfpackcid)
  } else {
    gf_pack = await hre.run(
      'deploy-gemfab', {netname: args.netname, gasLimit: args.gasLimit}
    )
    debug(`deployed gf`)
  }

  const tokens_pack = await hre.run(
      'deploy-tokens',
      {
          gf_pack: gf_pack,
          gfpackcid: args.gfpackcid,
          risk: args.risk,
          uni_pack: uni_pack,
          tokens: args.tokens,
          netname: args.netname,
          mock: args.mock,
          gasLimit: args.gasLimit
      }
  )
  debug('deployed (or loaded) tokens')

  const pb = new dpack.PackBuilder(hre.network.name)
  await pb.merge(uni_pack, fb_pack, gf_pack, tokens_pack);

  const pack = await pb.build();
  pack.network = hre.network.name

  if (args.ipfs) {
    console.log("deploy-dependencies IPFS CIDs:")
    let cid = await dpack.putIpfsJson(gf_pack, true)
    console.log(`  GemFab: ${cid}`)
    cid = await dpack.putIpfsJson(fb_pack, true)
    console.log(`  Feedbase: ${cid}`)
    cid = await dpack.putIpfsJson(uni_pack, true)
    console.log(`  UniswapV3: ${cid}`)
    cid = await dpack.putIpfsJson(tokens_pack, true)
    console.log(`  Tokens: ${cid}`)
    cid = await dpack.putIpfsJson(pack, true)
    console.log(`  Dependencies: ${cid}`)
  }

  return pack
});
