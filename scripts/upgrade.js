const { ethers, upgrades } = require("hardhat");



async function main() {
  const nftSaleAddress = "YOUR_CONTRACT_ADDRESS";
  const KingsVaultV2 = await ethers.getContractFactory("KingsVaultV2");
  const kingsVaultV2 = await upgrades.upgradeProxy(nftSaleAddress, KingsVaultV2);

  console.log("KingsVaultV2 upgraded at:", kingsVaultV2.address);
}


main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
