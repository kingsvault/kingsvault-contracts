import { expect } from "chai";
import hre from "hardhat";



describe("TestErc20", function () {
  it("USDT 18", async function () {
    const name = "USDT 18";
    const symbol = "USDT";
    const decimals = 18;
    const initialSupply = hre.ethers.parseUnits("100000000", decimals);
    const usdt = await hre.ethers.deployContract(
      "TestErc20",
      [name, symbol, decimals, initialSupply],
      {}
    );

    // assert that the value is correct
    expect(await usdt.totalSupply()).to.equal(initialSupply);
  });
});
