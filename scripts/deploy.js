async function main() {
    // Get the contract factory for BoomFunProtocol
    const BoomFunProtocol = await ethers.getContractFactory("BoomFunProtocol");
  
    // Deploy the contract
    const boomFunProtocol = await BoomFunProtocol.deploy();
  
    // Wait for the contract to be deployed (mined)
    await boomFunProtocol.deployTransaction.wait();
  
    // Output the deployed contract address
    console.log("BoomFunProtocol deployed to:", boomFunProtocol.address);
  }
  
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
  