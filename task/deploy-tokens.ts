import { task } from 'hardhat/config'
const debug = require('debug')('ricobank:task')
const dpack = require('@etherpacks/dpack')
import { b32, send } from 'minihat'
import { createAndInitializePoolIfNecessary } from './helpers'

task('deploy-tokens', '')
.addOptionalParam('tokens', 'JSON file with token addresses')
.addOptionalParam('gfpackcid', 'gemfab pack passed as cid cli string, alternative to gf_pack obj passed from another task')
.addOptionalParam('unipackcid', 'unipack passed as cid cli string, alternative to uni_pack obj passed from another task')
.addOptionalParam('outfile', 'output JSON file')
.addOptionalParam('mock', 'mock mode')
.addOptionalParam('gasLimit', 'per-tx gas limit')
.addOptionalParam('netname', 'network to read in tokens file')
.setAction(async (args, hre) => {
  debug('deploy tokens')

  const [ ali ]  = await hre.ethers.getSigners()

  let tokens : any = {}
  if (args.tokens) {
      const fromjson = require(args.tokens)[args.netname]
      if (fromjson) tokens = fromjson.erc20 ?? tokens
  }

  debug('deploy rico')
  const gf_dapp = await dpack.load(args.gf_pack ?? args.gfpackcid, hre.ethers, ali)
  let rico_addr = await gf_dapp.gemfab.callStatic.build(
    b32("Rico"), b32("RICO")
  );
  await send(gf_dapp.gemfab.build, b32("Rico"), b32("RICO"), {gasLimit: args.gasLimit})

  debug('deploy risk')
  let risk_addr
  if (args.risk) {
    // risk already deployed
    risk_addr = args.risk
  } else {
    risk_addr = await gf_dapp.gemfab.callStatic.build(
      b32("Rico Riskshare"), b32("RISK")
    )
    await send(gf_dapp.gemfab.build, b32("Rico Riskshare"), b32("RISK"), {gasLimit: args.gasLimit})
  }

  debug('create rico-risk pool')
  const uni_dapp = await dpack.load(args.uni_pack ?? args.unipackcid, hre.ethers, ali)
  let t0; let t1;
  ;[t0, t1] = [rico_addr, risk_addr]
  const unipackcid = args.unipackcid
  const uni_pack = args.uni_pack
  const ricorisk_addr = await createAndInitializePoolIfNecessary(
    {ali, ethers: hre.ethers, gasLimit: args.gasLimit, unipackcid, uni_pack },
    uni_dapp.uniswapV3Factory, t0, t1, 3000
  )

  let dai_addr
  if (args.mock) {
    // build a fake Dai
    dai_addr = await gf_dapp.gemfab.callStatic.build(
      b32("Dai Stablecoin"), b32("DAI")
    )
    await send(
      gf_dapp.gemfab.build, b32("Dai Stablecoin"), b32("DAI"),
      {gasLimit: args.gasLimit}
    )
  } else {
    dai_addr = tokens.dai.gem
  }

  ;[t0, t1] = [rico_addr, dai_addr]
  // rico:dai ~2k
  const ricodai_addr = await createAndInitializePoolIfNecessary(
    { ali, ethers: hre.ethers, gasLimit: args.gasLimit, unipackcid, uni_pack},
    uni_dapp.uniswapV3Factory, t0, t1, 500, '0x2D000000000000000000000000'
  )

  // pack the system-required pools and tokens
  const pb = new dpack.PackBuilder(hre.network.name)
  const gem_artifact = await dpack.getIpfsJson(gf_dapp._types.Gem.artifact['/'])
  const pool_artifact = await dpack.getIpfsJson(uni_dapp._types.UniswapV3Pool.artifact['/'])
  await pb.packObject({
    objectname: 'rico',
    typename: 'Gem',
    artifact: gem_artifact,
    address: rico_addr
  }, false)
  await pb.packObject({
    objectname: 'risk',
    typename: 'Gem',
    artifact: gem_artifact,
    address: risk_addr
  }, false)
  await pb.packObject({
    objectname: 'dai',
    typename: 'Gem',
    artifact: gem_artifact,
    address: dai_addr
  }, false)
  await pb.packObject({
    objectname: 'ricorisk',
    typename: 'UniswapV3Pool',
    artifact: pool_artifact,
    address: ricorisk_addr
  }, false)
  await pb.packObject({
    objectname: 'ricodai',
    typename: 'UniswapV3Pool',
    artifact: pool_artifact,
    address: ricodai_addr
  }, false)

  for (let tokenname in tokens) {

    // get or build the token unless it's dai
    let token      = tokens[tokenname]
    if ('dai' == tokenname) continue;

    let token_addr
    if (args.mock) {
      // build a fake token
      token_addr = await gf_dapp.gemfab.callStatic.build(
        b32(tokenname), b32(tokenname.toUpperCase())
      )
      await send(gf_dapp.gemfab.build,
        b32(tokenname), b32(tokenname.toUpperCase())
      )
    } else {
      token_addr = token.gem
    }

    // pack it
    await pb.packObject({
      objectname: tokenname,
      typename: 'Gem',
      artifact: gem_artifact,
      address: token_addr
    }, false)
  }

  const pack = await pb.build()
  const str = JSON.stringify(pack, null, 2)
  if (args.stdout) {
      console.log(str)
  }
  if (args.outfile) {
      require('fs').writeFileSync(args.outfile, str)
  }
  return pack
})
