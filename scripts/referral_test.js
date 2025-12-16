const { ethers } = require("hardhat");

// ---------- helpers ----------
const parse = (v) => ethers.parseEther(v.toString()); // to wei
const fmt = (bn) => ethers.formatEther(bn); // from wei

async function main() {
  const [deployer, user1, user2, user3, user4, user5, user6, user7, user8] =
    await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // deploy usdt tokens
  const USDT = await ethers.getContractFactory("TestUSDT");
  const usdt = await USDT.deploy(deployer.address);
  await usdt.waitForDeployment();
  console.log("USDT deployed to:", await usdt.getAddress());

  //transfer some usdt to users
  const transferAmount = parse(1000000);

  await usdt.transfer(user1.address, transferAmount);
  await usdt.transfer(user2.address, transferAmount);
  await usdt.transfer(user3.address, transferAmount);
  await usdt.transfer(user4.address, transferAmount);
  await usdt.transfer(user5.address, transferAmount);
  await usdt.transfer(user6.address, transferAmount);
  await usdt.transfer(user7.address, transferAmount);
  await usdt.transfer(user8.address, transferAmount);

  // deploy mavro tokens
  const MAVRO = await ethers.getContractFactory("MavroCoin");
  const mavro = await MAVRO.deploy(deployer.address);

  await mavro.waitForDeployment();
  console.log("MAVRO deployed to:", await mavro.getAddress());

  // deploy nft contract
  const NFT = await ethers.getContractFactory("NodeNFT");
  const nft = await NFT.deploy();
  await nft.waitForDeployment();
  console.log("NFT deployed to:", await nft.getAddress());

  // deploy referral contract
  const Referral = await ethers.getContractFactory("MavroNewReferralsSystem");

  const referral = await Referral.deploy(
    mavro.target,
    usdt.target,
    1765435210,
    565
  );
  await referral.waitForDeployment();
  console.log("Referral deployed to:", await referral.getAddress());

  // deploy node contract
  const Node = await ethers.getContractFactory("MavroNodeSale");
  const node = await Node.deploy(
    usdt.target,
    nft.target,
    referral.target,
    deployer.address
  );

  await node.waitForDeployment();
  console.log("Node deployed to:", await node.getAddress());

  // grant roles
  // grant MINTER_ROLE to Node contract in NFT contract
  const MINTER_ROLE = await nft.MINTER_ROLE();
  await nft.grantRole(MINTER_ROLE, node.target);
  console.log("Granted MINTER_ROLE to Node contract");

  // grant record role to node contract in referral contract
  const RECORD_ROLE = await referral.RECORDER_ROLE();
  await referral.grantRole(RECORD_ROLE, node.target);
  console.log("Granted RECORD_ROLE to Node contract");

  //approve usdt spending for node contract
  const approveAmount = parse(10000000);
  await usdt.connect(user1).approve(node.target, approveAmount);
  await usdt.connect(user2).approve(node.target, approveAmount);
  await usdt.connect(user3).approve(node.target, approveAmount);
  await usdt.connect(user4).approve(node.target, approveAmount);
  await usdt.connect(user5).approve(node.target, approveAmount);
  await usdt.connect(user6).approve(node.target, approveAmount);
  await usdt.connect(user7).approve(node.target, approveAmount);
  await usdt.connect(user8).approve(node.target, approveAmount);
  console.log("Users approved USDT spending for Node contract");

  await referral.connect(deployer).updateMigrationDuration(1);
  await referral.connect(deployer).finalizeMigration();

  // buying nodes
  await node.connect(user1).buyNodes(1, deployer.address);
  console.log("User1 bought a node with deployer as referrer");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
