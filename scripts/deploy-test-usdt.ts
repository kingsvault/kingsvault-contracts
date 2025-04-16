import hre from "hardhat";
import fs from "node:fs";
import { pause } from "./lib/pause";

const { ethers, network } = hre;


async function main() {
  const accounts = await ethers.getSigners();

  // 1. Получаем фабрику контракта TestErc20
  const TestErc20Factory = await ethers.getContractFactory("TestErc20");

  // 2. Задаём параметры для конструктора
  //    Подставьте свои значения: имя, символ и начальный запас токенов
  const name = "USDT 18";
  const symbol = "USDT";
  const decimals = 18;
  const initialSupply = ethers.parseUnits("100000000", decimals);

  // 3. Деплоим контракт, передавая аргументы в конструктор
  const testErc20 = await TestErc20Factory.deploy(name, symbol, decimals, initialSupply);
  await testErc20.waitForDeployment();

  console.log(`testErc20`, await testErc20.balanceOf(accounts[0].address));
  console.log(`TestErc20 deployed to: ${testErc20.target}`);

  fs.writeFileSync(`./scripts/config.${network.name}.usdt_address.txt`, testErc20.target.toString(), { encoding: "utf8", });

  await pause(10 * 1000);
  await hre.run("verify:verify", {
    address: testErc20.target,
    constructorArguments: [name, symbol, decimals, initialSupply],
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
