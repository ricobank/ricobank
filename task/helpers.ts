import { b32, send } from 'minihat'
const dpack = require('@etherpacks/dpack')

export const createAndInitializePoolIfNecessary = async (
  env, factory, token0, token1, fee, sqrtPriceX96?
) => {
  if (token1 < token0) {
    let t1 = token1
    token1 = token0
    token0 = t1
    if (sqrtPriceX96) {
      // invert the price
      sqrtPriceX96 = env.ethers.BigNumber.from(2).pow(96).pow(2).div(sqrtPriceX96)
    }
  }
  let pooladdr = await factory.getPool(token0, token1, fee)

  if (pooladdr == env.ethers.constants.AddressZero) {
    await send(factory.createPool, token0, token1, fee, {gasLimit: env.gasLimit})
    pooladdr = await factory.getPool(token0, token1, fee)
    const uni_dapp = await dpack.load(
      env.uni_pack ?? env.unipackcid, env.ethers, env.ali
    )
    const pool_artifact = await dpack.getIpfsJson(
      uni_dapp._types.UniswapV3Pool.artifact['/']
    )
    const pool = await env.ethers.getContractAt(pool_artifact.abi, pooladdr, env.ali)
    await send(
      pool.initialize, sqrtPriceX96 ? sqrtPriceX96 : '0x1' + '0'.repeat(96/4),
      {gasLimit: env.gasLimit}
    );
  }

  return pooladdr
}

export const getDiamondArtifact = () => {
    const diamond_artifact = require('../artifacts/src/diamond.sol/BankDiamond.json')
    let top_artifact = require('../artifacts/hardhat-diamond-abi/HardhatDiamondABI.sol/BankDiamond.json')
    top_artifact.deployedBytecode = diamond_artifact.deployedBytecode
    top_artifact.bytecode = diamond_artifact.bytecode
    top_artifact.linkReferences = diamond_artifact.linkReferences
    top_artifact.deployedLinkReferences = diamond_artifact.deployedLinkReferences
    top_artifact.abi = top_artifact.abi.filter((item, idx) => {
        return top_artifact.abi.findIndex(a => item.name == a.name) == idx
    })

    return top_artifact
}
