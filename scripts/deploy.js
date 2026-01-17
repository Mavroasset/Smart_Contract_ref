const hre = require("hardhat");

const parse = (v) => hre.ethers.parseEther(v.toString());
const fmt = (bn) => hre.ethers.formatEther(bn);

async function main() {
  const Mavro = await hre.ethers.getContractFactory("MavroNewReferralsSystem");

  const cashToken = "0x55d398326f99059fF775485246999027B3197955";
  const rewardToken = "0xaAc5Bf838926347DeF35e565A146fA383106e744";
  const nodeSaleContract = "0x194b70bd02459DacaB89846849D4232fA6E6C33E";
  const stakingContract = "0x2E4CFaaD8961C597f45D548c55cCf3C1d611890d";
  const snapshotAddr = "0xe99155ce9FFa4CB87D2701725c5d4bAc3E25fDeb";

  const mavro = await Mavro.deploy(
    cashToken,
    rewardToken,
    1750941834,
    "383581815723620765695190443",
    "10054903453486845354657361",
    776
  );
  await mavro.waitForDeployment();
  const mavroAddress = await mavro.getAddress();
  console.log("Mavro Referral:", mavroAddress);

  const rcorderRole = await mavro.RECORDER_ROLE();
  const snapshotRole = await mavro.SNAPSHOT_ROLE();

  //role grant
  await (await mavro.grantRole(rcorderRole, nodeSaleContract)).wait();
  await (await mavro.grantRole(snapshotRole, snapshotAddr)).wait();

  // updating contracts
  await (
    await mavro.updateContracts(
      cashToken,
      rewardToken,
      nodeSaleContract,
      stakingContract
    )
  ).wait();

  // updating pools
  // alpha ambassador pool
  await (
    await mavro.updatePool(
      2,
      "55000000000000000000000000",
      "55000000000000000000000000",
      "27500000000000000000000000",
      "27500000000000000000000000",
      "18333333000000000000000000",
      "18333333000000000000000000",
      "18333333000000000000000000"
    )
  ).wait();

  //Country pool

  await (
    await mavro.updatePool(
      3,
      "41250000000000000000000000",
      "41250000000000000000000000",
      "20625000000000000000000000",
      "20625000000000000000000000",
      "13750000000000000000000000",
      "13750000000000000000000000",
      "13750000000000000000000000"
    )
  ).wait();

  //Regional pool

  await (
    await mavro.updatePool(
      4,
      "27500000000000000000000000",
      "27500000000000000000000000",
      "13750000000000000000000000",
      "13750000000000000000000000",
      "9166666000000000000000000",
      "9166666000000000000000000",
      "9166666000000000000000000"
    )
  ).wait();

  //Global pool

  await (
    await mavro.updatePool(
      5,
      "13750000000000000000000000",
      "13750000000000000000000000",
      "6875000000000000000000000",
      "6875000000000000000000000",
      "4583333000000000000000000",
      "4583333000000000000000000",
      "4583333000000000000000000"
    )
  ).wait();

  //co-founder pool

  await (
    await mavro.updatePool(
      6,
      "68750000000000000000000000",
      "68750000000000000000000000",
      "68750000000000000000000000",
      "68750000000000000000000000",
      "91666666666666000000000000",
      "91666666666666000000000000",
      "91666666666666000000000000"
    )
  ).wait();

  // Verify
  console.log("Verifying Mavro Referral...");
  await hre.run("verify:verify", {
    address: mavroAddress,
    constructorArguments: [
      cashToken,
      rewardToken,
      1750941834,
      "383581815723620765695190443",
      "10054903453486845354657361",
      776,
    ], // put args here if needed
  });
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
