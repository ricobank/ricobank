const debug = require('debug')('ricobank:task')

import { task } from 'hardhat/config'
const dpack = require('@etherpacks/dpack')

task('deploy-dependencies', '')
.addOptionalParam('gasLimit', 'per-tx gas limit')
.addOptionalParam('ipfs', 'add packs to ipfs')
.addOptionalParam('mock', 'mock mode')
.setAction(async (args, hre) => {
  debug('deploying dependencies...')

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
          mock: args.mock,
          gasLimit: args.gasLimit,
          mint: args.mint
      }
  )
  debug('deployed (or loaded) tokens')

  const pb = new dpack.PackBuilder(hre.network.name)
  await pb.merge(gf_pack, tokens_pack);

  const pack = await pb.build();
  pack.network = hre.network.name

  if (args.ipfs) {
    console.log("deploy-dependencies IPFS CIDs:")
    let cid = await dpack.putIpfsJson(gf_pack, true)
    console.log(`  GemFab: ${cid}`)
    cid = await dpack.putIpfsJson(tokens_pack, true)
    console.log(`  Tokens: ${cid}`)
    cid = await dpack.putIpfsJson(pack, true)
    console.log(`  Dependencies: ${cid}`)
  }

  return pack
});
