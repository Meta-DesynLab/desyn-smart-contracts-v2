
const hre = require("hardhat");
const run=hre.run;
const ethers=hre.ethers;
async function main() {
        //compile
        await run("compile");
        //accounts
        const accounts = await ethers.getSigners();
        //deploy Vault
        const Vault = await hre.ethers.getContractFactory("Vault");
        const vault = await Vault.deploy();
        await vault.deployed();
        console.log("vault deployed to:", vault.address);
     // vault: 0x57236021d6c214e9e71E47db24D75Ef9B7e05464
     //  deploy DSProxyFactory
        const DSProxyFactory = await hre.ethers.getContractFactory("DSProxyFactory");
        const dSProxyFactory = await DSProxyFactory.deploy();
        await dSProxyFactory.deployed();
        console.log("dSProxyFactory deployed to:", dSProxyFactory.address);
        //deploy ProxyRegistry
        const ProxyRegistry = await hre.ethers.getContractFactory("ProxyRegistry");
        const proxyRegistry = await ProxyRegistry.deploy(dSProxyFactory.address);
        await proxyRegistry.deployed();
        console.log("proxyRegistry deployed to:", proxyRegistry.address);
        //deploy Actions
        const Actions = await hre.ethers.getContractFactory("Actions");
        const actions = await Actions.deploy();
        await actions.deployed();
        console.log("actions deployed to:", actions.address);
      //  deploy DesynSafeMath
        const DesynSafeMath = await hre.ethers.getContractFactory("DesynSafeMath");
        const desynSafeMath = await DesynSafeMath.deploy();
        await desynSafeMath.deployed();
        console.log("desynSafeMath deployed to:", desynSafeMath.address);
        //deploy RightsManager
        const RightsManager = await hre.ethers.getContractFactory("RightsManager");
        const rightsManager = await RightsManager.deploy();
        await rightsManager.deployed();
        console.log("rightsManager deployed to:", rightsManager.address);
        //deploy SmartPoolManager
        const SmartPoolManager = await hre.ethers.getContractFactory("SmartPoolManager");
        const smartPoolManager = await SmartPoolManager.deploy();
        await smartPoolManager.deployed();
        console.log("smartPoolManager deployed to:", smartPoolManager.address);
        //deploy CRPFactory
        const CRPFactory = await hre.ethers.getContractFactory("CRPFactory",{
            libraries:{
                DesynSafeMath:desynSafeMath.address,
                RightsManager:rightsManager.address,
                SmartPoolManager:smartPoolManager.address
                // DesynSafeMath:"0xee95d788Db17C3FdC4D4F6Bf1652aefEe034B77a",
                // RightsManager:"0x6052deFd2f64A4f0A7424ABEC9a1dbEF092FD3c0",
                // SmartPoolManager:"0x520E344dDc67F536215c17F1CB333238A15e27C4"
            }
        });
        const cRPFactory = await CRPFactory.deploy();
        await cRPFactory.deployed();
        console.log("cRPFactory deployed to:", cRPFactory.address);
        //deploy BFactory
        const Factory = await hre.ethers.getContractFactory("Factory");
        const bfactory = await Factory.deploy();
        await bfactory.deployed();
        console.log("bfactory deployed to:", bfactory.address);
      //   await bfactory.setVault("0xF10473e8edEe939d1b79d71CFC985Da54edD0364");
      //   const ConfigurableRightsPool = await ethers.getContractFactory('ConfigurableRightsPool',
      //   {
      //         libraries:{
      //             // DesynSafeMath:desynSafeMath.address,
      //             // RightsManager:rightsManager.address,
      //             // SmartPoolManager:smartPoolManager.address
      //             DesynSafeMath:"0xbbDE48FB6335471DBc901D545a47Ad4E14c9Ccc3",
      //             RightsManager:"0x8D853dA98c2c208EA6a71e6079c7c5D27C8c9456",
      //             SmartPoolManager:"0xaAB059bb11fC5B36CB54f5cA187AC28eeBBa2cEb"
      //         }}
      //   );
      //   const configurableRightsPool = await ConfigurableRightsPool.attach("0x808A1C433FDA34eEa019FaA6FAE4B273F3837c37");
      //       await configurableRightsPool.claimManagerFee(1);
      //       await hre.run('verify:verify', {
      //    address: "0x2fcaaA215605b5A12b4b49AF5bba47F659Ac655f",
      //    constructorArguments: [],
      // });
          
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
