const { ethers, upgrades } = require("hardhat");


// "https://kingsvault.github.io/metadata/"
async function main() {
  const KingsVaultV1 = await ethers.getContractFactory("KingsVaultV1");
  const kingsVaultV1 = await upgrades.deployProxy(KingsVaultV1, [
    process.env.USDT_ADDRESS,
    process.env.TREASURY_ADDRESS,
    process.env.CHAINLINK_VRF_COORDINATOR,
    process.env.CHAINLINK_KEY_HASH,
    process.env.CHAINLINK_SUBSCRIPTION_ID
  ], { initializer: "initialize" });

  await kingsVaultV1.deployed();
  console.log("KingsVaultV1 deployed to:", kingsVaultV1.address);
}


main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
