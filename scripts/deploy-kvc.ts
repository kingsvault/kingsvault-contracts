import hre from "hardhat";
import fs from "node:fs";

const { ethers, network } = hre;


//https://docs.chain.link/vrf/v2/subscription/supported-networks
const vrfCoordinators = {
  "bsc": "0xc587d9053cd1118f25F645F9E08BB98c9712A4EE",
  "bscTestnet": "0x6A2AAd07396B36Fe02a22b33cf443582f682c82f",
}

async function main() {
  const accounts = await ethers.getSigners();

  // 1. Деплоим реализацию KingsVaultCardsV1
  const KingsVaultCardsV1Factory = await ethers.getContractFactory("KingsVaultCardsV1");
  const implementation = await KingsVaultCardsV1Factory.deploy();
  await implementation.waitForDeployment();
  console.log("KingsVaultCardsV1 (implementation) deployed to:", implementation.target);

  // 2. Кодируем вызов инициализатора
  const initialOwner = accounts[0].address;
  // @ts-expect-error
  const vrfCoordinator = vrfCoordinators[network.name];
  const initializerData = implementation.interface.encodeFunctionData("initialize", [
    initialOwner,
    vrfCoordinator,
  ]);

  // 3. Деплоим TransparentUpgradeableProxy
  const TransparentUpgradeableProxyFactory = await ethers.getContractFactory("TransparentUpgradeableProxy");
  const proxy = await TransparentUpgradeableProxyFactory.deploy(
    implementation.target,
    initialOwner,
    initializerData
  );
  await proxy.waitForDeployment();
  console.log("TransparentUpgradeableProxy deployed to:", proxy.target);

  // 4. (Необязательно) Получаем интерфейс проксируемого контракта
  const proxied = await ethers.getContractAt("KingsVaultCardsV1", proxy.target);
  const proxyInfo = await proxied.proxy();
  console.log("proxyInfo", proxyInfo);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
