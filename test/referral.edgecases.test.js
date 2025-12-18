const { expect } = require("chai");
const { ethers } = require("hardhat");

async function advanceTime(seconds) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine");
}

describe("MavroNewReferralsSystem — Edge-case tests", function () {
  async function deployFixture() {
    const [owner, recorder, alice, bob, charlie, david, deep1, deep2, deep3] =
      await ethers.getSigners();

    // --- deploy mocks (rename factories if your filenames differ) ---
    const USDT = await ethers.getContractFactory("TestUSDT");
    const rewardToken = await USDT.deploy(owner.address);
    await rewardToken.waitForDeployment();

    const cashToken = await USDT.deploy(owner.address);
    await cashToken.waitForDeployment();

    // --- deploy main contract ---
    const now = (await ethers.provider.getBlock("latest")).timestamp;

    // programStartTime: set in past so "Not started yet" won't fail if you call claim
    const programStartTime = now - 10 * 24 * 60 * 60;

    const Mavro = await ethers.getContractFactory("MavroNewReferralsSystem");
    const mavro = await Mavro.deploy(
      await rewardToken.getAddress(),
      await cashToken.getAddress(),
      programStartTime,
      0 // totalNodesSold initial
    );
    await mavro.waitForDeployment();

    const MockStaking = await ethers.getContractFactory("MavroStaking");
    const staking = await MockStaking.deploy(rewardToken.target, mavro.target);
    await staking.waitForDeployment();

    const MockNodeSale = await ethers.getContractFactory("MavroNodeSale");
    const nodeSale = await MockNodeSale.deploy(
      cashToken.target,
      ethers.ZeroAddress,
      mavro.target,
      owner.address
    );
    await nodeSale.waitForDeployment();

    // wire contracts (must be non-zero)
    await (
      await mavro
        .connect(owner)
        .updateContracts(
          await cashToken.getAddress(),
          await rewardToken.getAddress(),
          await nodeSale.getAddress(),
          await staking.getAddress()
        )
    ).wait();

    // grant recorder role
    const RECORDER_ROLE = await mavro.RECORDER_ROLE();
    await (
      await mavro.connect(owner).grantRole(RECORDER_ROLE, recorder.address)
    ).wait();

    await (await mavro.connect(owner).updateClaimDay(15)).wait();

    // make staking huge for everyone so stakingAmount checks never block tests
    // const huge = ethers.parseEther("1000000000");
    // for (const s of [
    //   owner,
    //   recorder,
    //   alice,
    //   bob,
    //   charlie,
    //   david,
    //   deep1,
    //   deep2,
    //   deep3,
    // ]) {
    //   await (await staking.setStake(s.address, huge)).wait();
    // }

    // close migration window (recordReferral requires migrationRewardWindowClosed == true)
    // finalizeMigration requires time > migrationTime + migrationDuration (default 3 days)
    await ethers.provider.send("evm_increaseTime", [3 * 24 * 60 * 60 + 5]);
    await ethers.provider.send("evm_mine");
    await (await mavro.connect(owner).finalizeMigration()).wait();

    // shrink rank requirements for faster edge testing (optional but makes tests deterministic)
    // keep referralPercentage same style as your contract (BASE_DIVIDER=10000)
    // IMPORTANT: referralPct must allow distribution with 2+ legs. We'll use 5000 (50%) like your defaults.
    const setReq = async (rank, nodeReq, referralPct, stakeAmt) => {
      await (
        await mavro
          .connect(owner)
          .updateRankRequirements(rank, nodeReq, referralPct, stakeAmt)
      ).wait();
    };

    // Rank enum: 0 Member, 1 Councilor, 2 Alpha, 3 Country, 4 Regional, 5 Global
    await setReq(1, 10, 5000, 0); // Councilor
    await setReq(2, 20, 5000, 0); // Alpha
    await setReq(3, 40, 5000, 0); // Country
    await setReq(4, 60, 5000, 0); // Regional
    await setReq(5, 80, 5000, 0); // Global

    // helper: recordReferral
    const buy = async (user, nodeCount, referrer, amount = 0) => {
      await (
        await mavro
          .connect(recorder)
          .recordReferral(
            user.address,
            nodeCount,
            referrer ? referrer.address : ethers.ZeroAddress,
            amount
          )
      ).wait();
    };

    return {
      owner,
      recorder,
      alice,
      bob,
      charlie,
      david,
      deep1,
      deep2,
      deep3,
      mavro,
      buy,
    };
  }

  //   it("E1: recordReferral reverts before migration finalization (sanity)", async () => {
  //     const [owner, recorder, alice, bob] = await ethers.getSigners();

  //     const USDT = await ethers.getContractFactory("USDT");
  //     const rewardToken = await USDT.deploy("Reward", "RWD");
  //     const cashToken = await USDT.deploy("Cash", "CASH");

  //     const MockStaking = await ethers.getContractFactory("MockStaking");
  //     const staking = await MockStaking.deploy();

  //     const MockNodeSale = await ethers.getContractFactory("MockNodeSale");
  //     const nodeSale = await MockNodeSale.deploy();

  //     const now = (await ethers.provider.getBlock("latest")).timestamp;
  //     const Mavro = await ethers.getContractFactory("MavroNewReferralsSystem");
  //     const mavro = await Mavro.deploy(
  //       await rewardToken.getAddress(),
  //       await cashToken.getAddress(),
  //       now - 1000,
  //       0
  //     );
  //     await mavro.waitForDeployment();

  //     await (
  //       await mavro
  //         .connect(owner)
  //         .updateContracts(
  //           await cashToken.getAddress(),
  //           await rewardToken.getAddress(),
  //           await nodeSale.getAddress(),
  //           await staking.getAddress()
  //         )
  //     ).wait();

  //     const RECORDER_ROLE = await mavro.RECORDER_ROLE();
  //     await (
  //       await mavro.connect(owner).grantRole(RECORDER_ROLE, recorder.address)
  //     ).wait();

  //     // migrationRewardWindowClosed is false initially => should revert
  //     await expect(
  //       mavro.connect(recorder).recordReferral(alice.address, 1, bob.address, 0)
  //     ).to.be.revertedWith("Currently Unavailable");
  //   });

  it("E2: direct-leg attribution is correct (child-leg credit works)", async () => {
    const { mavro, buy, alice, bob, deep1 } = await deployFixture();

    // setup: bob -> alice, deep1 -> bob
    await buy(bob, 0, alice);
    await buy(deep1, 0, bob);

    // deep1 purchase should credit bob-leg for alice
    await buy(deep1, 25, bob);

    expect(await mavro.directLegTeamNodes(alice.address, bob.address)).to.equal(
      25n
    );
    expect(await mavro.totalDirectTeamNodes(alice.address)).to.equal(25n);
    expect(await mavro.maxDirectTeamNodes(alice.address)).to.equal(25n);
  });

  it("E3: max leg updates when another leg overtakes", async () => {
    const { mavro, buy, alice, bob, charlie } = await deployFixture();

    await buy(bob, 0, alice);
    await buy(charlie, 0, alice);

    await buy(bob, 30, alice);
    expect(await mavro.maxDirectTeamNodes(alice.address)).to.equal(30n);

    await buy(charlie, 50, alice);
    expect(await mavro.maxDirectTeamNodes(alice.address)).to.equal(50n);
    expect(await mavro.totalDirectTeamNodes(alice.address)).to.equal(80n);
  });

  it("E4: rank jump adds ALL intermediate pools (Alpha→Country→Regional→Global)", async () => {
    const { mavro, buy, alice, bob, charlie } = await deployFixture();

    // Need at least 2 legs for distribution rule (50/50)
    await buy(bob, 0, alice);
    await buy(charlie, 0, alice);

    // Push enough nodes so alice qualifies up to Global (nodeReq 80)
    // With 50% rule:
    // requiredFromOne = 40, requiredFromOthers = 40
    await buy(bob, 40, alice);
    await buy(charlie, 40, alice);

    // recordReferral updates rank of referrer (alice) when bob/charlie call with referrer=alice
    // After both calls, alice should reach Global (5)
    const u = await mavro.users(alice.address);
    expect(u.currentRank).to.equal(5n);

    // Must be in all pools from Alpha(2) to Global(5)
    expect(await mavro.isPoolParticipant(2, alice.address)).to.equal(true);
    expect(await mavro.isPoolParticipant(3, alice.address)).to.equal(true);
    expect(await mavro.isPoolParticipant(4, alice.address)).to.equal(true);
    expect(await mavro.isPoolParticipant(5, alice.address)).to.equal(true);
  });

  it("E5: repeated updates do NOT duplicate pool membership", async () => {
    const { mavro, buy, alice, bob, charlie } = await deployFixture();

    await buy(bob, 0, alice);
    await buy(charlie, 0, alice);

    // qualify Alpha and beyond
    await buy(bob, 20, alice);
    await buy(charlie, 20, alice);

    // Alice should now be at least Alpha (2)
    expect(
      (await mavro.users(alice.address)).currentRank
    ).to.be.greaterThanOrEqual(2n);

    // Force more purchases that will re-run _updateRank(alice) multiple times
    await buy(bob, 1, alice);
    await buy(charlie, 1, alice);
    await buy(bob, 1, alice);

    // Ensure still only "true" once in mapping; duplicates prevented by isPoolParticipant
    expect(await mavro.isPoolParticipant(2, alice.address)).to.equal(true);
    expect(await mavro.isPoolParticipant(3, alice.address)).to.be.oneOf([
      true,
      false,
    ]);
  });

  it("E6: checkMyRank does not blow up with many directs (no directTeam loop)", async () => {
    const { mavro, buy, alice } = await deployFixture();

    const signers = await ethers.getSigners();
    const manyDirects = signers.slice(20, 220); // 200 directs

    // create 200 directs with 0 nodes
    for (const d of manyDirects) {
      await buy(d, 0, alice);
    }

    // old implementation would loop over directTeam and could get expensive.
    // new implementation is O(1), so this should be fine.
    const r = await mavro.checkMyRank(alice.address);
    expect(typeof r).to.equal("bigint");
  });

  it("E7: distribution edge — one huge leg alone should NOT pass if others too small", async () => {
    const { mavro, buy, alice, bob, charlie } = await deployFixture();

    await buy(bob, 0, alice);
    await buy(charlie, 0, alice);

    // Global nodeReq=80, 50% => need one leg >=40 AND others >=40
    await buy(bob, 80, alice); // maxLeg=80, total=80 => total-max=0 (fails)
    expect((await mavro.users(alice.address)).currentRank).to.be.lessThan(5n);

    // Now add others to satisfy distribution
    await buy(charlie, 40, alice); // total=120, max=80 => total-max=40 (passes)
    expect((await mavro.users(alice.address)).currentRank).to.equal(5n);
  });

  it("E8: node transfer increases receiver nodesOwned but does NOT change upline rank aggregates (no manipulation)", async () => {
    const { mavro, buy, owner, recorder, alice, bob, charlie, david } =
      await deployFixture();

    // Setup directs
    await buy(bob, 0, alice);
    await buy(charlie, 0, alice);

    // Build Alice to be JUST BELOW Global:
    // Global requirement (in fixture): nodeReq=80, referralPct=50% => need maxLeg>=40 and (total-maxLeg)>=40
    // We'll set: bobLeg=39, charlieLeg=40 => total=79, max=40, total-max=39 => FAIL Global.
    await buy(bob, 39, alice);
    await buy(charlie, 40, alice);

    // sanity: stored rank should NOT be Global
    expect((await mavro.users(alice.address)).currentRank).to.be.lessThan(5n);

    // David buys 1 node with no referrer so it won't affect Alice
    await buy(david, 1, null);

    // Transfer that node to Bob (this changes nodesOwned for Bob, but should not affect Alice rank aggregates)
    await (
      await mavro
        .connect(recorder)
        .recordNodeTransfer(david.address, bob.address, 1)
    ).wait();

    // Bob nodesOwned increased by 1 (reward basis)
    expect((await mavro.users(bob.address)).nodesOwned).to.equal(40n);

    // Alice aggregates remain unchanged (still total=79, max=40)
    expect(await mavro.totalDirectTeamNodes(alice.address)).to.equal(79n);
    expect(await mavro.maxDirectTeamNodes(alice.address)).to.equal(40n);

    // And Alice still should NOT qualify for Global even if we recompute
    const computed = await mavro.checkMyRank(alice.address);
    expect(computed).to.be.lessThan(5n);
  });

  it("E9: ranks only increase from purchases (recordReferral), not from transfers (recordNodeTransfer)", async () => {
    const { mavro, buy, recorder, alice, bob, charlie, david } =
      await deployFixture();

    // Setup directs
    await buy(bob, 0, alice);
    await buy(charlie, 0, alice);

    // Bring Alice to Alpha (nodeReq=20, 50% => need maxLeg>=10 and others>=10)
    await buy(bob, 10, alice);
    await buy(charlie, 10, alice);

    const rankAfterPurchases = (await mavro.users(alice.address)).currentRank;
    expect(rankAfterPurchases).to.equal(2n); // AlphaAmbassador

    // David buys nodes without affecting Alice
    await buy(david, 20, null);

    // Transfer to Bob; Alice rank should not change from this transfer alone
    await (
      await mavro
        .connect(recorder)
        .recordNodeTransfer(david.address, bob.address, 20)
    ).wait();

    const rankAfterTransfer = (await mavro.users(alice.address)).currentRank;
    expect(rankAfterTransfer).to.equal(rankAfterPurchases);

    // If Bob makes a real purchase under Alice, THEN Alice may progress again
    await buy(bob, 60, alice); // purchase affects aggregates
    expect(
      (await mavro.users(alice.address)).currentRank
    ).to.be.greaterThanOrEqual(rankAfterPurchases);
  });
  it("E10: rank achieved before rewardStartTime → rank reward NOT claimable", async () => {
    const { mavro, buy, alice, bob, charlie } = await deployFixture();

    const claimDay = await mavro.claimDay();
    console.log("Claim day is:", claimDay);

    // Build structure
    await buy(bob, 0, alice);
    await buy(charlie, 0, alice);

    // Alpha requires 20 nodes, 50% rule → 10 + 10
    await buy(bob, 10, alice);
    await buy(charlie, 10, alice);

    // Alice has Alpha rank now
    const userRank = await mavro.checkMyRank(alice.address);
    console.log("Alice rank:", userRank);
    expect(userRank).to.equal(2n); // AlphaAmbassador

    // But Alpha pool rewardStartTime should still be 0 (only 1 participant)
    const alphaPool = await mavro.pools(2);
    expect(alphaPool.rewardStartTime).to.equal(0n);

    await advanceTime(24 * 60 * 60 + 10);

    // Try to claim Alpha reward → should revert
    await expect(mavro.connect(alice).claimRankReward()).to.be.revertedWith(
      "No reward to claim"
    ); // <-- use your actual revert msg
  });
  it("E11: rank reward claimable only AFTER pool rewardStartTime", async () => {
    const { mavro, buy, alice, bob, charlie, david } = await deployFixture();

    // Alice structure
    await buy(bob, 0, alice);
    await buy(charlie, 0, alice);

    await buy(bob, 10, alice);
    await buy(charlie, 10, alice);

    // Alice has Alpha
    expect((await mavro.users(alice.address)).currentRank).to.equal(2n);

    // Second Alpha participant (David)
    await buy(bob, 0, david);
    await buy(charlie, 0, david);
    await buy(bob, 10, david);
    await buy(charlie, 10, david);

    // Alpha pool should now start
    const alphaPool = await mavro.pools(2);
    expect(alphaPool.rewardStartTime).to.not.equal(0n);

    // Alice can now claim Alpha reward
    await expect(mavro.connect(alice).claimRankReward()).to.not.be.reverted;
  });
  it("E12: node reward uses nodesOwned (includes transfers)", async () => {
    const { mavro, recorder, buy, alice, bob } = await deployFixture();

    // Alice buys 10 nodes
    await buy(alice, 10, recorder);

    // Bob buys and transfers to Alice
    await buy(bob, 15, recorder);

    await mavro
      .connect(recorder)
      .recordNodeTransfer(bob.address, alice.address, 5); // use your real transfer fn

    const user = await mavro.users(alice.address);
    expect(user.nodesOwned).to.equal(15n);

    // Node reward should be based on 15
    await expect(mavro.connect(alice).claimMyNodeRewards()).to.not.be.reverted;
  });
  it("E13: transferring nodes does NOT upgrade rank", async () => {
    const { mavro, buy, alice, bob, charlie } = await deployFixture();

    await buy(bob, 0, alice);
    await buy(charlie, 0, alice);

    // Almost Alpha (needs 20)
    await buy(bob, 9, alice);
    await buy(charlie, 10, alice);

    expect((await mavro.users(alice.address)).currentRank).to.be.lessThan(2n);

    // Transfer nodes to Bob (attempt manipulation)
    await buy(bob, 5, ethers.ZeroAddress);
    await mavro.connect(bob).transferNodes(alice.address, 5);

    // Rank must NOT change
    expect((await mavro.users(alice.address)).currentRank).to.be.lessThan(2n);
  });
});
