import { task } from 'hardhat/config'
const debug = require('debug')('ricobank:task')
const dpack = require('@etherpacks/dpack')
import { b32, send } from 'minihat'

task('deploy-mock-tokens', '')
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
  const createAndInitializePoolIfNecessary = async (
    factory, token0, token1, fee, sqrtPriceX96?
  ) => {
    if (token1 < token0) {
      let t1 = token1
      token1 = token0
      token0 = t1
    }
    let pooladdr = await factory.getPool(token0, token1, fee)

    if (pooladdr == hre.ethers.constants.AddressZero) {
      await send(factory.createPool, token0, token1, fee, {gasLimit: args.gasLimit})
      pooladdr = await factory.getPool(token0, token1, fee)
      const uni_dapp = await dpack.load(
        args.uni_pack ?? args.unipackcid, hre.ethers, ali
      )
      const pool_artifact = await dpack.getIpfsJson(
        uni_dapp._types.UniswapV3Pool.artifact['/']
      )
      const pool = await hre.ethers.getContractAt(pool_artifact.abi, pooladdr, ali)
      await send(
        pool.initialize, sqrtPriceX96 ? sqrtPriceX96 : '0x1' + '0'.repeat(96/4),
        {gasLimit: args.gasLimit}
      );
    }

    return pooladdr
  }

  let tokens : any = {}
  if (args.tokens) {
      const fromjson = require(args.tokens)[args.netname]
      if (fromjson) tokens = fromjson
  }

  debug('deploy rico')
  const gf_dapp = await dpack.load(args.gf_pack ?? args.gfpackcid, hre.ethers, ali)
  let rico_addr
  if (tokens.rico && tokens.rico.gem) {
    rico_addr = tokens.rico.gem
  } else {
    rico_addr = await gf_dapp.gemfab.callStatic.build(
      b32("Rico"), b32("RICO")
    );
    await send(gf_dapp.gemfab.build, b32("Rico"), b32("RICO"), {gasLimit: args.gasLimit})
  }

  debug('deploy risk')
  let risk_addr
  if (tokens.risk && tokens.risk.gem) {
    risk_addr = tokens.risk.gem
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
  const ricorisk_addr = await createAndInitializePoolIfNecessary(uni_dapp.uniswapV3Factory, t0, t1, 3000)

  let dai_addr = tokens.dai ? tokens.dai.gem : undefined
  if (!dai_addr) {
    if (!args.mock) {
      throw new Error("No Dai address supplied, but not in mock mode")
    }

    // build a fake Dai
    dai_addr = await gf_dapp.gemfab.callStatic.build(
      b32("Dai Stablecoin"), b32("DAI")
    )
    await send(
      gf_dapp.gemfab.build, b32("Dai Stablecoin"), b32("DAI"),
      {gasLimit: args.gasLimit}
    )
  }

  ;[t0, t1] = [rico_addr, dai_addr]
  // rico:dai ~2k
  const ricodai_addr = await createAndInitializePoolIfNecessary(
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

  // in case a previous task built a new weth
  let tokensPlusWeth = JSON.parse(JSON.stringify(tokens))
  if (args.weth) tokensPlusWeth.weth.gem = args.weth

  for (let tokenname in tokensPlusWeth) {

    // get or build the token unless it's dai
    let token      = tokensPlusWeth[tokenname]
    if ('dai' == tokenname || token.hook != 'erc20') continue;

    let token_addr = token.gem
    if (!token_addr) {
      if (!args.mock) {
        throw new Error(`No ${tokenname} address supplied, but not in mock mode`)
      }

      // build a fake token
      token_addr = await gf_dapp.gemfab.callStatic.build(
        b32(tokenname), b32(tokenname.toUpperCase())
      )
      await send(gf_dapp.gemfab.build,
        b32(tokenname), b32(tokenname.toUpperCase())
      )
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
