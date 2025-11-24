const { time, loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ChronosGuardAnchor", function () {
  async function deployFixture() {
    const [admin, guard, recoveryUser, attacker] = await ethers.getSigners();
    const Anchor = await ethers.getContractFactory("ChronosGuardAnchor");
    const anchor = await Anchor.deploy(guard.address, recoveryUser.address);
    return { anchor, guard, recoveryUser, attacker };
  }

  describe("Invariant 3: State Continuity", function () {
    it("Should allow the Guard to update the state", async function () {
      const { anchor, guard } = await loadFixture(deployFixture);
      const newRoot = ethers.keccak256(ethers.toUtf8Bytes("State_V1"));
      
      await expect(anchor.connect(guard).updateStateRoot(newRoot))
        .to.emit(anchor, "StateUpdated");
    });

    it("Should REJECT updates from an Attacker", async function () {
      const { anchor, attacker } = await loadFixture(deployFixture);
      const fakeRoot = ethers.keccak256(ethers.toUtf8Bytes("Malicious_State"));
      
      await expect(anchor.connect(attacker).updateStateRoot(fakeRoot))
        .to.be.revertedWith("Access Denied");
    });
  });

  describe("Invariant 6: Sovereign Resurrection", function () {
    it("Should REJECT recovery before 365 days", async function () {
      const { anchor, recoveryUser } = await loadFixture(deployFixture);
      await expect(anchor.connect(recoveryUser).triggerRecovery())
        .to.be.revertedWith("Active");
    });

    it("Should ALLOW recovery after 365 days of silence", async function () {
      const { anchor, recoveryUser } = await loadFixture(deployFixture);
      
      // Simulate Time Travel (The L6 Proof)
      await time.increase(365 * 24 * 60 * 60 + 1); 

      await expect(anchor.connect(recoveryUser).triggerRecovery())
        .to.emit(anchor, "RecoveryTriggered")
        .withArgs(recoveryUser.address);
    });
  });
});
