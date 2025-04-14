const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("BoomFunProtocol and BoomFunToken", function () {
  let BoomFunProtocol, BoomFunToken, boomFunProtocol, boomFunToken;
  let owner, addr1, addr2;

  beforeEach(async function () {
    // Get contract factories and signers
    BoomFunToken = await ethers.getContractFactory("BoomFunToken");
    BoomFunProtocol = await ethers.getContractFactory("BoomFunProtocol");

    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

    // Deploy BoomFunToken contract
    boomFunToken = await BoomFunToken.deploy(
      "BoomFun Token",
      "BFT",
      ethers.utils.parseUnits("10000", 18),
      "A sample BoomFun token",
      owner.address
    );

    // Deploy BoomFunProtocol contract
    boomFunProtocol = await BoomFunProtocol.deploy();
  });

  it("Should create a new BoomFunToken correctly", async function () {
    expect(await boomFunToken.name()).to.equal("BoomFun Token");
    expect(await boomFunToken.symbol()).to.equal("BFT");
    expect(await boomFunToken.balanceOf(owner.address)).to.equal(
      ethers.utils.parseUnits("10000", 18)
    );
  });

  it("Should allow users to purchase tokens", async function () {
    const tokenId = 1;
    const initialSupply = ethers.utils.parseUnits("10000", 18);
    await boomFunProtocol.createToken("BoomFun Token", "BFT", initialSupply, "Sample description");

    const tokenInfo = await boomFunProtocol.tokens(tokenId);

    expect(tokenInfo.name).to.equal("BoomFun Token");
    expect(tokenInfo.symbol).to.equal("BFT");

    const purchaseAmount = ethers.utils.parseEther("1"); // User purchases with 1 ETH
    await boomFunProtocol.connect(addr1).purchaseTokenAMAP(tokenId, 0, { value: purchaseAmount });

    expect(await ethers.provider.getBalance(boomFunProtocol.address)).to.equal(purchaseAmount);
  });

  it("Should allow users to sell tokens", async function () {
    const tokenId = 1;
    const initialSupply = ethers.utils.parseUnits("10000", 18);
    await boomFunProtocol.createToken("BoomFun Token", "BFT", initialSupply, "Sample description");

    // First purchase some tokens
    const purchaseAmount = ethers.utils.parseEther("1");
    await boomFunProtocol.connect(addr1).purchaseTokenAMAP(tokenId, 0, { value: purchaseAmount });

    // Then sell some tokens
    const sellAmount = ethers.utils.parseUnits("10", 18); // Sell 10 tokens
    // First approve the contract to transfer tokens from user address
    await boomFunToken.connect(addr1).approve(boomFunProtocol.address, sellAmount);

    await boomFunProtocol.connect(addr1).sellToken(tokenId, sellAmount);

    // Check contract balance
    const contractBalance = await ethers.provider.getBalance(boomFunProtocol.address);
    expect(contractBalance).to.be.below(purchaseAmount);
  });
});
