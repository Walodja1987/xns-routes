import { expect } from "chai";
import hre from "hardhat";
import "@nomicfoundation/hardhat-ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import type { InboundBlockRegistry } from "../typechain-types/InboundBlockRegistry";

describe("InboundBlockRegistry", function () {
  const { ethers } = hre;

  // Types
  interface SetupOutput {
    inboundBlockRegistry: InboundBlockRegistry;
    deployer: SignerWithAddress;
    user1: SignerWithAddress;
    user2: SignerWithAddress;
  }

  // Test setup function
  async function setup(): Promise<SetupOutput> {
    const [deployer, user1, user2] = await ethers.getSigners();
    const deployed = await ethers.deployContract("InboundBlockRegistry");
    await deployed.waitForDeployment();
    const inboundBlockRegistry = (await ethers.getContractAt(
      "InboundBlockRegistry",
      await deployed.getAddress(),
    )) as unknown as InboundBlockRegistry;

    return {
      inboundBlockRegistry,
      deployer,
      user1,
      user2,
    };
  }

  describe("isInboundBlocked", function () {
    let s: SetupOutput;

    beforeEach(async () => {
      s = await loadFixture(setup);
    });

    it("Should return false for addresses that have not blocked inbound transfers", async () => {
      // ---------
      // Assert: No account is blocked by default
      // ---------
      expect(await s.inboundBlockRegistry.isInboundBlocked(s.deployer.address)).to.equal(false);
      expect(await s.inboundBlockRegistry.isInboundBlocked(s.user1.address)).to.equal(false);
      expect(await s.inboundBlockRegistry.isInboundBlocked(s.user2.address)).to.equal(false);
    });

    it("Should return true only for the account that called `blockInboundForever`", async () => {
      // ---------
      // Act: user1 blocks inbound transfers for itself
      // ---------
      await s.inboundBlockRegistry.connect(s.user1).blockInboundForever();

      // ---------
      // Assert: user1 is blocked, others are unchanged
      // ---------
      expect(await s.inboundBlockRegistry.isInboundBlocked(s.user1.address)).to.equal(true);
      expect(await s.inboundBlockRegistry.isInboundBlocked(s.deployer.address)).to.equal(false);
      expect(await s.inboundBlockRegistry.isInboundBlocked(s.user2.address)).to.equal(false);
    });
  });

  describe("blockInboundForever", function () {
    let s: SetupOutput;

    beforeEach(async () => {
      s = await loadFixture(setup);
    });

    it("Should mark `msg.sender` as blocked forever", async () => {
      // ---------
      // Act: deployer blocks inbound transfers
      // ---------
      await s.inboundBlockRegistry.connect(s.deployer).blockInboundForever();

      // ---------
      // Assert: deployer is permanently marked as blocked
      // ---------
      expect(await s.inboundBlockRegistry.isInboundBlocked(s.deployer.address)).to.equal(true);
    });

    it("Should emit `InboundBlockedForever` event with `msg.sender`", async () => {
      // ---------
      // Act: user2 blocks inbound transfers
      // ---------
      // ---------
      // Assert: expected event is emitted with user2 as account
      // ---------
      await expect(s.inboundBlockRegistry.connect(s.user2).blockInboundForever())
        .to.emit(s.inboundBlockRegistry, "InboundBlockedForever")
        .withArgs(s.user2.address);
    });

    it("Should revert with `AlreadyBlocked` when calling `blockInboundForever` twice", async () => {
      // ---------
      // Arrange: user1 already blocked inbound transfers
      // ---------
      await s.inboundBlockRegistry.connect(s.user1).blockInboundForever();

      // ---------
      // Act & Assert: second call reverts with custom error
      // ---------
      let didRevert = false;
      try {
        await s.inboundBlockRegistry.connect(s.user1).blockInboundForever();
      } catch (error: unknown) {
        didRevert = true;
        const message = error instanceof Error ? error.message : String(error);
        expect(message).to.include("AlreadyBlocked");
      }

      expect(didRevert).to.equal(true);
    });

    it("Should allow multiple different accounts to block themselves independently", async () => {
      // ---------
      // Act: different users block independently
      // ---------
      await s.inboundBlockRegistry.connect(s.deployer).blockInboundForever();
      await s.inboundBlockRegistry.connect(s.user1).blockInboundForever();

      // ---------
      // Assert: both callers are blocked, untouched account remains unblocked
      // ---------
      expect(await s.inboundBlockRegistry.isInboundBlocked(s.deployer.address)).to.equal(true);
      expect(await s.inboundBlockRegistry.isInboundBlocked(s.user1.address)).to.equal(true);
      expect(await s.inboundBlockRegistry.isInboundBlocked(s.user2.address)).to.equal(false);
    });
  });

  describe("setGuardian", function () {
    let s: SetupOutput;

    beforeEach(async () => {
      s = await loadFixture(setup);
    });

    it("Should set guardian and emit `GuardianSet`", async () => {
      await expect(s.inboundBlockRegistry.connect(s.user1).setGuardian(s.user2.address))
        .to.emit(s.inboundBlockRegistry, "GuardianSet")
        .withArgs(s.user1.address, s.user2.address);

      expect(await s.inboundBlockRegistry.getGuardianOf(s.user1.address)).to.equal(
        s.user2.address,
      );
    });

    it("Should allow changing guardian", async () => {
      await s.inboundBlockRegistry.connect(s.user1).setGuardian(s.user2.address);
      await s.inboundBlockRegistry.connect(s.user1).setGuardian(s.deployer.address);

      expect(await s.inboundBlockRegistry.getGuardianOf(s.user1.address)).to.equal(
        s.deployer.address,
      );
    });

    it("Should revert with `InvalidGuardian` when guardian is zero address", async () => {
      await expect(
        s.inboundBlockRegistry.connect(s.user1).setGuardian(ethers.ZeroAddress),
      ).to.be.revertedWithCustomError(s.inboundBlockRegistry, "InvalidGuardian");
    });

    it("Should revert with `InvalidGuardian` when guardian is `msg.sender`", async () => {
      await expect(
        s.inboundBlockRegistry.connect(s.user1).setGuardian(s.user1.address),
      ).to.be.revertedWithCustomError(s.inboundBlockRegistry, "InvalidGuardian");
    });

    it("Should revert with `BlockedAccount` when blocked account tries to set guardian", async () => {
      await s.inboundBlockRegistry.connect(s.user1).blockInboundForever();

      await expect(
        s.inboundBlockRegistry.connect(s.user1).setGuardian(s.user2.address),
      ).to.be.revertedWithCustomError(s.inboundBlockRegistry, "BlockedAccount");
    });
  });

  describe("getGuardianOf", function () {
    let s: SetupOutput;

    beforeEach(async () => {
      s = await loadFixture(setup);
    });

    it("Should return zero address by default", async () => {
      expect(await s.inboundBlockRegistry.getGuardianOf(s.user1.address)).to.equal(
        ethers.ZeroAddress,
      );
    });

    it("Should return latest configured guardian", async () => {
      await s.inboundBlockRegistry.connect(s.user1).setGuardian(s.user2.address);
      await s.inboundBlockRegistry.connect(s.user1).setGuardian(s.deployer.address);

      expect(await s.inboundBlockRegistry.getGuardianOf(s.user1.address)).to.equal(
        s.deployer.address,
      );
    });
  });

  describe("blockInboundForeverFor", function () {
    let s: SetupOutput;

    beforeEach(async () => {
      s = await loadFixture(setup);
    });

    it("Should allow configured guardian to block account", async () => {
      await s.inboundBlockRegistry.connect(s.user1).setGuardian(s.user2.address);

      await expect(
        s.inboundBlockRegistry.connect(s.user2).blockInboundForeverFor(s.user1.address),
      )
        .to.emit(s.inboundBlockRegistry, "InboundBlockedForever")
        .withArgs(s.user1.address);

      expect(await s.inboundBlockRegistry.isInboundBlocked(s.user1.address)).to.equal(true);
    });

    it("Should revert with `NotGuardian` when caller is not configured guardian", async () => {
      await s.inboundBlockRegistry.connect(s.user1).setGuardian(s.user2.address);

      await expect(
        s.inboundBlockRegistry.connect(s.deployer).blockInboundForeverFor(s.user1.address),
      )
        .to.be.revertedWithCustomError(s.inboundBlockRegistry, "NotGuardian")
        .withArgs(s.user1.address);
    });

    it("Should revert with `AlreadyBlocked` when guardian tries to block twice", async () => {
      await s.inboundBlockRegistry.connect(s.user1).setGuardian(s.user2.address);
      await s.inboundBlockRegistry.connect(s.user2).blockInboundForeverFor(s.user1.address);

      await expect(
        s.inboundBlockRegistry.connect(s.user2).blockInboundForeverFor(s.user1.address),
      ).to.be.revertedWithCustomError(s.inboundBlockRegistry, "AlreadyBlocked");
    });
  });

});