import { task } from 'hardhat/config'
const debug = require('debug')('ricobank:task')
const dpack = require('@etherpacks/dpack')
import { b32, send } from 'minihat'
const GASLIMIT = '1000000000000'



task('deploy-mock-tokens', '')
.addOptionalParam('tokens', 'JSON file with token addresses')
.addOptionalParam('outfile', 'output JSON file')
.setAction(async (args, hre) => {
  debug('deploy tokens')

  const [ signer ]  = await hre.ethers.getSigners()
  const createAndInitializePoolIfNecessary = async (factory, token0, token1, fee, sqrtPriceX96?) => {
    if (token1 < token0) {
      let t1 = token1
      token1 = token0
      token0 = t1
    }
    let pooladdr = await factory.getPool(token0, token1, fee)

    if (pooladdr == hre.ethers.constants.AddressZero) {
      await send(factory.createPool, token0, token1, fee, {gasLimit: GASLIMIT})
      pooladdr = await factory.getPool(token0, token1, fee)
      const uni_dapp = await dpack.load(args.uni_pack, hre.ethers, signer)
      const pool_artifact = await dpack.getIpfsJson(uni_dapp._types.UniswapV3Pool.artifact['/'])
      const pool = await hre.ethers.getContractAt(pool_artifact.abi, pooladdr, signer)
      await send(pool.initialize, sqrtPriceX96 ? sqrtPriceX96 : '0x1' + '0'.repeat(96/4), {gasLimit: GASLIMIT});
    }

    return pooladdr
  }

  let tokens : any = {}
  if (args.tokens) {
      const fromjson = require(args.tokens)[args.netname]
      if (fromjson) tokens = fromjson
  }

  debug('deploy rico')
  const gf_dapp = await dpack.load(args.gf_pack, hre.ethers, signer)
  let rico_addr
  if (tokens.rico && tokens.rico.gem) {
    rico_addr = tokens.rico.gem
  } else {
    rico_addr = await gf_dapp.gemfab.callStatic.build(
      b32("Rico"), b32("RICO")
    );
    await send(gf_dapp.gemfab.build, b32("Rico"), b32("RICO"))
  }

  debug('deploy risk')
  let risk_addr
  if (tokens.risk && tokens.risk.gem) {
    risk_addr = tokens.risk.gem
  } else {
    risk_addr = await gf_dapp.gemfab.callStatic.build(
      b32("Rico Riskshare"), b32("RISK")
    )
    await send(gf_dapp.gemfab.build, b32("Rico Riskshare"), b32("RISK"))
  }

  const uni_dapp = await dpack.load(args.uni_pack, hre.ethers, signer)
  let t0; let t1;
  ;[t0, t1] = [rico_addr, risk_addr]
  const ricorisk_addr = await createAndInitializePoolIfNecessary(uni_dapp.uniswapV3Factory, t0, t1, 3000)

  let dai_addr
  if (tokens.dai && tokens.dai.gem) {
    dai_addr = tokens.dai.gem
  } else {
    dai_addr = await gf_dapp.gemfab.callStatic.build(
      b32("Dai Stablecoin"), b32("DAI")
    )
    await send(gf_dapp.gemfab.build, b32("Dai Stablecoin"), b32("DAI"))
  }
  ;[t0, t1] = [rico_addr, dai_addr]
  const ricodai_addr = await createAndInitializePoolIfNecessary(uni_dapp.uniswapV3Factory, t0, t1, 500)

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

  debug('deploy pools')
  let tokensPlusWeth = JSON.parse(JSON.stringify(tokens))
  if (args.weth) tokensPlusWeth.weth.gem = args.weth
  for (let tokenname in tokensPlusWeth) {
    if ('dai' == tokenname) continue;
    let token = tokensPlusWeth[tokenname]
    let token_addr = token.gem
    if (!token_addr) token_addr = await gf_dapp.gemfab.callStatic.build(
      b32(tokenname), b32(tokenname.toUpperCase())
    )

    ;[t0, t1] = [token_addr, dai_addr]
    let sqrtPriceX96 = '0x20' + '0'.repeat(96/4) // weth/dai price 1024
    if (hre.ethers.BigNumber.from(t1).lt(hre.ethers.BigNumber.from(t0))) {
        sqrtPriceX96 = '0x08' + '0'.repeat(96/4-2) // 1/1024
    }

    const tokendai_addr = await createAndInitializePoolIfNecessary(
        uni_dapp.uniswapV3Factory, t0, t1, 500, sqrtPriceX96
    )

    await pb.packObject({
      objectname: tokenname,
      typename: 'Gem',
      artifact: gem_artifact,
      address: token_addr
    }, false)

    await pb.packObject({
      objectname: tokenname+'dai',
      typename: 'UniswapV3Pool',
      artifact: pool_artifact,
      address: tokendai_addr
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
