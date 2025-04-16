import hre from "hardhat";
import fs from "node:fs";
import { pause } from "./lib/pause";

const { ethers, network } = hre;


//https://docs.chain.link/vrf/v2/subscription/supported-networks
const vrfCoordinators = {
  "mainnet": "0x271682DEB8C4E0901D1a1550aD2e64D568E69909",
  "sepolia": "0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625",
  "bsc": "0xc587d9053cd1118f25F645F9E08BB98c9712A4EE",
  "bscTestnet": "0x6A2AAd07396B36Fe02a22b33cf443582f682c82f",
};
const linkTokens = {
  "mainnet": "0x514910771AF9Ca656af840dff83E8264EcF986CA",
  "sepolia": "0x779877A7B0D9E8603169DdbD7836e478b4624789",
  "bsc": "0x404460C6A5EdE2D891e8297795264fDe62ADBB75",
  "bscTestnet": "0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06",
};


const usdtTokens = {
  "mainnet": "!", //"0xdAC17F958D2ee523a2206206994597C13D831ec7", // 6 decimals
  "sepolia": fs.readFileSync(`./scripts/config.sepolia.usdt_address.txt`, { encoding: "utf8", }),// 18 decimals
  "bsc": "0x55d398326f99059fF775485246999027B3197955", // 18 decimals
  "bscTestnet": fs.readFileSync(`./scripts/config.bscTestnet.usdt_address.txt`, { encoding: "utf8", }), // 18 decimals
};
const teamWallets = {
  "mainnet": "!",
  "sepolia": "replaced",
  "bsc": "!",
  "bscTestnet": "replaced",
};


async function main() {
  const accounts = await ethers.getSigners();

  teamWallets["sepolia"] = accounts[1].address;
  teamWallets["bscTestnet"] = accounts[1].address;


  // 1. Деплоим реализацию KingsVaultCardsV1
  const KingsVaultCardsV1Factory = await ethers.getContractFactory("KingsVaultCardsV1");
  const implementation = await KingsVaultCardsV1Factory.deploy();
  await implementation.waitForDeployment();
  console.log("KingsVaultCardsV1 (implementation) deployed to:", implementation.target);


  // 2. Кодируем вызов инициализатора
  const initialOwner = accounts[0].address;
  // @ts-expect-error
  const vrfCoordinator = vrfCoordinators[network.name];
  // @ts-expect-error
  const linkToken = linkTokens[network.name];
  // @ts-expect-error
  const usdt = usdtTokens[network.name];
  // @ts-expect-error
  const teamWallet = teamWallets[network.name];
  const initializerData = implementation.interface.encodeFunctionData("initialize", [
    initialOwner,
    usdt,
    teamWallet,
    vrfCoordinator,
    linkToken,
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


  fs.writeFileSync(`./scripts/config.${network.name}.proxy_upgradeable_address.txt`, proxied.target.toString(), { encoding: "utf8", });
  fs.writeFileSync(`./scripts/config.${network.name}.proxy_implementation_address.txt`, implementation.target.toString(), { encoding: "utf8", });
  fs.writeFileSync(`./scripts/config.${network.name}.proxy_admin_address.txt`, proxyInfo.admin, { encoding: "utf8", });


  await pause(10 * 1000);
  await hre.run("verify:verify", {
    address: implementation.target,
    constructorArguments: [],
  });


  await hre.run("verify:verify", {
    address: proxy.target,
    constructorArguments: [
      implementation.target,
      initialOwner,
      initializerData
    ],
  });


  await hre.run("verify:verify", {
    address: proxyInfo.admin,
    constructorArguments: [initialOwner],
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
