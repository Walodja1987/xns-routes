import { expect } from "chai";
import hre from "hardhat";
import "@nomicfoundation/hardhat-ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import type { MockXNS, SponsoredRoutes, XNSRoutes } from "../typechain-types";

describe("SponsoredRoutes", function () {
  const { ethers } = hre;

  const LABEL = "gifts";
  const NAMESPACE = "sponsor";
  const ROUTE_LABEL = "alice";
  const RT0 = 0;

  /** Matches `require(..., "...")` strings in `SponsoredRoutes.sol` and `XNSRoutes.sol`. */
  const SR = {
    zeroXnsAddress: "SponsoredRoutes: 0x XNS address",
    zeroXnsRoutesAddress: "SponsoredRoutes: 0x XNSRoutes",
  } as const;
  const XR = {
    invalidRouteLabel: "XNSRoutes: invalid route label",
    invalidTarget: "XNSRoutes: invalid target",
    notXnsNameOwner: "XNSRoutes: not XNS name owner",
    routeBookClosed: "XNSRoutes: route book closed",
    routeAlreadyExists: "XNSRoutes: route already exists",
  } as const;

  function xnsNameKey(label: string, namespace: string): string {
    return ethers.solidityPackedKeccak256(["string", "string", "string"], [label, "@", namespace]);
  }

  function routeStorageKey(label: string, namespace: string, routeLabel: string): string {
    return ethers.solidityPackedKeccak256(
      ["string", "string", "string", "string", "string"],
      [label, "@", namespace, "/", routeLabel],
    );
  }

  async function deployFixture() {
    const [contractOwner, sponsor, other] = await ethers.getSigners();

    const mockXns = (await ethers.deployContract("MockXNS")) as unknown as MockXNS;
    const mockAddr = String(mockXns.target);

    const routes = (await ethers.deployContract("XNSRoutes", [
      contractOwner.address,
      mockAddr,
    ])) as unknown as XNSRoutes;

    const sponsored = (await ethers.deployContract("SponsoredRoutes", [
      sponsor.address,
      mockAddr,
      String(routes.target),
      LABEL,
      NAMESPACE,
    ])) as unknown as SponsoredRoutes;

    const target = ethers.hexlify(ethers.getBytes(ethers.Wallet.createRandom().address));

    return { mockXns, routes, sponsored, sponsor, other, target };
  }

  describe("constructor", function () {
    it("Should register the XNS name to the contract itself", async function () {
      const { mockXns, sponsored } = await loadFixture(deployFixture);
      expect(await mockXns["getAddress(string,string)"](LABEL, NAMESPACE)).to.equal(
        String(sponsored.target),
      );
    });

    it("Should store the owner, registry and XNS name", async function () {
      const { routes, sponsored, sponsor } = await loadFixture(deployFixture);
      expect(await sponsored.owner()).to.equal(sponsor.address);
      expect(await sponsored.XNS_ROUTES()).to.equal(String(routes.target));
      expect(await sponsored.xnsLabel()).to.equal(LABEL);
      expect(await sponsored.xnsNamespace()).to.equal(NAMESPACE);
    });

    it("Should revert when xnsContract is the zero address", async function () {
      const { routes, sponsor } = await loadFixture(deployFixture);
      const factory = await ethers.getContractFactory("SponsoredRoutes");
      await expect(
        factory.deploy(
          sponsor.address,
          ethers.ZeroAddress,
          String(routes.target),
          LABEL,
          NAMESPACE,
        ),
      ).to.be.revertedWith(SR.zeroXnsAddress);
    });

    it("Should revert when xnsRoutesContract is the zero address", async function () {
      const { mockXns, sponsor } = await loadFixture(deployFixture);
      const factory = await ethers.getContractFactory("SponsoredRoutes");
      await expect(
        factory.deploy(
          sponsor.address,
          String(mockXns.target),
          ethers.ZeroAddress,
          LABEL,
          NAMESPACE,
        ),
      ).to.be.revertedWith(SR.zeroXnsRoutesAddress);
    });

    it("Should revert when initialOwner is the zero address", async function () {
      const { mockXns, routes } = await loadFixture(deployFixture);
      const factory = await ethers.getContractFactory("SponsoredRoutes");
      await expect(
        factory.deploy(
          ethers.ZeroAddress,
          String(mockXns.target),
          String(routes.target),
          LABEL,
          NAMESPACE,
        ),
      )
        .to.be.revertedWithCustomError(factory, "OwnableInvalidOwner")
        .withArgs(ethers.ZeroAddress);
    });
  });

  describe("sponsorRoute", function () {
    it("Should create a frozen, active route and emit RouteCreated then RouteFrozen", async function () {
      const { routes, sponsored, sponsor, target } = await loadFixture(deployFixture);
      const nameKey = xnsNameKey(LABEL, NAMESPACE);
      const routeKey = routeStorageKey(LABEL, NAMESPACE, ROUTE_LABEL);

      const tx = sponsored.connect(sponsor).sponsorRoute(ROUTE_LABEL, target, RT0);
      await expect(tx)
        .to.emit(routes, "RouteCreated")
        .withArgs(nameKey, routeKey, ethers.keccak256(target), LABEL, NAMESPACE, ROUTE_LABEL, RT0);
      await expect(tx)
        .to.emit(routes, "RouteFrozen")
        .withArgs(nameKey, routeKey, LABEL, NAMESPACE, ROUTE_LABEL);

      const record = await routes["getRouteRecord(string,string,string)"](
        LABEL,
        NAMESPACE,
        ROUTE_LABEL,
      );
      expect(record.target).to.equal(target);
      expect(record.isActive).to.equal(true);
      expect(record.isFrozen).to.equal(true);
    });

    it("Should make the route immediately resolvable", async function () {
      const { routes, sponsored, sponsor, target } = await loadFixture(deployFixture);
      await sponsored.connect(sponsor).sponsorRoute(ROUTE_LABEL, target, RT0);

      const [resolvedTarget, routeType] = await routes["resolveRoute(string)"](
        `${LABEL}@${NAMESPACE}/${ROUTE_LABEL}`,
      );
      expect(resolvedTarget).to.equal(target);
      expect(routeType).to.equal(RT0);
    });

    it("Should revert when the caller is not the owner", async function () {
      const { sponsored, other, target } = await loadFixture(deployFixture);
      await expect(sponsored.connect(other).sponsorRoute(ROUTE_LABEL, target, RT0))
        .to.be.revertedWithCustomError(sponsored, "OwnableUnauthorizedAccount")
        .withArgs(other.address);
    });

    it("Should bubble up XNSRoutes validation errors", async function () {
      const { sponsored, sponsor, target } = await loadFixture(deployFixture);
      await expect(sponsored.connect(sponsor).sponsorRoute("Bad", target, RT0)).to.be.revertedWith(
        XR.invalidRouteLabel,
      );
      await expect(
        sponsored.connect(sponsor).sponsorRoute(ROUTE_LABEL, "0x", RT0),
      ).to.be.revertedWith(XR.invalidTarget);
    });

    it("Should revert when the route already exists", async function () {
      const { sponsored, sponsor, target } = await loadFixture(deployFixture);
      await sponsored.connect(sponsor).sponsorRoute(ROUTE_LABEL, target, RT0);
      await expect(
        sponsored.connect(sponsor).sponsorRoute(ROUTE_LABEL, target, RT0),
      ).to.be.revertedWith(XR.routeAlreadyExists);
    });
  });

  describe("closeRouteBook", function () {
    it("Should close the route book and block further sponsorships", async function () {
      const { routes, sponsored, sponsor, target } = await loadFixture(deployFixture);
      await sponsored.connect(sponsor).sponsorRoute(ROUTE_LABEL, target, RT0);

      await expect(sponsored.connect(sponsor).closeRouteBook())
        .to.emit(routes, "RouteBookClosed")
        .withArgs(xnsNameKey(LABEL, NAMESPACE), LABEL, NAMESPACE);

      expect(await routes["isRouteBookClosed(string,string)"](LABEL, NAMESPACE)).to.equal(true);
      await expect(sponsored.connect(sponsor).sponsorRoute("bob", target, RT0)).to.be.revertedWith(
        XR.routeBookClosed,
      );

      const [resolvedTarget] = await routes["resolveRoute(string,string,string)"](
        LABEL,
        NAMESPACE,
        ROUTE_LABEL,
      );
      expect(resolvedTarget).to.equal(target);
    });

    it("Should revert when the caller is not the owner", async function () {
      const { sponsored, other } = await loadFixture(deployFixture);
      await expect(sponsored.connect(other).closeRouteBook())
        .to.be.revertedWithCustomError(sponsored, "OwnableUnauthorizedAccount")
        .withArgs(other.address);
    });
  });

  describe("permanence guarantee", function () {
    it("Should not expose any function that could change, deactivate or forward calls", async function () {
      const { sponsored } = await loadFixture(deployFixture);
      const functionNames: string[] = [];
      sponsored.interface.forEachFunction((fn) => functionNames.push(fn.name));

      expect(functionNames.sort()).to.deep.equal(
        [
          "XNS_ROUTES",
          "acceptOwnership",
          "closeRouteBook",
          "owner",
          "pendingOwner",
          "renounceOwnership",
          "sponsorRoute",
          "transferOwnership",
          "xnsLabel",
          "xnsNamespace",
        ].sort(),
      );
    });

    it("Should not let the owner manage routes directly on XNSRoutes", async function () {
      const { routes, sponsored, sponsor, target } = await loadFixture(deployFixture);
      await sponsored.connect(sponsor).sponsorRoute(ROUTE_LABEL, target, RT0);

      await expect(
        routes.connect(sponsor).deactivateRoute(LABEL, NAMESPACE, ROUTE_LABEL),
      ).to.be.revertedWith(XR.notXnsNameOwner);
    });

    it("Should keep existing routes resolvable after ownership is renounced", async function () {
      const { routes, sponsored, sponsor, target } = await loadFixture(deployFixture);
      await sponsored.connect(sponsor).sponsorRoute(ROUTE_LABEL, target, RT0);
      await sponsored.connect(sponsor).renounceOwnership();

      expect(await sponsored.owner()).to.equal(ethers.ZeroAddress);
      await expect(
        sponsored.connect(sponsor).sponsorRoute("bob", target, RT0),
      ).to.be.revertedWithCustomError(sponsored, "OwnableUnauthorizedAccount");

      const [resolvedTarget] = await routes["resolveRoute(string,string,string)"](
        LABEL,
        NAMESPACE,
        ROUTE_LABEL,
      );
      expect(resolvedTarget).to.equal(target);
    });
  });
});
