const { ethers } = require("hardhat");



async function main() {
  const accounts = await ethers.getSigners();

  // 1. Деплоим реализацию KingsVaultCardsV1
  const KingsVaultCardsV1Factory = await ethers.getContractFactory("KingsVaultCardsV1");
  const implementation = await KingsVaultCardsV1Factory.deploy();
  await implementation.deployed();
  console.log("KingsVaultCardsV1 (implementation) deployed to:", implementation.address);

  // 2. Кодируем вызов инициализатора
  const initialOwner = accounts[0];
  const vrfCoordinator = "";
  const initializerData = implementation.interface.encodeFunctionData("initialize", [
    initialOwner,
    vrfCoordinator,
  ]);

  // 3. Деплоим TransparentUpgradeableProxy
  //    ВАЖНО: ваша кастомная версия TUP внутри себя сама создаёт ProxyAdmin
  //    и ставит его администратором прокси.
  const TransparentUpgradeableProxyFactory = await ethers.getContractFactory("TransparentUpgradeableProxy");
  const proxy = await TransparentUpgradeableProxyFactory.deploy(
    implementation.address,
    initialOwner,
    initializerData
  );
  await proxy.deployed();
  console.log("TransparentUpgradeableProxy deployed to:", proxy.address);

  // 4. (Необязательно) Получаем интерфейс проксируемого контракта
  const proxied = await ethers.getContractAt("KingsVaultCardsV1", proxy.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
