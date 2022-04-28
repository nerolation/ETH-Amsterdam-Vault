import { ethers } from "hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  try {
    const { deploy } = hre.deployments;
    const { deployer } = await hre.getNamedAccounts();
    const doLogging = true;

    const currentTimestamp = (await ethers.provider.getBlock("latest")).timestamp;

    await deploy("JointVaultStrategy", {
      from: deployer,
      log: doLogging,
      args: [
        '0x5FC8d32690cc91D4c39d9d3abcBD16989F875707', // aToken
        '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9', // underlyingToken
        '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0', // factory
        '0x5392A33F7F677f59e833FEBF4016cDDD88fF9E67', // starting fcm
        '0x75537828f2ce51be7289709686A69CbFDbB714F1', // starting marginEngine
        '0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9', // mock aave
        {
          start: currentTimestamp,
          end: currentTimestamp + 86400,
        },
      ],
    });

    return true; // Only execute once
  } catch (e) {
    console.error(e);
    throw e;
  }
};
func.tags = ["VaultStrategy"];
func.id = "VaultStrategy";
export default func;
